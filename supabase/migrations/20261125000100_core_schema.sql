-- Bearch core schema: extensions, enums, tables, indexes.
-- Conventions: every table lives in `public`, uses uuid PKs, timestamptz in UTC.
-- Business time zone for deadlines is Asia/Jakarta (WIB).

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('student', 'admin');
create type public.skill_kind as enum ('hard', 'soft');
create type public.competition_category as enum
  ('technology', 'business', 'design', 'science', 'social_impact', 'non_academic');
create type public.competition_level as enum ('campus', 'regional', 'national', 'international');
create type public.competition_status as enum ('draft', 'pending', 'approved', 'rejected');
create type public.duplicate_status as enum
  ('not_checked', 'clear', 'possible_duplicate', 'check_failed');
create type public.team_status as enum ('open', 'locked');
create type public.lock_reason as enum ('manual', 'auto');
create type public.request_status as enum
  ('pending', 'approved', 'declined', 'auto_rejected', 'cancelled');
create type public.invite_status as enum
  ('pending', 'accepted', 'declined', 'expired', 'cancelled');
create type public.report_reason as enum
  ('non_contribution', 'missed_deadlines', 'no_show', 'disrespectful', 'other');
create type public.report_status as enum
  ('awaiting_appeal', 'appealed', 'info_requested', 'upheld', 'dismissed');
create type public.sep_claim_status as enum ('submitted', 'verified', 'rejected');

-- ---------------------------------------------------------------------------
-- Access control lists
-- ---------------------------------------------------------------------------
-- Sign-up is limited to these email domains (UPH accounts only).
create table public.allowed_email_domains (
  domain text primary key check (domain = lower(domain))
);

-- Emails listed here become admins (Student Affairs) on first sign-in and may
-- bypass the domain check (useful for demo/judge accounts).
create table public.admin_allowlist (
  email text primary key check (email = lower(email)),
  note text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create table public.majors (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  faculty text not null
);

create table public.skills (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind public.skill_kind not null,
  created_at timestamptz not null default now()
);
create unique index skills_name_lower_key on public.skills (lower(name));

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  full_name text not null default '',
  avatar_url text,
  major_id uuid references public.majors (id),
  batch smallint check (batch between 2000 and 2100),
  role public.user_role not null default 'student',
  portfolio_url text,
  linkedin_url text,
  onboarded boolean not null default false,
  -- Single reputation score (1.00-5.00) from peer ratings, minus upheld-report
  -- penalties. NULL until the first rating. No separate activity score.
  reputation numeric(3, 2),
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_major_idx on public.profiles (major_id);

-- Self-assessed level 1..4 (beginner, intermediate, advanced, expert).
-- peer_level is the running average of peer tiers from ratings.
create table public.profile_skills (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  skill_id uuid not null references public.skills (id) on delete cascade,
  level smallint not null check (level between 1 and 4),
  peer_level numeric(3, 2),
  peer_count integer not null default 0,
  primary key (profile_id, skill_id)
);
create index profile_skills_skill_idx on public.profile_skills (skill_id);

-- Weekly recurring free slots (local WIB time). weekday: 1 = Monday .. 7 = Sunday.
create table public.availability_slots (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  source text not null default 'manual' check (source in ('manual', 'uph_timetable', 'google')),
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);
create index availability_profile_idx on public.availability_slots (profile_id, weekday);

-- ---------------------------------------------------------------------------
-- Competitions
-- ---------------------------------------------------------------------------
create table public.competitions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 2),
  organizer text not null,
  category public.competition_category not null,
  level public.competition_level not null,
  description text not null default '',
  official_url text,
  guidebook_url text,
  prize text,
  -- Last day of registration (WIB). Teams auto-lock at 23:59 WIB the day before (H-1).
  registration_deadline date not null,
  event_start date,
  event_end date,
  announcement_date date,
  team_min smallint not null default 1 check (team_min >= 1),
  team_max smallint not null check (team_max >= 1),
  status public.competition_status not null default 'draft',
  submitted_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  -- AI duplicate check (written by the check-duplicate Edge Function only).
  duplicate_status public.duplicate_status not null default 'not_checked',
  duplicate_of uuid references public.competitions (id) on delete set null,
  duplicate_score numeric(4, 3),
  duplicate_reasons jsonb not null default '[]'::jsonb,
  duplicate_checked_at timestamptz,
  duplicate_override_reason text,
  -- AI-inferred required skills, cached once per competition (infer-skills Edge Function).
  inferred_skill_ids uuid[],
  inferred_skills_at timestamptz,
  inferred_skills_model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (team_max >= team_min),
  check (event_end is null or event_start is null or event_end >= event_start)
);
create index competitions_status_idx on public.competitions (status, registration_deadline);
create index competitions_submitted_by_idx on public.competitions (submitted_by);
create index competitions_name_trgm_idx on public.competitions
  using gin (lower(name) extensions.gin_trgm_ops);
create index competitions_organizer_trgm_idx on public.competitions
  using gin (lower(organizer) extensions.gin_trgm_ops);

-- Proof of legitimacy (poster / guidebook) stored in the `competition-proofs` bucket.
create table public.competition_files (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions (id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  size_bytes bigint,
  uploaded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index competition_files_comp_idx on public.competition_files (competition_id);

-- ---------------------------------------------------------------------------
-- Teams (a.k.a. lobbies)
-- ---------------------------------------------------------------------------
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions (id) on delete cascade,
  leader_id uuid not null references public.profiles (id),
  name text not null check (length(trim(name)) between 2 and 60),
  pitch text not null default '',
  max_members smallint not null check (max_members >= 1),
  approval_based boolean not null default true,
  cross_major_preferred boolean not null default true,
  status public.team_status not null default 'open',
  locked_at timestamptz,
  lock_reason public.lock_reason,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (competition_id, name),
  check ((status = 'locked') = (locked_at is not null))
);
create index teams_competition_idx on public.teams (competition_id, status);
create index teams_leader_idx on public.teams (leader_id);

-- competition_id is denormalised so "one team per student per competition" is a constraint.
create table public.team_members (
  team_id uuid not null references public.teams (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  competition_id uuid not null references public.competitions (id) on delete cascade,
  is_leader boolean not null default false,
  role_label text,
  joined_at timestamptz not null default now(),
  primary key (team_id, profile_id),
  unique (competition_id, profile_id)
);
create index team_members_profile_idx on public.team_members (profile_id);

-- Skills the leader says the team still needs ("Looking for ...").
-- If a team has none, AI inference kicks in (see infer-skills Edge Function).
create table public.team_required_skills (
  team_id uuid not null references public.teams (id) on delete cascade,
  skill_id uuid not null references public.skills (id) on delete cascade,
  role_label text,
  primary key (team_id, skill_id)
);

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  message text not null default '',
  status public.request_status not null default 'pending',
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index join_requests_one_pending
  on public.join_requests (team_id, profile_id) where status = 'pending';
create index join_requests_profile_idx on public.join_requests (profile_id, status);

-- Direct invites skip the request queue and reserve a slot for 48h.
create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  invitee_id uuid not null references public.profiles (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  role_label text,
  message text not null default '',
  status public.invite_status not null default 'pending',
  expires_at timestamptz not null default now() + interval '48 hours',
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index team_invites_one_pending
  on public.team_invites (team_id, invitee_id) where status = 'pending';
create index team_invites_invitee_idx on public.team_invites (invitee_id, status);

-- ---------------------------------------------------------------------------
-- Collaboration: chat + meetings
-- ---------------------------------------------------------------------------
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  body text not null default '',
  attachment_path text,
  attachment_name text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  check (length(body) > 0 or attachment_path is not null)
);
create index messages_team_idx on public.messages (team_id, created_at desc);

create table public.team_meetings (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  pinned boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index team_meetings_team_idx on public.team_meetings (team_id, starts_at);

-- ---------------------------------------------------------------------------
-- Peer ratings (anonymous; aggregated into profiles.reputation)
-- ---------------------------------------------------------------------------
create table public.peer_ratings (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  rater_id uuid not null references public.profiles (id) on delete cascade,
  ratee_id uuid not null references public.profiles (id) on delete cascade,
  -- Average of the soft-skill stars below; this is what feeds reputation.
  score numeric(3, 2) not null check (score between 1 and 5),
  comment text, -- visible to admins only
  created_at timestamptz not null default now(),
  unique (team_id, rater_id, ratee_id),
  check (rater_id <> ratee_id)
);
create index peer_ratings_ratee_idx on public.peer_ratings (ratee_id);

-- Hard-skill tier demonstrated during the competition: 1 novice .. 4 expert.
create table public.peer_rating_skills (
  rating_id uuid not null references public.peer_ratings (id) on delete cascade,
  skill_id uuid not null references public.skills (id) on delete cascade,
  tier smallint not null check (tier between 1 and 4),
  primary key (rating_id, skill_id)
);

-- Soft-skill stars 1..5 on a fixed set of criteria.
create table public.peer_rating_criteria (
  rating_id uuid not null references public.peer_ratings (id) on delete cascade,
  criterion text not null
    check (criterion in ('communication', 'time_management', 'teamwork', 'responsibility')),
  stars smallint not null check (stars between 1 and 5),
  primary key (rating_id, criterion)
);

-- ---------------------------------------------------------------------------
-- Reports & appeals
-- ---------------------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  code serial unique, -- shown as #R-0142
  team_id uuid not null references public.teams (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_id uuid not null references public.profiles (id) on delete cascade,
  reason public.report_reason not null,
  description text not null check (length(trim(description)) >= 20),
  status public.report_status not null default 'awaiting_appeal',
  appeal_deadline timestamptz not null default now() + interval '7 days',
  appeal_text text,
  appealed_at timestamptz,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
create index reports_reported_idx on public.reports (reported_id, status);
create index reports_reporter_idx on public.reports (reporter_id);
create index reports_team_idx on public.reports (team_id, status);

create table public.report_evidence (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id) on delete cascade,
  uploaded_by uuid not null references public.profiles (id) on delete cascade,
  side text not null check (side in ('report', 'appeal')),
  label text not null,
  storage_path text,
  external_url text,
  created_at timestamptz not null default now()
);
create index report_evidence_report_idx on public.report_evidence (report_id);

-- ---------------------------------------------------------------------------
-- SEP (Student Engagement Points) claims
-- ---------------------------------------------------------------------------
-- Placeholder point table; final points follow the official UPH SEP guideline
-- and are confirmed by Student Affairs when verifying a claim.
create table public.sep_point_rules (
  level public.competition_level not null,
  placement text not null, -- 'winner_1', 'winner_2', 'winner_3', 'finalist', 'participant'
  points integer not null check (points >= 0),
  primary key (level, placement)
);

create table public.sep_claims (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null unique references public.teams (id) on delete cascade,
  submitted_by uuid not null references public.profiles (id),
  placement text not null,
  placement_label text not null,
  announcement_url text,
  estimated_points integer,
  status public.sep_claim_status not null default 'submitted',
  verified_points integer,
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);

create table public.sep_claim_files (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.sep_claims (id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Notifications + AI call log
-- ---------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  -- Set by cron jobs so the same warning is never sent twice.
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_profile_idx on public.notifications (profile_id, created_at desc);
create unique index notifications_dedupe_key
  on public.notifications (profile_id, dedupe_key) where dedupe_key is not null;

create table public.ai_calls (
  id bigserial primary key,
  fn text not null,
  competition_id uuid references public.competitions (id) on delete set null,
  profile_id uuid references public.profiles (id) on delete set null,
  ok boolean not null,
  detail text,
  created_at timestamptz not null default now()
);
create index ai_calls_recent_idx on public.ai_calls (fn, created_at desc);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger competitions_updated_at before update on public.competitions
  for each row execute function public.set_updated_at();
create trigger teams_updated_at before update on public.teams
  for each row execute function public.set_updated_at();
