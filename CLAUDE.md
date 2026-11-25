# Project Context: UPH Competition & Matchmaking Platform
- **Goal:** Hackathon MVP for UPH students to find teammates, manage competition lobbies, validate SEP claims, and track team reputation.
- **Language & Naming:** English identifiers (`camelCase` for variables/functions, `PascalCase` for components, `snake_case` for DB columns). UI copy in English/Indonesian as needed.

---

# Agentic Workflow Rules (Caveman + Superpowers + ECC)
0. **Plugin roles (no overlap):** Superpowers = process only (brainstorm, write-plan, execute-plan, verification). ECC = coding rules/standards only; do NOT use ECC's plan/tdd/review commands that duplicate Superpowers. Caveman = output style only.
1. **Caveman Output (Default):** Be ultra-terse. Zero pleasantries, zero filler intros/outros. Output raw diffs, concise bullet status, and shell commands only.
2. **Superpowers Discipline:**
   - Before building multi-file features, draft a brief step-by-step plan (`/write-plan`) and execute sequentially (`/execute-plan`).
   - **Surgical edits only:** Never refactor or reformat working files unrelated to the active task.
   - **Verify before done:** Run build and type-check commands before reporting completion.
3. **ECC Architecture:**
   - Keep components and modules focused and under 250 lines. Split complex UI into subcomponents and custom hooks.
   - Enforce strict TypeScript types and handle loading, empty, and error states on every async action.

---

# Scope Guardrails (STRICT PHASE 1 MVP ONLY)
Build ONLY Phase 1 features below. **DO NOT** generate code, routes, or DB tables for out-of-scope items.

### Included in Phase 1:
- **Core:** UPH email + OTP login (`Student`, `Admin`).
- **Profile & Matchmaking:**
  - Student profile: major, hard skills, soft skills.
  - Browse & detail competitions.
  - Lobby broadcast + join approval request, plus direct teammate invite.
  - AI teammate recommendation: infer required skills from competition details and output clear per-candidate reasoning.
  - Team lock lifecycle: manual lock by Leader before H-1; system auto-lock at H-1 registration deadline (auto-reject pending requests, permanent lock/no unlock); automated reminder at H-3/H-2 if team slots are still open.
- **Admin Gatekeeper:**
  - Student submits competition info -> AI duplicate check (comparing organizer, category, timeline, name) -> allow submission with override reason.
  - Admin validation queue displaying `"possible duplicate"` warning badge.
- **Lobby Collaboration:** Shared team availability calendar and team group chat.
- **Reporting & Appeal:** Report member with concrete evidence -> target student appeal -> Admin review & resolution.
- **Rating, SEP & Analytics:**
  - Unified hard + soft skill peer rating system.
  - Upload winning result (strictly gated: block upload until peer ratings are submitted).
  - SEP claim + Admin validation + UPH Mobile sync status.
  - Reputation score calculated strictly from peer ratings + verified reports.
  - Admin analytics dashboard: time-to-team, cross-major rate, retention rate.

### Explicitly Out of Scope (DO NOT BUILD):
- Freemium / billing / subscription tiers.
- Squad system.
- Activity score metrics.
- Mentorship matching (Phase 2), External portfolio links (Phase 2).
- Auto hard-skill tiering from portfolio, In-depth profile verification (Phase 3).

---

# UI & Design System (Mandatory)
- **Aesthetic:** Apple-inspired frosted glassmorphism with subtle blurs (`backdrop-filter: blur(16px)`), delicate semi-transparent borders, and clean card containers.
- **Color Palette:**
  - Primary Accent: Apple System Blue (`#0071E3` / Tailwind `blue-500` to `blue-600`) for primary buttons, focus rings, active tabs, progress bars, and highlight badges.
  - Glass Reflections & Glow: Soft blue-tinted highlights (`rgba(0, 113, 227, 0.08)` to `rgba(59, 130, 246, 0.15)`).
- **Readability First:** Outer layout shells use frosted blur, while text inputs, forms, and data/metric cards must maintain high foreground-to-background contrast (never washed-out text).
- **Typography:** Load and apply Google Font `'Montserrat'` across the entire application.
- **Theme Support:** Include an accessible Light Mode / Dark Mode toggle button that smoothly transitions frosted glass surfaces, dark slate backdrops, and deep azure glow accents.

---

# Stack Mapping (this repo is Flutter, not web)
The rules above use web terms. In this repo they mean:
- `backdrop-filter: blur(16px)` -> `BackdropFilter(ImageFilter.blur(sigmaX: 16, sigmaY: 16))` via `GlassTokens.blur` (`app/lib/core/theme.dart`).
- `#0071E3` -> `BearchColors.accent` (`Color(0xFF0071E3)`); glow -> `GlassTokens.blobs`. Tailwind classes do not apply.
- Montserrat -> `google_fonts` (`GoogleFonts.montserratTextTheme`), pinned `^8` (9.x breaks `TextTheme` on Flutter 3.47).
- Light/Dark toggle -> `themeModeProvider` + toggle in the app bar.
- "Strict TypeScript" -> strict Dart types in `app/` (no `dynamic` leaking out of the data layer) and strict TS in `supabase/functions/` (`deno check`).
- "Components and custom hooks" -> widgets and Riverpod providers; the 250-line limit applies to Dart and TS source files. SQL migrations are append-only (never edited after push), so they are exempt; keep new ones focused.

# Development Commands
- App (preview mode, sample data): `cd app && flutter run`
- App (real backend): `cd app && flutter run --dart-define-from-file=env.json`
- Analyze / test app: `cd app && flutter analyze && flutter test`
- Edge Functions type-check: `cd supabase/functions && npx -y deno@2 check infer-skills/index.ts check-duplicate/index.ts`
- DB tests (PGlite, no Docker): `cd supabase/tests && npm install && npm test`
- Supabase CLI: `npx supabase ...` (brew is blocked on this Mac); project ref `qsycmdpktmdbcgeddyil`
- Push migrations / deploy: `npx supabase db push --remote`, `npx supabase functions deploy infer-skills check-duplicate --use-api` (hosted changes need `--yes`: ask the user first)

# Backend Rules
- Business rules live in the DB (SECURITY DEFINER RPCs); `app/lib/data/bearch_api.dart` only maps calls.
- New migration file for every schema change; never edit a migration already pushed to hosted.
- New client RPC needs an explicit `grant execute ... to authenticated` (default privileges revoke it).
- SECURITY DEFINER functions: `set search_path = ''` and fully qualified names.
- Lock rule details: auto-lock 23:59 WIB on H-1 (pg_cron every 5 min); fallback text when no skills: "Skill yang dibutuhkan belum diatur".
- Secrets: `app/env.json` and `supabase/functions/.env` are gitignored. Never commit keys.
- Figma: file `fyWqt34xTrfpNFsDiFRfhK`, Starter plan with tight MCP limits; read sparingly.
