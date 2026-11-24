-- Function privileges, pg_cron jobs and realtime publication.

-- ---------------------------------------------------------------------------
-- Function privileges: nothing is callable unless granted here.
-- Future migrations must GRANT EXECUTE explicitly for new client RPCs.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

-- Safe uuid cast for storage path parsing.
create or replace function public.try_uuid(p text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p::uuid;
exception when others then
  return null;
end;
$$;

grant execute on function
  -- RLS helpers / utilities
  public.is_admin(),
  public.is_team_member(uuid),
  public.is_team_leader(uuid),
  public.can_see_competition(uuid),
  public.try_uuid(text),
  public.today_wib(),
  public.competition_lock_at(date),
  public.team_open_slots(uuid),
  public.normalize_competition_name(text),
  -- teams / lobbies
  public.create_team(uuid, text, text, integer, boolean, boolean, jsonb),
  public.request_join(uuid, text),
  public.cancel_join_request(uuid),
  public.decide_join_request(uuid, boolean),
  public.send_invite(uuid, uuid, text, text),
  public.respond_invite(uuid, boolean),
  public.cancel_invite(uuid),
  public.leave_team(uuid),
  public.disband_team(uuid),
  public.lock_team(uuid),
  -- matching & calendar
  public.team_matching_skills(uuid),
  public.availability_overlap_pct(uuid, uuid),
  public.team_availability_heatmap(uuid),
  public.recommend_candidates(uuid, integer),
  -- competitions
  public.submit_competition(uuid, text),
  public.admin_review_competition(uuid, boolean, text),
  -- ratings / reports / SEP / admin
  public.can_rate_team(uuid),
  public.submit_rating(uuid, uuid, jsonb, jsonb, text),
  public.my_rating_progress(uuid),
  public.file_report(uuid, uuid, public.report_reason, text, jsonb),
  public.submit_appeal(uuid, text, jsonb),
  public.reports_about_me(),
  public.admin_decide_report(uuid, public.report_status, text, boolean),
  public.sep_estimate(uuid, text),
  public.sep_claim_blockers(uuid),
  public.submit_sep_claim(uuid, text, text, text),
  public.admin_verify_sep_claim(uuid, boolean, integer, text),
  public.admin_dashboard_stats()
to authenticated;

-- The auth trigger runs as supabase_auth_admin.
grant execute on function public.handle_new_user() to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- pg_cron (times are UTC; WIB = UTC+7)
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;

-- Lock teams that reached H-1 23:59 WIB. RPCs already refuse changes after the
-- lock time, so a few minutes of cron lag cannot let anyone sneak in.
select cron.schedule('bearch-auto-lock', '*/5 * * * *', $$select public.auto_lock_due_teams()$$);

-- H-3 / H-2 warnings to leaders at 08:00 WIB.
select cron.schedule('bearch-lock-warnings', '0 1 * * *', $$select public.send_lock_warnings()$$);

-- Free slots reserved by 48h invites that nobody answered.
select cron.schedule('bearch-expire-invites', '*/15 * * * *', $$select public.expire_invites()$$);

-- ---------------------------------------------------------------------------
-- Realtime (postgres_changes respects RLS)
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table
  public.messages,
  public.notifications,
  public.join_requests,
  public.team_invites,
  public.team_members,
  public.teams;
