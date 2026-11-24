import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/session.dart';
import 'features/auth/login_screen.dart';
import 'features/competitions/browse_screen.dart';
import 'features/placeholder_screen.dart';
import 'shell/app_shell.dart';

/// One drawer destination. `figma` and `plan` describe screens that are still
/// placeholders, so whoever picks a screen up knows what to build.
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.figma = const [],
    this.plan = const [],
    this.backend = const [],
  });

  final String path;
  final String label;
  final IconData icon;
  final List<String> figma;
  final List<String> plan;
  final List<String> backend;
}

class NavSection {
  const NavSection(this.title, this.items);
  final String title;
  final List<NavItem> items;
}

const browseItem = NavItem(path: '/browse', label: 'Browse Competitions', icon: Icons.grid_view_rounded);

const studentNav = [
  NavSection('Discover', [
    browseItem,
    NavItem(
      path: '/submit',
      label: 'Submit Competition',
      icon: Icons.add_rounded,
      figma: ['15 · Submit Competition', '16 · Submitted · Pending Validation'],
      plan: [
        'Form: name, organizer, category, level, deadline, team size, link, description',
        'Upload poster/guidebook to storage bucket competition-proofs/<competition_id>/',
        'Run AI duplicate check; show "Possible duplicate found" card with reason chips',
        'Submit anyway with a reason; Student Affairs sees the flag',
      ],
      backend: ['insert competitions (draft)', 'fn check-duplicate', 'rpc submit_competition'],
    ),
    NavItem(
      path: '/lobbies',
      label: 'My Lobbies',
      icon: Icons.groups_rounded,
      figma: ['06 · Lobby · Manage Broadcast', '07 · AI Teammate Recommendations', '08 · Find Teammates', '09 · Team Locked'],
      plan: [
        'Team slots, join requests (approve/decline), team balance check',
        'H-3 / H-2 banner: auto-locks H-1 23:59 WIB even if not full',
        '"Lock team now" (no unlock; pending requests get auto-rejected)',
        'AI recommendations with "Why" reasons; fallback "Skill yang dibutuhkan belum diatur"',
        'Direct invite modal (slot reserved 48h)',
      ],
      backend: [
        'rpc create_team / decide_join_request / send_invite / lock_team',
        'fn infer-skills + rpc recommend_candidates',
      ],
    ),
    NavItem(
      path: '/invites',
      label: 'Invites',
      icon: Icons.mail_outline_rounded,
      plan: ['Pending invites with 48h countdown', 'Accept / decline', 'My join requests (cancel)'],
      backend: ['select team_invites / join_requests', 'rpc respond_invite / cancel_join_request'],
    ),
  ]),
  NavSection('My Team', [
    NavItem(
      path: '/team/chat',
      label: 'Team Chat',
      icon: Icons.chat_bubble_outline_rounded,
      figma: ['11 · Team Chat'],
      plan: ['Realtime messages + attachments', 'Pinned meeting', 'Team info side sheet'],
      backend: ['realtime messages', 'storage chat-attachments/<team_id>/', 'team_meetings'],
    ),
    NavItem(
      path: '/team/calendar',
      label: 'Team Calendar',
      icon: Icons.calendar_month_rounded,
      figma: ['10 · Team Calendar · Shared Availability'],
      plan: ['Weekly heatmap of free members', 'Best slots this week', 'Edit my availability'],
      backend: ['rpc team_availability_heatmap', 'availability_slots'],
    ),
    NavItem(
      path: '/team/rate',
      label: 'Rate & Claim SEP',
      icon: Icons.workspace_premium_outlined,
      figma: ['12 · Rate Teammates', '13 · Upload Result · SEP Claim', '14 · SEP Claim Submitted'],
      plan: [
        'Rate each teammate: hard-skill tiers + soft-skill stars (one reputation score)',
        'Unlock checklist, upload certificate, SEP estimate',
      ],
      backend: ['rpc my_rating_progress / submit_rating', 'rpc sep_claim_blockers / submit_sep_claim'],
    ),
    NavItem(
      path: '/reports',
      label: 'Reports & Appeals',
      icon: Icons.flag_outlined,
      figma: ['18 · Report a Member', '19 · Reports & Appeals'],
      plan: ['Fact-based report with evidence', 'Reports about me + 7-day appeal'],
      backend: ['rpc file_report / reports_about_me / submit_appeal', 'storage report-evidence/'],
    ),
  ]),
];

const adminNav = [
  NavSection('Student Affairs', [
    NavItem(
      path: '/admin',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      figma: ['17 · Admin · Student Affairs Dashboard'],
      plan: ['KPIs: time-to-team, cross-major %, retention, SEP credited', 'Queues summary'],
      backend: ['rpc admin_dashboard_stats'],
    ),
    NavItem(
      path: '/admin/competitions',
      label: 'Competition Queue',
      icon: Icons.fact_check_outlined,
      figma: ['17 · validation queue'],
      plan: ['Pending submissions with proof files', 'Possible-duplicate flag + override reason', 'Approve / reject'],
      backend: ['select competitions where status = pending', 'rpc admin_review_competition'],
    ),
    NavItem(
      path: '/admin/reports',
      label: 'Reports & Appeals',
      icon: Icons.gavel_rounded,
      figma: ['20 · Admin · Report & Appeal Review'],
      plan: ['Report vs appeal side by side', 'Context: reputation, prior reports', 'Uphold / dismiss / request info'],
      backend: ['select reports + report_evidence', 'rpc admin_decide_report'],
    ),
    NavItem(
      path: '/admin/sep',
      label: 'SEP Claims',
      icon: Icons.verified_outlined,
      plan: ['Verify certificate', 'Confirm points per member'],
      backend: ['select sep_claims + sep_claim_files', 'rpc admin_verify_sep_claim'],
    ),
  ]),
  NavSection('Discover', [browseItem]),
];

const onboardingItem = NavItem(
  path: '/onboarding',
  label: 'Set Up Skill Profile',
  icon: Icons.person_outline_rounded,
  figma: ['03 · Set Up Skill Profile'],
  plan: ['Faculty/program + batch', 'Hard skills with level, soft skills', 'Availability', 'Portfolio + LinkedIn'],
  backend: ['update profiles', 'profile_skills', 'availability_slots'],
);

List<NavItem> get _allItems => {
      for (final s in [...studentNav, ...adminNav]) ...s.items,
    }.toList();

NavItem? navItemFor(String location) {
  NavItem? best;
  for (final item in _allItems) {
    if (location == item.path || location.startsWith('${item.path}/')) {
      if (best == null || item.path.length > best.path.length) best = item;
    }
  }
  return best;
}

/// Re-runs GoRouter redirects whenever the Supabase session changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(SupabaseClient? client) {
    _sub = client?.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  StreamSubscription<AuthState>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final refresh = _AuthRefresh(client);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/browse',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final atAuth = loc == '/login' || loc == '/verify';
      if (client == null) return atAuth ? '/browse' : null; // preview mode: no auth
      final signedIn = client.auth.currentSession != null;
      if (!signedIn) return atAuth ? null : '/login';
      if (atAuth) return '/browse';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/verify',
        builder: (context, state) => VerifyOtpScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: '/onboarding', builder: (context, state) => const PlaceholderScreen(item: onboardingItem)),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/browse',
            builder: (context, state) => const BrowseScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => PlaceholderScreen(
                  item: NavItem(
                    path: '/browse/${state.pathParameters['id']}',
                    label: 'Competition Detail',
                    icon: Icons.emoji_events_outlined,
                    figma: const ['05 · Competition Detail'],
                    plan: const [
                      'Header: verified pill, level, deadline, team size, prize, SEP on win',
                      'Open lobbies sorted by skill match (Request to join / Manage lobby)',
                      'Timeline with "Lobbies auto-lock at H-1" note',
                      'Open a lobby',
                    ],
                    backend: const ['select competitions + teams', 'rpc create_team / request_join'],
                  ),
                ),
              ),
            ],
          ),
          for (final item in _allItems.where((i) => i.path != '/browse'))
            GoRoute(path: item.path, builder: (context, state) => PlaceholderScreen(item: item)),
        ],
      ),
    ],
  );
});
