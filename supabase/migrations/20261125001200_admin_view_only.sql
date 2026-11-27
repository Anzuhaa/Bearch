-- Admins (Student Affairs) only view lobbies/teams: they cannot create a team,
-- join one or request to join. Insert triggers cover every path (create_team,
-- request_join, decide_join_request, respond_invite). send_invite already only
-- accepts student invitees.

create or replace function public.guard_student_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles p where p.id = new.profile_id and p.role = 'admin') then
    raise exception 'Admins can view lobbies but cannot create, join or request to join a team.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger team_members_student_only before insert on public.team_members
  for each row execute function public.guard_student_only();
create trigger join_requests_student_only before insert on public.join_requests
  for each row execute function public.guard_student_only();

-- One-off cleanup of admin rows created before this guard (open teams only;
-- locked teams stay frozen by design).
update public.join_requests r
   set status = 'cancelled', decided_at = now()
  from public.profiles p
 where p.id = r.profile_id and p.role = 'admin' and r.status = 'pending';

delete from public.team_members m
 using public.profiles p, public.teams t
 where p.id = m.profile_id and p.role = 'admin'
   and t.id = m.team_id and t.status = 'open' and not m.is_leader;
