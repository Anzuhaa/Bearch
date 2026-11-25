# Plan: Phase 1 screens (replace "To build" placeholders)

Order follows the demo script. Each screen: loading / empty / error states, < 250 lines,
reads via Supabase (RLS), writes via RPCs in `BearchApi`. Detail pages are full-screen
routes outside the drawer shell so Android back works naturally.

## Batch A (demo steps 1-4)
1. Shared: `core/async_ui.dart` (AsyncView, runAction, dialogs, PageScaffold, NeedsBackend).
   `/home` resolver: admins land on `/admin`, students on `/browse`.
2. Competition detail `/competition/:id`: header, timeline + H-1 lock note, lobbies with
   members/needed skills, Open a lobby (create_team), Request to join, Manage my lobby.
3. My Lobbies `/lobbies` -> Lobby `/lobby/:id`: members, needed skills (leader edits),
   H-3/H-2 banner, join requests approve/decline, pending invites, lock (confirm, no unlock),
   leave/disband. Recommendations `/lobby/:id/recommend`: infer-skills (source + fallback
   "Skill yang dibutuhkan belum diatur"), ranked candidates with reasons, invite.
4. Invites `/invites`: accept/decline invites (48h), my join requests (cancel).
5. Submit `/submit`: form + proof (link or file upload) -> draft -> check-duplicate ->
   possible-duplicate card + override reason -> submit_competition; my submissions list.
6. Admin `/admin` stats; `/admin/competitions` queue with duplicate badge, approve/reject.

Verify: flutter analyze + test, build APK, walk the demo on the phone via adb.

## Batch B (demo steps 5-6)
Team chat (realtime), team calendar (heatmap + edit availability), rate teammates + SEP
claim (upload gated), reports & appeals, admin reports + SEP verify, onboarding profile.
