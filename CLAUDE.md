# Project Overview

Bearch: UPH teammate matchmaking app (hackathon, team Bear Invasion). Flutter mobile app
(Android + iOS, students and Student Affairs admins) on Supabase.
Figma: file `fyWqt34xTrfpNFsDiFRfhK`. Starter plan, tight MCP limits, so read it sparingly.
Frame ids are in README/screen placeholders.

# Development Commands

- App (preview mode, sample data): `cd app && flutter run`
- App (real backend): `cd app && flutter run --dart-define-from-file=env.json`
- Analyze / test app: `cd app && flutter analyze && flutter test`
- DB tests (PGlite, no Docker): `cd supabase/tests && npm install && npm test`
- Supabase CLI: `npx supabase ...` (brew is blocked on this Mac); project ref `qsycmdpktmdbcgeddyil`
- Push migrations: `npx supabase db push --remote` (hosted changes need `--yes`: ask the user first)
- Deploy functions: `npx supabase functions deploy infer-skills check-duplicate --use-api`

# Architecture & Tech Stack

- App: Flutter, Riverpod 3, go_router, google_fonts pinned `^8` (9.x breaks TextTheme on Flutter 3.47)
- Style: Apple-like glassmorphism, Montserrat, accent `#0071E3`, light + dark, drawer navigation
- Backend: Supabase Postgres + RLS + pg_cron, auth = UPH email OTP (6 digits)
- Edge Functions (Deno/TS): `infer-skills`, `check-duplicate`; Gemini key server-side only
- Business rules live in the DB (SECURITY DEFINER RPCs), not in the app. `app/lib/data/bearch_api.dart` only maps calls.

# Project Rules

- New migration file for every schema change; never edit a migration already pushed to hosted.
- New client RPC needs an explicit `grant execute ... to authenticated` (default privileges revoke it).
- SECURITY DEFINER functions: `set search_path = ''` and fully qualified names.
- Keep locked decisions: single reputation score (no activity score); team lock at H-1 23:59 WIB, manual earlier, no unlock, no member replacement, pending requests auto-rejected; AI skill inference only when the leader set no required skills (cached per competition); fallback text "Skill yang dibutuhkan belum diatur".
- Secrets: `app/env.json` and `supabase/functions/.env` are gitignored. Never commit keys.
- Run DB tests after SQL changes and `flutter analyze` + `flutter test` after Dart changes.

# Persona & Behavior Rules (Caveman Mode)

- Be extremely concise and direct.
- No pleasantries, conversational fluff, or apologies.
- Minimize text explanations to save token budget.
- Focus purely on tool execution, clean code, and file modifications.
- Prefer editing files directly rather than printing code snippets in chat.
