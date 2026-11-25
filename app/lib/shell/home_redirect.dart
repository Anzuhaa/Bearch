import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/async_ui.dart';
import '../core/glass.dart';
import '../core/local_cache.dart';
import '../core/session.dart';
import '../core/skeleton.dart';
import '../core/theme.dart';

/// Landing after sign-in: admins go to the dashboard, students to Browse.
class HomeRedirect extends ConsumerWidget {
  const HomeRedirect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AsyncView<Profile?>(
          value: profile,
          loading: const _Splash(),
          onRetry: () => ref.invalidate(profileProvider),
          data: (p) {
            // The router reacts to sign-in before Riverpod does, so the cached profile can
            // still be the previous user's (or null). Reload until it matches the session.
            final uid = ref.read(supabaseProvider)?.auth.currentUser?.id;
            if (uid != null && p?.id != uid) {
              Future.microtask(() => ref.invalidate(profileProvider));
            } else {
              if (uid != null && p != null) LocalCache.setRole(uid, p.role.name);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go(p?.role == UserRole.admin ? '/admin' : '/browse');
              });
            }
            return const _Splash();
          },
        ),
      ),
    );
  }
}

/// Brand mark while the very first sign-in resolves (returning users skip this).
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Center(
        child: SkeletonPulse(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: BearchColors.accent, borderRadius: BorderRadius.circular(20)),
            child: const Text('B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 34)),
          ),
        ),
      );
}
