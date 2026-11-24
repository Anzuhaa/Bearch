-- Newer Supabase projects no longer grant table privileges to service_role by
-- default. Edge Functions (adminClient) and admin scripts need them.
-- service_role bypasses RLS; it is only ever used server-side.

grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;

-- Sequences used by client-visible inserts (none today: reports.code and
-- ai_calls.id are only written by SECURITY DEFINER functions / service_role).
