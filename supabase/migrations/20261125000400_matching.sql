-- Teammate matching (ranking runs in the DB; AI only infers required skills).
--
-- Required skills for a team = skills the leader set (team_required_skills).
-- If the leader set none, we fall back to the competition's cached AI-inferred
-- skills (competitions.inferred_skill_ids, filled once by the infer-skills
-- Edge Function). If neither exists, recommend_candidates returns no rows and
-- the app shows "Skill yang dibutuhkan belum diatur".

-- Which skills a team is matching on, and where they came from.
create or replace function public.team_matching_skills(p_team uuid)
returns table (skill_id uuid, skill_name text, role_label text, source text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.name, r.role_label, 'leader'::text
    from public.team_required_skills r
    join public.skills s on s.id = r.skill_id
   where r.team_id = p_team
  union all
  select s.id, s.name, null::text, 'ai'::text
    from public.teams t
    join public.competitions c on c.id = t.competition_id
    join public.skills s on s.id = any (c.inferred_skill_ids)
   where t.id = p_team
     and not exists (select 1 from public.team_required_skills r where r.team_id = p_team);
$$;

-- % of the team's common free time (30-min buckets where every current member
-- is free) that the candidate is also free. NULL if the team has no common slot.
create or replace function public.availability_overlap_pct(p_team uuid, p_profile uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with buckets as (
    select d::smallint as weekday, (time '00:00' + make_interval(mins => 30 * g)) as t
      from generate_series(1, 7) d, generate_series(0, 47) g
  ),
  members as (
    select m.profile_id from public.team_members m where m.team_id = p_team
  ),
  team_free as (
    select b.weekday, b.t
      from buckets b
     where exists (select 1 from members)
       and not exists (
         select 1 from members m
          where not exists (
            select 1 from public.availability_slots s
             where s.profile_id = m.profile_id and s.weekday = b.weekday
               and s.start_time <= b.t and s.end_time > b.t
          )
       )
  ),
  both_free as (
    select tf.weekday, tf.t
      from team_free tf
     where exists (
       select 1 from public.availability_slots s
        where s.profile_id = p_profile and s.weekday = tf.weekday
          and s.start_time <= tf.t and s.end_time > tf.t
     )
  )
  select case
           when (select count(*) from team_free) = 0 then null
           else round(100.0 * (select count(*) from both_free) / (select count(*) from team_free))::integer
         end;
$$;

-- Heatmap for the team calendar: how many members are free in each 1h slot.
create or replace function public.team_availability_heatmap(p_team uuid)
returns table (weekday smallint, slot_start time, free_count integer, member_count integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (public.is_team_member(p_team) or public.is_admin()) then
    raise exception 'Only team members can see the team calendar.' using errcode = '42501';
  end if;

  return query
  with members as (
    select m.profile_id from public.team_members m where m.team_id = p_team
  )
  select d::smallint,
         (time '00:00' + make_interval(hours => h)),
         (select count(*)::integer from members m
           where exists (
             select 1 from public.availability_slots s
              where s.profile_id = m.profile_id and s.weekday = d
                and s.start_time <= (time '00:00' + make_interval(hours => h))
                and (s.end_time >= (time '00:00' + make_interval(hours => h + 1))
                     or (h = 23 and s.end_time = time '23:59:59'))
           )),
         (select count(*)::integer from members)
    from generate_series(1, 7) d, generate_series(6, 23) h
   order by 1, 2;
end;
$$;

-- Ranked, explainable candidate list for a team.
-- Score (0-100):
--   up to 70  level-weighted coverage of required skills
--   +15       cross-major bonus (candidate's major not yet in the team)
--   up to 10  reputation (neutral 5 if not rated yet)
--   up to 5   availability overlap with the team's common free time
create or replace function public.recommend_candidates(p_team uuid, p_limit integer default 20)
returns table (
  profile_id uuid,
  full_name text,
  major_name text,
  batch smallint,
  reputation numeric,
  match_score integer,
  matched_skills text[],
  availability_overlap integer,
  cross_major boolean,
  pending_with_team boolean,
  reasons text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_required integer;
begin
  select * into v_team from public.teams where id = p_team;
  if not found then
    raise exception 'Team not found' using errcode = 'P0002';
  end if;
  if not (public.is_team_member(p_team) or public.is_admin()) then
    raise exception 'Only team members can see recommendations.' using errcode = '42501';
  end if;

  select count(*) into v_required from public.team_matching_skills(p_team);
  if v_required = 0 then
    return; -- app shows: "Skill yang dibutuhkan belum diatur"
  end if;

  return query
  with req as (
    select ms.skill_id, ms.skill_name from public.team_matching_skills(p_team) ms
  ),
  team_majors as (
    select distinct p.major_id
      from public.team_members m
      join public.profiles p on p.id = m.profile_id
     where m.team_id = p_team and p.major_id is not null
  ),
  cand as (
    select p.id, p.full_name, p.major_id, p.batch, p.reputation
      from public.profiles p
     where p.role = 'student'
       and p.onboarded
       and not exists (
         select 1 from public.team_members m
          where m.competition_id = v_team.competition_id and m.profile_id = p.id
       )
  ),
  cov as (
    select c.id,
           array_agg(r.skill_name order by ps.level desc, r.skill_name) as names,
           sum(ps.level)::numeric / 4 as weighted,
           count(*)::integer as cnt
      from cand c
      join public.profile_skills ps on ps.profile_id = c.id
      join req r on r.skill_id = ps.skill_id
     group by c.id
  ),
  scored as (
    select c.id,
           c.full_name,
           mj.name as major_name,
           c.batch,
           c.reputation,
           cov.names,
           cov.cnt,
           round(70 * cov.weighted / v_required)::integer as skill_pts,
           (c.major_id is not null
             and not exists (select 1 from team_majors tm where tm.major_id = c.major_id)) as is_cross,
           case when c.reputation is null then 5
                else round((c.reputation - 1) / 4 * 10)::integer end as rep_pts,
           public.availability_overlap_pct(p_team, c.id) as overlap,
           (exists (select 1 from public.join_requests jr
                     where jr.team_id = p_team and jr.profile_id = c.id and jr.status = 'pending')
            or exists (select 1 from public.team_invites ti
                     where ti.team_id = p_team and ti.invitee_id = c.id and ti.status = 'pending')
           ) as pending
      from cand c
      join cov on cov.id = c.id
      left join public.majors mj on mj.id = c.major_id
  )
  select s.id,
         s.full_name,
         s.major_name,
         s.batch,
         s.reputation,
         least(100,
               s.skill_pts
               + case when s.is_cross then 15 else 0 end
               + s.rep_pts
               + coalesce(round(5 * s.overlap / 100.0)::integer, 0))::integer as score,
         s.names,
         s.overlap,
         s.is_cross,
         s.pending,
         array_remove(array[
           'Covers ' || s.cnt || ' of ' || v_required || ' needed skills ('
             || array_to_string(s.names, ', ') || ')',
           case when s.is_cross then 'Adds a new major (+ cross-major bonus)' end,
           case when s.reputation is not null then '★ ' || to_char(s.reputation, 'FM0.0') || ' reputation'
                else 'New on Bearch, no ratings yet' end,
           case when s.overlap is not null then 'Free time overlaps ' || s.overlap || '% with the team' end
         ], null)
    from scored s
   order by score desc, s.reputation desc nulls last, s.full_name
   limit greatest(1, least(p_limit, 100));
end;
$$;
