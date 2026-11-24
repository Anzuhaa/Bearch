-- Team (lobby) lifecycle: create, join requests, direct invites, leave/disband,
-- manual + automatic lock, lock warnings, invite expiry.
--
-- Rules encoded here:
--   * one team per student per competition (team_members unique constraint)
--   * teams auto-lock at H-1 23:59 WIB (competition_lock_at); leaders may lock earlier
--   * locking works even if the team is not full
--   * on lock, pending join requests are auto-rejected and pending invites cancelled
--   * no unlock, and no member changes once locked (no replacement)
--   * leaders get H-3 and H-2 warnings (send_lock_warnings, daily cron)
--   * direct invites reserve a slot for 48h

-- ---------------------------------------------------------------------------
-- Small internal helpers
-- ---------------------------------------------------------------------------
create or replace function public.notify(
  p_profile uuid,
  p_kind text,
  p_title text,
  p_body text default '',
  p_data jsonb default '{}'::jsonb,
  p_dedupe text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (profile_id, kind, title, body, data, dedupe_key)
  values (p_profile, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb), p_dedupe)
  on conflict (profile_id, dedupe_key) where dedupe_key is not null do nothing;
$$;

create or replace function public.post_system_message(p_team uuid, p_body text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.messages (team_id, sender_id, body, is_system) values (p_team, null, p_body, true);
$$;

create or replace function public.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v uuid := auth.uid();
begin
  if v is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  return v;
end;
$$;

-- Members + live (pending, unexpired) invites count against max_members.
create or replace function public.team_open_slots(p_team uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select t.max_members
         - (select count(*) from public.team_members m where m.team_id = t.id)::integer
         - (select count(*) from public.team_invites i
             where i.team_id = t.id and i.status = 'pending' and i.expires_at > now())::integer
  from public.teams t
  where t.id = p_team;
$$;

-- Returns the team row locked FOR UPDATE and raises if it can no longer change.
create or replace function public.assert_team_open(p_team uuid)
returns public.teams
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_deadline date;
begin
  select * into v_team from public.teams where id = p_team for update;
  if not found then
    raise exception 'Team not found' using errcode = 'P0002';
  end if;
  if v_team.status = 'locked' then
    raise exception 'This team is locked and registered; it can no longer change.' using errcode = 'P0001';
  end if;
  select c.registration_deadline into v_deadline from public.competitions c where c.id = v_team.competition_id;
  if now() >= public.competition_lock_at(v_deadline) then
    raise exception 'The H-1 lock time for this competition has passed.' using errcode = 'P0001';
  end if;
  return v_team;
end;
$$;

-- Adds a member and clears their other pending requests/invites for the same competition.
create or replace function public.add_team_member(p_team uuid, p_profile uuid, p_role_label text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  select * into v_team from public.teams where id = p_team;

  if exists (
    select 1 from public.team_members m
    where m.competition_id = v_team.competition_id and m.profile_id = p_profile
  ) then
    raise exception 'This student is already in a team for this competition.' using errcode = '23505';
  end if;

  insert into public.team_members (team_id, profile_id, competition_id, is_leader, role_label)
  values (p_team, p_profile, v_team.competition_id, false, p_role_label);

  update public.join_requests r
     set status = 'cancelled', decided_at = now()
    from public.teams t
   where r.team_id = t.id and t.competition_id = v_team.competition_id
     and r.profile_id = p_profile and r.status = 'pending';

  update public.team_invites i
     set status = 'cancelled', responded_at = now()
    from public.teams t
   where i.team_id = t.id and t.competition_id = v_team.competition_id
     and i.invitee_id = p_profile and i.status = 'pending' and i.team_id <> p_team;

  perform public.post_system_message(
    p_team,
    (select p.full_name from public.profiles p where p.id = p_profile) || ' joined the team'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------
create or replace function public.guard_team_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_comp public.competitions;
  v_used integer;
begin
  if old.status = 'locked' then
    if new.status <> 'locked'
       or new.locked_at is distinct from old.locked_at
       or new.max_members <> old.max_members
       or new.leader_id <> old.leader_id
       or new.competition_id <> old.competition_id then
      raise exception 'Locked teams cannot be unlocked or changed.' using errcode = 'P0001';
    end if;
  end if;

  if new.max_members <> old.max_members then
    select * into v_comp from public.competitions where id = new.competition_id;
    if new.max_members > v_comp.team_max then
      raise exception 'Team size cannot exceed % members for this competition.', v_comp.team_max
        using errcode = 'P0001';
    end if;
    select (select count(*) from public.team_members m where m.team_id = new.id)
         + (select count(*) from public.team_invites i
             where i.team_id = new.id and i.status = 'pending' and i.expires_at > now())
      into v_used;
    if new.max_members < v_used then
      raise exception 'Team already has % members/reserved slots.', v_used using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger teams_guard_update before update on public.teams
  for each row execute function public.guard_team_update();

-- No member changes once a team is locked (no replacement). Deleting a whole
-- account (profile already gone) is still allowed to cascade.
create or replace function public.guard_team_members()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_team_id uuid;
begin
  if tg_op = 'DELETE' then
    v_team_id := old.team_id;
    if not exists (select 1 from public.profiles p where p.id = old.profile_id) then
      return old;
    end if;
  else
    v_team_id := new.team_id;
  end if;

  if exists (select 1 from public.teams t where t.id = v_team_id and t.status = 'locked') then
    raise exception 'Team is locked; members cannot be added, removed or replaced.' using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger team_members_guard before insert or delete on public.team_members
  for each row execute function public.guard_team_members();

-- ---------------------------------------------------------------------------
-- RPC: create a lobby (caller becomes leader)
-- p_required_skills: [{"skill_id": uuid, "role_label": text}]
-- ---------------------------------------------------------------------------
create or replace function public.create_team(
  p_competition uuid,
  p_name text,
  p_pitch text default '',
  p_max_members integer default null,
  p_approval_based boolean default true,
  p_cross_major_preferred boolean default true,
  p_required_skills jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_comp public.competitions;
  v_team_id uuid;
  v_max integer;
begin
  select * into v_comp from public.competitions where id = p_competition;
  if not found or v_comp.status <> 'approved' then
    raise exception 'Competition is not open for lobbies.' using errcode = 'P0001';
  end if;
  if now() >= public.competition_lock_at(v_comp.registration_deadline) then
    raise exception 'Registration for this competition has closed (H-1 lock passed).' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.team_members m where m.competition_id = p_competition and m.profile_id = v_uid) then
    raise exception 'You are already in a team for this competition.' using errcode = '23505';
  end if;

  v_max := coalesce(p_max_members, v_comp.team_max);
  if v_max < 1 or v_max > v_comp.team_max then
    raise exception 'Team size must be between 1 and %.', v_comp.team_max using errcode = 'P0001';
  end if;

  insert into public.teams (competition_id, leader_id, name, pitch, max_members, approval_based, cross_major_preferred)
  values (p_competition, v_uid, trim(p_name), coalesce(p_pitch, ''), v_max, p_approval_based, p_cross_major_preferred)
  returning id into v_team_id;

  insert into public.team_members (team_id, profile_id, competition_id, is_leader, role_label)
  values (v_team_id, v_uid, p_competition, true, 'Leader');

  insert into public.team_required_skills (team_id, skill_id, role_label)
  select v_team_id, (e ->> 'skill_id')::uuid, nullif(e ->> 'role_label', '')
  from jsonb_array_elements(coalesce(p_required_skills, '[]'::jsonb)) e
  on conflict do nothing;

  -- Leading a team withdraws your requests/invites elsewhere in this competition.
  update public.join_requests r set status = 'cancelled', decided_at = now()
    from public.teams t
   where r.team_id = t.id and t.competition_id = p_competition
     and r.profile_id = v_uid and r.status = 'pending';
  update public.team_invites i set status = 'cancelled', responded_at = now()
    from public.teams t
   where i.team_id = t.id and t.competition_id = p_competition
     and i.invitee_id = v_uid and i.status = 'pending';

  perform public.post_system_message(v_team_id, 'Lobby created. Broadcasting to UPH students.');
  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: request to join
-- ---------------------------------------------------------------------------
create or replace function public.request_join(p_team uuid, p_message text default '')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_team public.teams;
  v_req uuid;
begin
  v_team := public.assert_team_open(p_team);

  if exists (select 1 from public.team_members m where m.competition_id = v_team.competition_id and m.profile_id = v_uid) then
    raise exception 'You are already in a team for this competition.' using errcode = '23505';
  end if;
  if public.team_open_slots(p_team) <= 0 then
    raise exception 'This team is full.' using errcode = 'P0001';
  end if;

  if not v_team.approval_based then
    perform public.add_team_member(p_team, v_uid, null);
    insert into public.join_requests (team_id, profile_id, message, status, decided_at)
    values (p_team, v_uid, coalesce(p_message, ''), 'approved', now())
    returning id into v_req;
    perform public.notify(v_team.leader_id, 'team_joined', 'New teammate joined',
      (select full_name from public.profiles where id = v_uid) || ' joined ' || v_team.name,
      jsonb_build_object('team_id', p_team));
    return v_req;
  end if;

  insert into public.join_requests (team_id, profile_id, message)
  values (p_team, v_uid, coalesce(p_message, ''))
  returning id into v_req;

  perform public.notify(v_team.leader_id, 'join_request', 'New join request',
    (select full_name from public.profiles where id = v_uid) || ' wants to join ' || v_team.name,
    jsonb_build_object('team_id', p_team, 'request_id', v_req));
  return v_req;
end;
$$;

create or replace function public.cancel_join_request(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
begin
  update public.join_requests set status = 'cancelled', decided_at = now()
   where id = p_request and profile_id = v_uid and status = 'pending';
  if not found then
    raise exception 'Request not found or no longer pending.' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: leader approves / declines a request
-- ---------------------------------------------------------------------------
create or replace function public.decide_join_request(p_request uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_req public.join_requests;
  v_team public.teams;
begin
  select * into v_req from public.join_requests where id = p_request for update;
  if not found or v_req.status <> 'pending' then
    raise exception 'Request not found or no longer pending.' using errcode = 'P0002';
  end if;

  v_team := public.assert_team_open(v_req.team_id);
  if v_team.leader_id <> v_uid then
    raise exception 'Only the team leader can decide join requests.' using errcode = '42501';
  end if;

  if p_approve then
    if public.team_open_slots(v_team.id) <= 0 then
      raise exception 'No open slots left (members + reserved invites).' using errcode = 'P0001';
    end if;
    perform public.add_team_member(v_team.id, v_req.profile_id, null);
    update public.join_requests set status = 'approved', decided_by = v_uid, decided_at = now()
     where id = p_request;
    perform public.notify(v_req.profile_id, 'join_approved', 'You''re in!',
      'Your request to join ' || v_team.name || ' was approved.', jsonb_build_object('team_id', v_team.id));
  else
    update public.join_requests set status = 'declined', decided_by = v_uid, decided_at = now()
     where id = p_request;
    perform public.notify(v_req.profile_id, 'join_declined', 'Request declined',
      v_team.name || ' declined your request.', jsonb_build_object('team_id', v_team.id));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: direct invites (reserve a slot for 48h)
-- ---------------------------------------------------------------------------
create or replace function public.send_invite(
  p_team uuid,
  p_invitee uuid,
  p_role_label text default null,
  p_message text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_team public.teams;
  v_invite uuid;
begin
  v_team := public.assert_team_open(p_team);
  if v_team.leader_id <> v_uid then
    raise exception 'Only the team leader can send invites.' using errcode = '42501';
  end if;
  if p_invitee = v_uid then
    raise exception 'You cannot invite yourself.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_invitee and p.role = 'student') then
    raise exception 'Student not found.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.team_members m where m.competition_id = v_team.competition_id and m.profile_id = p_invitee) then
    raise exception 'This student is already in a team for this competition.' using errcode = '23505';
  end if;
  if public.team_open_slots(p_team) <= 0 then
    raise exception 'No open slots left (members + reserved invites).' using errcode = 'P0001';
  end if;

  insert into public.team_invites (team_id, invitee_id, invited_by, role_label, message)
  values (p_team, p_invitee, v_uid, p_role_label, coalesce(p_message, ''))
  returning id into v_invite;

  perform public.notify(p_invitee, 'team_invite', 'Team invite',
    v_team.name || ' invited you' || coalesce(' as ' || p_role_label, '') || '. Slot reserved for 48h.',
    jsonb_build_object('team_id', p_team, 'invite_id', v_invite));
  return v_invite;
end;
$$;

create or replace function public.respond_invite(p_invite uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_inv public.team_invites;
  v_team public.teams;
begin
  select * into v_inv from public.team_invites where id = p_invite for update;
  if not found or v_inv.invitee_id <> v_uid or v_inv.status <> 'pending' then
    raise exception 'Invite not found or no longer pending.' using errcode = 'P0002';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'This invite has expired.' using errcode = 'P0001';
  end if;

  v_team := public.assert_team_open(v_inv.team_id);

  if p_accept then
    -- Mark accepted first so the reserved slot is released before adding the member.
    update public.team_invites set status = 'accepted', responded_at = now() where id = p_invite;
    perform public.add_team_member(v_team.id, v_uid, v_inv.role_label);
    perform public.notify(v_team.leader_id, 'invite_accepted', 'Invite accepted',
      (select full_name from public.profiles where id = v_uid) || ' joined ' || v_team.name,
      jsonb_build_object('team_id', v_team.id));
  else
    update public.team_invites set status = 'declined', responded_at = now() where id = p_invite;
    perform public.notify(v_team.leader_id, 'invite_declined', 'Invite declined',
      (select full_name from public.profiles where id = v_uid) || ' declined the invite.',
      jsonb_build_object('team_id', v_team.id));
  end if;
end;
$$;

create or replace function public.cancel_invite(p_invite uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
begin
  update public.team_invites i set status = 'cancelled', responded_at = now()
    from public.teams t
   where i.id = p_invite and t.id = i.team_id and t.leader_id = v_uid and i.status = 'pending';
  if not found then
    raise exception 'Invite not found or no longer pending.' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: leave / disband (only while open)
-- ---------------------------------------------------------------------------
create or replace function public.leave_team(p_team uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_team public.teams;
begin
  v_team := public.assert_team_open(p_team);
  if v_team.leader_id = v_uid then
    raise exception 'Leaders cannot leave; disband the lobby instead.' using errcode = 'P0001';
  end if;
  delete from public.team_members where team_id = p_team and profile_id = v_uid;
  if not found then
    raise exception 'You are not in this team.' using errcode = 'P0002';
  end if;
  perform public.post_system_message(p_team,
    (select full_name from public.profiles where id = v_uid) || ' left the team');
  perform public.notify(v_team.leader_id, 'member_left', 'A member left',
    (select full_name from public.profiles where id = v_uid) || ' left ' || v_team.name,
    jsonb_build_object('team_id', p_team));
end;
$$;

create or replace function public.disband_team(p_team uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_team public.teams;
  r record;
begin
  v_team := public.assert_team_open(p_team);
  if v_team.leader_id <> v_uid then
    raise exception 'Only the leader can disband the lobby.' using errcode = '42501';
  end if;
  for r in select profile_id from public.team_members where team_id = p_team and profile_id <> v_uid loop
    perform public.notify(r.profile_id, 'team_disbanded', 'Lobby disbanded',
      v_team.name || ' was disbanded by the leader.', '{}'::jsonb);
  end loop;
  for r in select profile_id from public.join_requests where team_id = p_team and status = 'pending' loop
    perform public.notify(r.profile_id, 'team_disbanded', 'Lobby disbanded',
      v_team.name || ' was disbanded; your request was closed.', '{}'::jsonb);
  end loop;
  delete from public.teams where id = p_team;
end;
$$;

-- ---------------------------------------------------------------------------
-- Locking
-- ---------------------------------------------------------------------------
-- Internal: lock + auto-reject pending requests + cancel pending invites.
create or replace function public.lock_team_internal(p_team uuid, p_reason public.lock_reason)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_comp public.competitions;
  v_members integer;
  v_rejected integer := 0;
  r record;
begin
  update public.teams
     set status = 'locked', locked_at = now(), lock_reason = p_reason
   where id = p_team and status = 'open'
  returning * into v_team;
  if not found then
    return false;
  end if;

  select * into v_comp from public.competitions where id = v_team.competition_id;
  select count(*) into v_members from public.team_members where team_id = p_team;

  for r in
    update public.join_requests
       set status = 'auto_rejected', decided_at = now()
     where team_id = p_team and status = 'pending'
    returning profile_id
  loop
    v_rejected := v_rejected + 1;
    perform public.notify(r.profile_id, 'join_auto_rejected', 'Request closed',
      v_team.name || ' has locked its team, so your request was automatically rejected.',
      jsonb_build_object('team_id', p_team));
  end loop;

  for r in
    update public.team_invites
       set status = 'cancelled', responded_at = now()
     where team_id = p_team and status = 'pending'
    returning invitee_id
  loop
    perform public.notify(r.invitee_id, 'invite_cancelled', 'Invite closed',
      v_team.name || ' has locked its team.', jsonb_build_object('team_id', p_team));
  end loop;

  for r in select profile_id from public.team_members where team_id = p_team loop
    perform public.notify(r.profile_id, 'team_locked', 'Team locked & registered',
      v_team.name || ' is locked with ' || v_members || '/' || v_team.max_members
        || ' members for ' || v_comp.name || '. Locked teams cannot be unlocked.',
      jsonb_build_object('team_id', p_team, 'reason', p_reason));
  end loop;

  perform public.post_system_message(p_team,
    case p_reason when 'auto' then 'Team auto-locked at H-1' else 'Team locked by the leader' end
    || ' · ' || v_members || ' members'
    || case when v_rejected > 0 then ' · ' || v_rejected || ' pending request(s) auto-rejected' else '' end);
  return true;
end;
$$;

-- RPC: leader locks early (allowed even if not full). No unlock exists.
create or replace function public.lock_team(p_team uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.require_uid();
  v_team public.teams;
begin
  select * into v_team from public.teams where id = p_team for update;
  if not found then
    raise exception 'Team not found' using errcode = 'P0002';
  end if;
  if v_team.leader_id <> v_uid then
    raise exception 'Only the team leader can lock the team.' using errcode = '42501';
  end if;
  if v_team.status = 'locked' then
    raise exception 'Team is already locked.' using errcode = 'P0001';
  end if;
  perform public.lock_team_internal(p_team, 'manual');
end;
$$;

-- Cron: lock every open team whose competition reached H-1 23:59 WIB.
create or replace function public.auto_lock_due_teams()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select t.id
      from public.teams t
      join public.competitions c on c.id = t.competition_id
     where t.status = 'open'
       and now() >= public.competition_lock_at(c.registration_deadline)
     for update of t skip locked
  loop
    if public.lock_team_internal(r.id, 'auto') then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Cron (daily 08:00 WIB): warn leaders of open teams at H-3 and H-2.
create or replace function public.send_lock_warnings()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_days integer;
  v_open integer;
  v_lock timestamptz;
  r record;
begin
  for r in
    select t.id, t.name, t.leader_id, t.max_members, c.registration_deadline
      from public.teams t
      join public.competitions c on c.id = t.competition_id
     where t.status = 'open'
       and c.registration_deadline - public.today_wib() in (2, 3)
  loop
    v_days := r.registration_deadline - public.today_wib();
    v_open := r.max_members - (select count(*) from public.team_members m where m.team_id = r.id)::integer;
    v_lock := public.competition_lock_at(r.registration_deadline);
    perform public.notify(
      r.leader_id,
      'lock_warning',
      'H-' || v_days || ' reminder · ' || r.name,
      case when v_open > 0 then v_open || ' slot(s) still open. ' else 'Team is full. ' end
        || r.name || ' auto-locks on '
        || to_char(v_lock at time zone 'Asia/Jakarta', 'DD Mon, HH24:MI') || ' WIB even if it isn''t full, '
        || 'and pending requests will be auto-rejected.',
      jsonb_build_object('team_id', r.id, 'days_left', v_days, 'open_slots', v_open),
      'lock_warning:' || r.id || ':H-' || v_days
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Cron (every 15 min): expire 48h invites so their reserved slots free up.
create or replace function public.expire_invites()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    update public.team_invites i
       set status = 'expired'
     where i.status = 'pending' and i.expires_at <= now()
    returning i.team_id, i.invitee_id
  loop
    v_count := v_count + 1;
    perform public.notify(
      (select t.leader_id from public.teams t where t.id = r.team_id),
      'invite_expired', 'Invite expired',
      (select p.full_name from public.profiles p where p.id = r.invitee_id)
        || ' didn''t respond within 48h; the slot is open again.',
      jsonb_build_object('team_id', r.team_id));
  end loop;
  return v_count;
end;
$$;
