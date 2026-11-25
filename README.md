# Bearch

Teammate matchmaking for UPH students: verified competitions, approval-based lobbies,
AI-assisted cross-major matching, shared team calendars, peer reputation and SEP claims.
Built by **Bear Invasion** for UPH STACK Hackathon 2026.

```
app/                Flutter app (Android + iOS). Students and Student Affairs admins.
supabase/
  migrations/       Postgres schema, RLS, RPCs, pg_cron jobs, storage policies
  functions/        Edge Functions (TypeScript/Deno): infer-skills, check-duplicate (Gemini)
  tests/            DB scenario tests on in-memory Postgres (no Docker needed)
  seed.sql          Majors, skills, SEP point table (placeholder), demo competitions
```

## Run the app

```bash
cd app
flutter pub get
flutter run                                   # preview mode: no backend, sample data
flutter run --dart-define-from-file=env.json  # real backend (copy env.example.json -> env.json)
```

Preview mode has a "Preview as admin" switch in the drawer, so the UI can be built and demoed
before Supabase is set up.

## Backend

Needs the [Supabase CLI](https://supabase.com/docs/guides/cli) (+ Docker for local).

```bash
supabase start                 # local stack; OTP emails land in Inbucket http://127.0.0.1:54324
supabase db reset              # applies migrations + seed.sql
cp supabase/functions/.env.example supabase/functions/.env   # add GEMINI_API_KEY
supabase functions serve
```

Hosted: `supabase link`, `supabase db push`, `supabase functions deploy infer-skills check-duplicate`,
`supabase secrets set GEMINI_API_KEY=...`. Add Student Affairs accounts with
`insert into email_allowlist(email, role) values ('…@uph.edu', 'admin');` before they first sign in
(demo/judge accounts: same table with role `student`; see `supabase/scripts/demo_accounts.mjs`).

Demo accounts / reset before a rehearsal (needs the service-role key, never commit it):

```bash
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=... DEMO_PASSWORD=... \
  node supabase/scripts/demo_accounts.mjs --reset
```

Resets to: open lobby "Bear Invasion (Demo)" on UPH STACK 2026 (Satria leads, AI recs path) and a
finished, locked "Pitch Perfect (Demo)" on Hology 8.0 (ready for ratings, SEP claim, reports).

DB tests (no Docker):

```bash
cd supabase/tests && npm install && npm test
```

## Rules encoded in the database

| Rule | Where |
| --- | --- |
| Only `@student.uph.edu` / `@uph.edu` (or allowlisted admins) can sign up | `handle_new_user` trigger |
| One team per student per competition | `team_members` unique constraint |
| Teams auto-lock at **H-1 23:59 WIB** (pg_cron, every 5 min); leaders may lock earlier, even if not full | `auto_lock_due_teams`, `lock_team` |
| On lock: pending requests auto-rejected, pending invites cancelled | `lock_team_internal` |
| No unlock, no member add/remove/replace after lock | `guard_team_update`, `guard_team_members` triggers |
| H-3 and H-2 warnings to leaders (08:00 WIB daily, deduped) | `send_lock_warnings` |
| Direct invites reserve a slot for 48h | `team_open_slots`, `expire_invites` |
| AI skill inference only when the leader set no required skills; cached once per competition | `infer-skills` fn, `competitions.inferred_skill_ids` |
| Ranking in the DB: skill overlap + cross-major bonus + reputation + availability, with reasons | `recommend_candidates` |
| Fallback when no skills: "Skill yang dibutuhkan belum diatur" | `recommend_candidates` returns 0 rows + app copy |
| Duplicate check: organizer + category + timeline + fuzzy name, AI verdict, override reason, admin sees flag; AI down → manual review | `find_duplicate_candidates`, `check-duplicate` fn, `submit_competition` |
| One reputation score from peer ratings (no activity score), minus upheld/false reports | `submit_rating`, `recompute_reputation` |
| Reported members see reason + evidence, not the reporter | `reports_about_me` |
| SEP claim needs: verified competition, locked team, all teammates rated, no open reports | `sep_claim_blockers` |

Clients only get the RPCs granted in `20261125000700_cron_realtime_grants.sql`; new RPCs need an
explicit `grant execute ... to authenticated`.

## Open items

- SEP points in `sep_point_rules` are placeholders until we have the official UPH SEP guideline.
- "Sign in with UPH Mobile" and pushing SEP to UPH Mobile need an official UPH integration.
- Email OTP for real UPH addresses needs a custom SMTP provider (Supabase free tier limitation); demo accounts use password login.
