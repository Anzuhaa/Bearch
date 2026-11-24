-- Peer ratings -> single reputation score, reports & appeals, SEP claims,
-- admin dashboard stats.
--
-- Reputation is ONE number (no separate activity score):
--   avg(peer rating score)  - 0.25 per upheld report against you
--                           - 0.25 per report you filed that admins marked false
--   clamped to [1, 5]; NULL until the first rating.

alter table public.reports add column false_report boolean not null default false;

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------
create or replace function public.recompute_reputation(p_profile uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_avg numeric;
  v_count integer;
  v_penalty numeric;
begin
  select avg(score), count(*) into v_avg, v_count
    from public.peer_ratings where ratee_id = p_profile;

  select 0.25 * (
           (select count(*) from public.reports where reported_id = p_profile and status = 'upheld')
         + (select count(*) from public.reports where reporter_id = p_profile and false_report)
         )
    into v_penalty;

  update public.profiles
     set reputation = case when v_count = 0 then null
                           else greatest(1, least(5, round(v_avg - v_penalty, 2))) end,
         rating_count = v_count
   where id = p_profile;
end;
$$;

-- Ratings open once the team is locked and the competition is over
-- (event_end, or the registration deadline if no event dates were given).
create or replace function public.can_rate_team(p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.teams t
      join public.competitions c on c.id = t.competition_id
     where t.id = p_team
       and t.status = 'locked'
       and public.today_wib() >= coalesce(c.event_end, c.registration_deadline)
  );
$$;

-- p_skill_tiers: [{"skill_id": uuid, "tier": 1..4}]   (novice..expert)
-- p_criteria:    {"communication": 1..5, "time_management": 1..5,
--                 "teamwork": 1..5, "responsibility": 1..5}
create or replace function public.submit_rating(
  p_team uuid,
  p_ratee uuid,
  p_skill_tiers jsonb,
  p_criteria jsonb,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_rating uuid;
  v_score numeric;
  v_crit text;
begin
  if not public.is_team_member(p_team) then
    raise exception 'You are not in this team.' using errcode = '42501';
  end if;
  if p_ratee = v_uid or not exists (
    select 1 from public.team_members m where m.team_id = p_team and m.profile_id = p_ratee
  ) then
    raise exception 'You can only rate your teammates.' using errcode = 'P0001';
  end if;
  if not public.can_rate_team(p_team) then
    raise exception 'Ratings open after the competition is over.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.sep_claims s where s.team_id = p_team) then
    raise exception 'Ratings are final once the SEP claim is submitted.' using errcode = 'P0001';
  end if;

  foreach v_crit in array array['communication', 'time_management', 'teamwork', 'responsibility'] loop
    if coalesce((p_criteria ->> v_crit)::integer, 0) not between 1 and 5 then
      raise exception 'Give 1-5 stars for %.', replace(v_crit, '_', ' ') using errcode = 'P0001';
    end if;
  end loop;

  select avg(value::integer) into v_score from jsonb_each_text(p_criteria)
   where key in ('communication', 'time_management', 'teamwork', 'responsibility');

  insert into public.peer_ratings (team_id, rater_id, ratee_id, score, comment)
  values (p_team, v_uid, p_ratee, round(v_score, 2), nullif(trim(p_comment), ''))
  on conflict (team_id, rater_id, ratee_id)
  do update set score = excluded.score, comment = excluded.comment, created_at = now()
  returning id into v_rating;

  delete from public.peer_rating_criteria where rating_id = v_rating;
  insert into public.peer_rating_criteria (rating_id, criterion, stars)
  select v_rating, key, value::smallint from jsonb_each_text(p_criteria)
   where key in ('communication', 'time_management', 'teamwork', 'responsibility');

  delete from public.peer_rating_skills where rating_id = v_rating;
  insert into public.peer_rating_skills (rating_id, skill_id, tier)
  select v_rating, (e ->> 'skill_id')::uuid, (e ->> 'tier')::smallint
    from jsonb_array_elements(coalesce(p_skill_tiers, '[]'::jsonb)) e
   where (e ->> 'tier')::integer between 1 and 4
  on conflict do nothing;

  -- Refresh peer-verified skill levels for the ratee.
  update public.profile_skills ps
     set peer_level = agg.avg_tier, peer_count = agg.n
    from (
      select rs.skill_id, round(avg(rs.tier), 2) as avg_tier, count(*)::integer as n
        from public.peer_rating_skills rs
        join public.peer_ratings r on r.id = rs.rating_id
       where r.ratee_id = p_ratee
       group by rs.skill_id
    ) agg
   where ps.profile_id = p_ratee and ps.skill_id = agg.skill_id;

  perform public.recompute_reputation(p_ratee);
  return v_rating;
end;
$$;

-- Rating progress for the caller in a team (drives the "1 of 3 rated" UI).
create or replace function public.my_rating_progress(p_team uuid)
returns table (profile_id uuid, full_name text, role_label text, rated boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select m.profile_id, p.full_name, m.role_label,
         exists (select 1 from public.peer_ratings r
                  where r.team_id = p_team and r.rater_id = auth.uid() and r.ratee_id = m.profile_id)
    from public.team_members m
    join public.profiles p on p.id = m.profile_id
   where m.team_id = p_team
     and m.profile_id <> auth.uid()
     and public.is_team_member(p_team)
   order by m.joined_at;
$$;

-- ---------------------------------------------------------------------------
-- Reports & appeals
-- ---------------------------------------------------------------------------
-- p_evidence: [{"label": text, "storage_path": text?, "external_url": text?}] (>= 1 required)
create or replace function public.file_report(
  p_team uuid,
  p_reported uuid,
  p_reason public.report_reason,
  p_description text,
  p_evidence jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_report uuid;
  v_team public.teams;
  r record;
begin
  select * into v_team from public.teams where id = p_team;
  if not found or not public.is_team_member(p_team) then
    raise exception 'You can only report members of your own team.' using errcode = '42501';
  end if;
  if p_reported = v_uid or not exists (
    select 1 from public.team_members m where m.team_id = p_team and m.profile_id = p_reported
  ) then
    raise exception 'That student is not in this team.' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_array_length(p_evidence), 0) = 0 then
    raise exception 'Evidence is required; opinions alone are not accepted.' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.reports
     where team_id = p_team and reporter_id = v_uid and reported_id = p_reported
       and status in ('awaiting_appeal', 'appealed', 'info_requested')
  ) then
    raise exception 'You already have an open report on this member.' using errcode = 'P0001';
  end if;

  insert into public.reports (team_id, reporter_id, reported_id, reason, description)
  values (p_team, v_uid, p_reported, p_reason, trim(p_description))
  returning id into v_report;

  insert into public.report_evidence (report_id, uploaded_by, side, label, storage_path, external_url)
  select v_report, v_uid, 'report', coalesce(nullif(e ->> 'label', ''), 'Evidence'),
         nullif(e ->> 'storage_path', ''), nullif(e ->> 'external_url', '')
    from jsonb_array_elements(p_evidence) e;

  perform public.notify(p_reported, 'report_received', 'Report received',
    'A teammate in ' || v_team.name || ' filed a report about you. You have 7 days to appeal.',
    jsonb_build_object('report_id', v_report));
  for r in select p.id from public.profiles p where p.role = 'admin' loop
    perform public.notify(r.id, 'report_filed', 'New report', 'Report filed in ' || v_team.name,
      jsonb_build_object('report_id', v_report));
  end loop;
  return v_report;
end;
$$;

create or replace function public.submit_appeal(p_report uuid, p_text text, p_evidence jsonb default '[]'::jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_rep public.reports;
  r record;
begin
  select * into v_rep from public.reports where id = p_report for update;
  if not found or v_rep.reported_id <> v_uid then
    raise exception 'Report not found.' using errcode = 'P0002';
  end if;
  if v_rep.status not in ('awaiting_appeal', 'info_requested') then
    raise exception 'This report is not open for an appeal.' using errcode = 'P0001';
  end if;
  if v_rep.status = 'awaiting_appeal' and now() > v_rep.appeal_deadline then
    raise exception 'The 7-day appeal window has closed.' using errcode = 'P0001';
  end if;
  if length(trim(coalesce(p_text, ''))) < 20 then
    raise exception 'Explain your side in at least 20 characters.' using errcode = 'P0001';
  end if;

  update public.reports
     set status = 'appealed', appeal_text = trim(p_text), appealed_at = now()
   where id = p_report;

  insert into public.report_evidence (report_id, uploaded_by, side, label, storage_path, external_url)
  select p_report, v_uid, 'appeal', coalesce(nullif(e ->> 'label', ''), 'Counter-evidence'),
         nullif(e ->> 'storage_path', ''), nullif(e ->> 'external_url', '')
    from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) e;

  for r in select p.id from public.profiles p where p.role = 'admin' loop
    perform public.notify(r.id, 'appeal_submitted', 'Appeal submitted',
      'Case #R-' || lpad(v_rep.code::text, 4, '0') || ' has a new appeal.',
      jsonb_build_object('report_id', p_report));
  end loop;
end;
$$;

-- What the reported member sees: reason + statement + evidence, never the reporter.
create or replace function public.reports_about_me()
returns table (
  id uuid,
  code integer,
  team_name text,
  competition_name text,
  reason public.report_reason,
  description text,
  status public.report_status,
  appeal_deadline timestamptz,
  appeal_text text,
  decision_note text,
  evidence jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.code, t.name, c.name, r.reason, r.description, r.status, r.appeal_deadline,
         r.appeal_text, r.decision_note,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'side', e.side, 'label', e.label,
                    'storage_path', e.storage_path, 'external_url', e.external_url,
                    'created_at', e.created_at) order by e.created_at)
             from public.report_evidence e where e.report_id = r.id
         ), '[]'::jsonb),
         r.created_at
    from public.reports r
    join public.teams t on t.id = r.team_id
    join public.competitions c on c.id = t.competition_id
   where r.reported_id = auth.uid()
   order by r.created_at desc;
$$;

create or replace function public.admin_decide_report(
  p_report uuid,
  p_decision public.report_status,
  p_note text default null,
  p_false_report boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_rep public.reports;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  if p_decision not in ('upheld', 'dismissed', 'info_requested') then
    raise exception 'Decision must be upheld, dismissed or info_requested.' using errcode = 'P0001';
  end if;
  select * into v_rep from public.reports where id = p_report for update;
  if not found or v_rep.status in ('upheld', 'dismissed') then
    raise exception 'Report not found or already decided.' using errcode = 'P0001';
  end if;

  update public.reports
     set status = p_decision,
         decided_by = case when p_decision = 'info_requested' then null else v_uid end,
         decided_at = case when p_decision = 'info_requested' then null else now() end,
         decision_note = nullif(trim(p_note), ''),
         false_report = (p_decision = 'dismissed' and p_false_report)
   where id = p_report;

  perform public.recompute_reputation(v_rep.reported_id);
  perform public.recompute_reputation(v_rep.reporter_id);

  perform public.notify(v_rep.reported_id, 'report_decided',
    case p_decision when 'upheld' then 'Report upheld'
                    when 'dismissed' then 'Report dismissed'
                    else 'Student Affairs needs more info' end,
    coalesce(p_note, ''), jsonb_build_object('report_id', p_report));
  perform public.notify(v_rep.reporter_id, 'report_decided',
    case p_decision when 'upheld' then 'Your report was upheld'
                    when 'dismissed' then 'Your report was dismissed'
                    else 'Student Affairs is reviewing your report' end,
    coalesce(p_note, ''), jsonb_build_object('report_id', p_report));
end;
$$;

-- ---------------------------------------------------------------------------
-- SEP claims
-- ---------------------------------------------------------------------------
create or replace function public.sep_estimate(p_team uuid, p_placement text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select r.points
    from public.teams t
    join public.competitions c on c.id = t.competition_id
    join public.sep_point_rules r on r.level = c.level and r.placement = p_placement
   where t.id = p_team;
$$;

-- Unlocked when: competition verified, team locked, caller rated every
-- teammate, and no open reports on the team.
create or replace function public.sep_claim_blockers(p_team uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    case when not exists (
      select 1 from public.teams t join public.competitions c on c.id = t.competition_id
       where t.id = p_team and c.status = 'approved') then 'Competition is not verified by Student Affairs' end,
    case when not exists (select 1 from public.teams t where t.id = p_team and t.status = 'locked')
         then 'Team is not locked' end,
    case when exists (
      select 1 from public.team_members m
       where m.team_id = p_team and m.profile_id <> auth.uid()
         and not exists (select 1 from public.peer_ratings r
                          where r.team_id = p_team and r.rater_id = auth.uid() and r.ratee_id = m.profile_id))
         then 'Rate all teammates first' end,
    case when exists (
      select 1 from public.reports r
       where r.team_id = p_team and r.status in ('awaiting_appeal', 'appealed', 'info_requested'))
         then 'There are open reports on this team' end,
    case when exists (select 1 from public.sep_claims s where s.team_id = p_team)
         then 'SEP already claimed for this team' end
  ], null);
$$;

create or replace function public.submit_sep_claim(
  p_team uuid,
  p_placement text,
  p_placement_label text,
  p_announcement_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_blockers text[];
  v_claim uuid;
  r record;
begin
  if not public.is_team_member(p_team) then
    raise exception 'You are not in this team.' using errcode = '42501';
  end if;
  v_blockers := public.sep_claim_blockers(p_team);
  if cardinality(v_blockers) > 0 then
    raise exception '%', array_to_string(v_blockers, '; ') using errcode = 'P0001';
  end if;
  if p_placement not in ('winner_1', 'winner_2', 'winner_3', 'finalist', 'participant') then
    raise exception 'Unknown placement.' using errcode = 'P0001';
  end if;

  insert into public.sep_claims (team_id, submitted_by, placement, placement_label, announcement_url, estimated_points)
  values (p_team, v_uid, p_placement, p_placement_label, nullif(trim(p_announcement_url), ''),
          public.sep_estimate(p_team, p_placement))
  returning id into v_claim;

  for r in select p.id from public.profiles p where p.role = 'admin' loop
    perform public.notify(r.id, 'sep_claim_submitted', 'SEP claim to verify',
      (select t.name from public.teams t where t.id = p_team) || ' · ' || p_placement_label,
      jsonb_build_object('claim_id', v_claim));
  end loop;
  return v_claim;
end;
$$;

create or replace function public.admin_verify_sep_claim(
  p_claim uuid,
  p_approve boolean,
  p_points integer default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_claim public.sep_claims;
  r record;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  select * into v_claim from public.sep_claims where id = p_claim for update;
  if not found or v_claim.status <> 'submitted' then
    raise exception 'Claim not found or already reviewed.' using errcode = 'P0001';
  end if;

  update public.sep_claims
     set status = case when p_approve then 'verified'::public.sep_claim_status
                       else 'rejected'::public.sep_claim_status end,
         verified_points = case when p_approve then coalesce(p_points, estimated_points, 0) end,
         verified_by = v_uid,
         verified_at = now(),
         review_note = nullif(trim(p_note), '')
   where id = p_claim;

  -- NOTE: pushing points to UPH Mobile needs an official integration; for now
  -- members are notified and the verified claim is the source of truth.
  for r in select m.profile_id from public.team_members m where m.team_id = v_claim.team_id loop
    perform public.notify(r.profile_id, 'sep_claim_reviewed',
      case when p_approve then 'SEP verified 🎉' else 'SEP claim rejected' end,
      case when p_approve then '+' || coalesce(p_points, v_claim.estimated_points, 0) || ' SEP per member'
           else coalesce(p_note, '') end,
      jsonb_build_object('claim_id', p_claim));
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin dashboard KPIs (semester = last 6 months)
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_since timestamptz := now() - interval '6 months';
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admins only.' using errcode = '42501';
  end if;

  with locked as (
    select t.* from public.teams t where t.status = 'locked' and t.locked_at >= v_since
  ),
  team_majors as (
    select l.id, count(distinct p.major_id) as majors
      from locked l
      join public.team_members m on m.team_id = l.id
      join public.profiles p on p.id = m.profile_id
     group by l.id
  ),
  participants as (
    select m.profile_id, count(distinct m.competition_id) as comps
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where t.status = 'locked'
     group by m.profile_id
  )
  select jsonb_build_object(
    'avg_time_to_team_days',
      (select round((extract(epoch from avg(l.locked_at - l.created_at)) / 86400)::numeric, 1) from locked l),
    'cross_major_pct',
      (select round(100.0 * count(*) filter (where majors >= 2) / nullif(count(*), 0)) from team_majors),
    'retention_pct',
      (select round(100.0 * count(*) filter (where comps >= 2) / nullif(count(*), 0)) from participants),
    'sep_credited',
      (select coalesce(sum(s.verified_points * (select count(*) from public.team_members m where m.team_id = s.team_id)), 0)
         from public.sep_claims s where s.status = 'verified' and s.verified_at >= v_since),
    'sep_students',
      (select count(distinct m.profile_id) from public.sep_claims s
         join public.team_members m on m.team_id = s.team_id
        where s.status = 'verified' and s.verified_at >= v_since),
    'pending_competitions', (select count(*) from public.competitions where status = 'pending'),
    'open_reports',
      (select count(*) from public.reports where status in ('awaiting_appeal', 'appealed', 'info_requested')),
    'sep_to_verify', (select count(*) from public.sep_claims where status = 'submitted')
  ) into v;
  return v;
end;
$$;
