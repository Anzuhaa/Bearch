import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/session.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/admin/competition_queue_screen.dart';
import 'features/admin/reports_review_screen.dart';
import 'features/admin/sep_claims_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/verify_otp_screen.dart';
import 'features/competitions/browse_screen.dart';
import 'features/competitions/competition_detail_screen.dart';
import 'features/competitions/submit_competition_screen.dart';
import 'features/invites/invites_screen.dart';
import 'features/lobbies/lobby_screen.dart';
import 'features/lobbies/my_lobbies_screen.dart';
import 'features/lobbies/recommendations_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/team/rate_claim_screen.dart';
import 'features/team/team_calendar_screen.dart';
import 'features/team/team_chat_screen.dart';
import 'features/team/team_hub_screen.dart';
import 'shell/app_shell.dart';
import 'shell/home_redirect.dart';
import 'shell/nav_items.dart';

export 'shell/nav_items.dart';

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

/// Screen for each drawer destination in nav_items.dart.
final Map<String, Widget Function()> _builtScreens = {
  '/browse': () => const BrowseScreen(),
  '/submit': () => const SubmitCompetitionScreen(),
  '/teams': () => const MyLobbiesScreen(),
  '/invites': () => const InvitesScreen(),
  '/admin': () => const AdminDashboardScreen(),
  '/admin/competitions': () => const CompetitionQueueScreen(),
  '/admin/reports': () => const ReportsReviewScreen(),
  '/admin/sep': () => const SepClaimsScreen(),
  '/reports': () => const ReportsScreen(),
};

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final refresh = _AuthRefresh(client);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final atAuth = loc == '/login' || loc == '/verify';
      if (client == null) return atAuth || loc == '/home' ? '/browse' : null; // preview mode: no auth
      final signedIn = client.auth.currentSession != null;
      if (!signedIn) return atAuth ? null : '/login';
      if (atAuth) return '/home'; // HomeRedirect sends admins to /admin, students to /browse
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/verify',
        builder: (context, state) => VerifyOtpScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeRedirect()),
      GoRoute(path: '/onboarding', builder: (context, state) => const ProfileScreen()),
      // Full-screen detail pages (pushed on top of the drawer shell).
      GoRoute(
        path: '/competition/:id',
        builder: (context, state) => CompetitionDetailScreen(competitionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/lobby/:id',
        builder: (context, state) => LobbyScreen(teamId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'recommend',
            builder: (context, state) => RecommendationsScreen(teamId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/team/:id',
        builder: (context, state) => TeamHubScreen(teamId: state.pathParameters['id']!),
        routes: [
          GoRoute(path: 'chat', builder: (context, state) => TeamChatPage(teamId: state.pathParameters['id']!)),
          GoRoute(path: 'calendar', builder: (context, state) => TeamCalendarPage(teamId: state.pathParameters['id']!)),
          GoRoute(path: 'rate', builder: (context, state) => RateClaimPage(teamId: state.pathParameters['id']!)),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          for (final item in allNavItems.where((i) => !i.pushed))
            GoRoute(
              path: item.path,
              builder: (context, state) => _builtScreens[item.path]!(),
            ),
        ],
      ),
    ],
  );
});
