-- Auth hook (UPH-only sign-up), RLS helper functions, row level security policies
-- and column-level grants.
--
-- Design: clients read through RLS. Most state transitions (joining a team,
-- locking, rating, reporting...) go through SECURITY DEFINER RPCs defined in
-- later migrations, so clients get very few direct write grants.

-- ---------------------------------------------------------------------------
-- Time helpers
-- ---------------------------------------------------------------------------
create or replace function public.today_wib()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Jakarta')::date;
$$;

-- Teams auto-lock at 23:59:59 WIB on H-1 (the day before the registration deadline).
create or replace function public.competition_lock_at(p_deadline date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select ((p_deadline - 1)::timestamp + time '23:59:59') at time zone 'Asia/Jakarta';
$$;

-- ---------------------------------------------------------------------------
-- New user -> profile (only UPH domains or allowlisted admins)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_is_admin boolean;
begin
  v_is_admin := exists (select 1 from public.admin_allowlist a where a.email = v_email);

  if not v_is_admin and not exists (
    select 1 from public.allowed_email_domains d where d.domain = split_part(v_email, '@', 2)
  ) then
    raise exception 'Only verified UPH email accounts can join Bearch (@student.uph.edu or @uph.edu).'
      using errcode = 'P0001';
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    v_email,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      initcap(replace(split_part(v_email, '@', 1), '.', ' '))
    ),
    case when v_is_admin then 'admin'::public.user_role else 'student'::public.user_role end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS helpers (SECURITY DEFINER so they can read tables without recursion)
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
  );
$$;

create or replace function public.is_team_member(p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.team_members m where m.team_id = p_team and m.profile_id = auth.uid()
  );
$$;

create or replace function public.is_team_leader(p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.teams t where t.id = p_team and t.leader_id = auth.uid()
  );
$$;

create or replace function public.can_see_competition(p_competition uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition
      and (c.status = 'approved' or c.submitted_by = auth.uid() or public.is_admin())
  );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
alter table public.allowed_email_domains enable row level security;
alter table public.admin_allowlist enable row level security;
alter table public.majors enable row level security;
alter table public.skills enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_skills enable row level security;
alter table public.availability_slots enable row level security;
alter table public.competitions enable row level security;
alter table public.competition_files enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_required_skills enable row level security;
alter table public.join_requests enable row level security;
alter table public.team_invites enable row level security;
alter table public.messages enable row level security;
alter table public.team_meetings enable row level security;
alter table public.peer_ratings enable row level security;
alter table public.peer_rating_skills enable row level security;
alter table public.peer_rating_criteria enable row level security;
alter table public.reports enable row level security;
alter table public.report_evidence enable row level security;
alter table public.sep_point_rules enable row level security;
alter table public.sep_claims enable row level security;
alter table public.sep_claim_files enable row level security;
alter table public.notifications enable row level security;
alter table public.ai_calls enable row level security;

-- Everything needs a signed-in UPH account; anon gets nothing.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- Default: authenticated can only SELECT; writes are granted per table below.
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from authenticated;
grant select on all tables in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- Access lists (admin read only; managed from the Supabase dashboard)
-- ---------------------------------------------------------------------------
create policy "admins read domains" on public.allowed_email_domains
  for select to authenticated using (public.is_admin());
create policy "admins read allowlist" on public.admin_allowlist
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create policy "read majors" on public.majors
  for select to authenticated using (true);

create policy "read skills" on public.skills
  for select to authenticated using (true);
create policy "admins add skills" on public.skills
  for insert to authenticated with check (public.is_admin());
grant insert (name, kind) on public.skills to authenticated;

create policy "read sep rules" on public.sep_point_rules
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Profiles: directory is visible to all signed-in students (needed for
-- matchmaking). Users may edit only their own non-privileged columns.
-- ---------------------------------------------------------------------------
create policy "read profiles" on public.profiles
  for select to authenticated using (true);
create policy "update own profile" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
grant update (full_name, avatar_url, major_id, batch, portfolio_url, linkedin_url, onboarded)
  on public.profiles to authenticated;

create policy "read profile skills" on public.profile_skills
  for select to authenticated using (true);
create policy "manage own skills insert" on public.profile_skills
  for insert to authenticated with check (profile_id = auth.uid());
create policy "manage own skills update" on public.profile_skills
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "manage own skills delete" on public.profile_skills
  for delete to authenticated using (profile_id = auth.uid());
grant insert (profile_id, skill_id, level), update (level), delete on public.profile_skills to authenticated;

create policy "read availability" on public.availability_slots
  for select to authenticated using (true);
create policy "manage own availability insert" on public.availability_slots
  for insert to authenticated with check (profile_id = auth.uid());
create policy "manage own availability update" on public.availability_slots
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "manage own availability delete" on public.availability_slots
  for delete to authenticated using (profile_id = auth.uid());
grant insert (profile_id, weekday, start_time, end_time, source),
  update (weekday, start_time, end_time, source), delete
  on public.availability_slots to authenticated;

-- ---------------------------------------------------------------------------
-- Competitions: approved ones are public to students; submitters see their own
-- drafts/pending/rejected; admins see everything. Status changes go through
-- submit_competition() / admin_review_competition().
-- ---------------------------------------------------------------------------
create policy "read competitions" on public.competitions
  for select to authenticated
  using (status = 'approved' or submitted_by = auth.uid() or public.is_admin());
create policy "submit competition draft" on public.competitions
  for insert to authenticated
  with check (submitted_by = auth.uid() and status = 'draft');
create policy "edit own draft" on public.competitions
  for update to authenticated
  using ((submitted_by = auth.uid() and status in ('draft', 'pending')) or public.is_admin())
  with check ((submitted_by = auth.uid() and status in ('draft', 'pending')) or public.is_admin());
create policy "delete own draft" on public.competitions
  for delete to authenticated
  using (submitted_by = auth.uid() and status = 'draft');
grant insert (name, organizer, category, level, description, official_url, guidebook_url, prize,
              registration_deadline, event_start, event_end, announcement_date, team_min, team_max,
              submitted_by),
      update (name, organizer, category, level, description, official_url, guidebook_url, prize,
              registration_deadline, event_start, event_end, announcement_date, team_min, team_max),
      delete
  on public.competitions to authenticated;

-- Editing the identifying fields invalidates an earlier duplicate check.
create or replace function public.reset_duplicate_check()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status in ('draft', 'pending') and (
       new.name is distinct from old.name
    or new.organizer is distinct from old.organizer
    or new.category is distinct from old.category
    or new.registration_deadline is distinct from old.registration_deadline
  ) then
    new.duplicate_status := 'not_checked';
    new.duplicate_of := null;
    new.duplicate_score := null;
    new.duplicate_reasons := '[]'::jsonb;
    new.duplicate_checked_at := null;
  end if;
  return new;
end;
$$;

create trigger competitions_reset_duplicate before update on public.competitions
  for each row execute function public.reset_duplicate_check();

create policy "read competition files" on public.competition_files
  for select to authenticated using (public.can_see_competition(competition_id));
create policy "attach files to own submission" on public.competition_files
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.competitions c
      where c.id = competition_id and c.submitted_by = auth.uid() and c.status in ('draft', 'pending')
    )
  );
create policy "remove files from own draft" on public.competition_files
  for delete to authenticated
  using (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.competitions c
      where c.id = competition_id and c.status in ('draft', 'pending')
    )
  );
grant insert (competition_id, storage_path, file_name, size_bytes, uploaded_by), delete
  on public.competition_files to authenticated;

-- ---------------------------------------------------------------------------
-- Teams / lobbies: browsable by everyone; created & state-changed via RPCs.
-- Leaders may edit the pitch/settings of an open team directly.
-- ---------------------------------------------------------------------------
create policy "read teams" on public.teams
  for select to authenticated using (true);
create policy "leader edits open team" on public.teams
  for update to authenticated
  using (leader_id = auth.uid() and status = 'open')
  with check (leader_id = auth.uid() and status = 'open');
grant update (name, pitch, max_members, approval_based, cross_major_preferred)
  on public.teams to authenticated;

create policy "read team members" on public.team_members
  for select to authenticated using (true);

create policy "read required skills" on public.team_required_skills
  for select to authenticated using (true);
create policy "leader sets required skills" on public.team_required_skills
  for insert to authenticated
  with check (exists (
    select 1 from public.teams t where t.id = team_id and t.leader_id = auth.uid() and t.status = 'open'
  ));
create policy "leader removes required skills" on public.team_required_skills
  for delete to authenticated
  using (exists (
    select 1 from public.teams t where t.id = team_id and t.leader_id = auth.uid() and t.status = 'open'
  ));
grant insert (team_id, skill_id, role_label), delete on public.team_required_skills to authenticated;

create policy "read join requests" on public.join_requests
  for select to authenticated
  using (profile_id = auth.uid() or public.is_team_member(team_id) or public.is_admin());

create policy "read invites" on public.team_invites
  for select to authenticated
  using (invitee_id = auth.uid() or public.is_team_member(team_id) or public.is_admin());

-- ---------------------------------------------------------------------------
-- Chat & meetings: team members only (admins may read chat for report evidence)
-- ---------------------------------------------------------------------------
create policy "read team chat" on public.messages
  for select to authenticated using (public.is_team_member(team_id) or public.is_admin());
create policy "post to team chat" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and is_system = false and public.is_team_member(team_id));
grant insert (team_id, sender_id, body, attachment_path, attachment_name) on public.messages to authenticated;

create policy "read meetings" on public.team_meetings
  for select to authenticated using (public.is_team_member(team_id));
create policy "members schedule meetings" on public.team_meetings
  for insert to authenticated
  with check (created_by = auth.uid() and public.is_team_member(team_id));
create policy "members edit meetings" on public.team_meetings
  for update to authenticated
  using (public.is_team_member(team_id)) with check (public.is_team_member(team_id));
create policy "members delete meetings" on public.team_meetings
  for delete to authenticated using (public.is_team_member(team_id));
grant insert (team_id, title, starts_at, ends_at, location, pinned, created_by),
      update (title, starts_at, ends_at, location, pinned), delete
  on public.team_meetings to authenticated;

-- ---------------------------------------------------------------------------
-- Ratings are anonymous: only the rater and admins can read individual rows.
-- Written via submit_rating().
-- ---------------------------------------------------------------------------
create policy "read own given ratings" on public.peer_ratings
  for select to authenticated using (rater_id = auth.uid() or public.is_admin());
create policy "read own given rating skills" on public.peer_rating_skills
  for select to authenticated
  using (exists (
    select 1 from public.peer_ratings r
    where r.id = rating_id and (r.rater_id = auth.uid() or public.is_admin())
  ));
create policy "read own given rating criteria" on public.peer_rating_criteria
  for select to authenticated
  using (exists (
    select 1 from public.peer_ratings r
    where r.id = rating_id and (r.rater_id = auth.uid() or public.is_admin())
  ));

-- ---------------------------------------------------------------------------
-- Reports: reporter + admins read rows directly. The reported member reads via
-- reports_about_me(), which hides the reporter's identity.
-- ---------------------------------------------------------------------------
create policy "read reports I filed" on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

create policy "read evidence" on public.report_evidence
  for select to authenticated
  using (uploaded_by = auth.uid() or public.is_admin());
create policy "add evidence" on public.report_evidence
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.reports r
      where r.id = report_id
        and r.status in ('awaiting_appeal', 'info_requested', 'appealed')
        and (
          (side = 'report' and r.reporter_id = auth.uid())
          or (side = 'appeal' and r.reported_id = auth.uid())
        )
    )
  );
grant insert (report_id, uploaded_by, side, label, storage_path, external_url)
  on public.report_evidence to authenticated;

-- ---------------------------------------------------------------------------
-- SEP claims: team members + admins
-- ---------------------------------------------------------------------------
create policy "read team sep claim" on public.sep_claims
  for select to authenticated using (public.is_team_member(team_id) or public.is_admin());
create policy "read sep files" on public.sep_claim_files
  for select to authenticated
  using (exists (
    select 1 from public.sep_claims s
    where s.id = claim_id and (public.is_team_member(s.team_id) or public.is_admin())
  ));
create policy "members attach sep files" on public.sep_claim_files
  for insert to authenticated
  with check (exists (
    select 1 from public.sep_claims s
    where s.id = claim_id and s.status = 'submitted' and public.is_team_member(s.team_id)
  ));
grant insert (claim_id, storage_path, file_name, size_bytes) on public.sep_claim_files to authenticated;

-- ---------------------------------------------------------------------------
-- Notifications: own only; may mark read / delete
-- ---------------------------------------------------------------------------
create policy "read own notifications" on public.notifications
  for select to authenticated using (profile_id = auth.uid());
create policy "mark own notifications" on public.notifications
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "delete own notifications" on public.notifications
  for delete to authenticated using (profile_id = auth.uid());
grant update (read_at), delete on public.notifications to authenticated;

-- ai_calls: no client policies (service role only).
revoke select on public.ai_calls from authenticated;
