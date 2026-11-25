import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/session.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/verify_otp_screen.dart';
import 'features/competitions/browse_screen.dart';
import 'features/placeholder_screen.dart';
import 'shell/app_shell.dart';
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
          for (final item in allNavItems.where((i) => i.path != '/browse'))
            GoRoute(path: item.path, builder: (context, state) => PlaceholderScreen(item: item)),
        ],
      ),
    ],
  );
});
