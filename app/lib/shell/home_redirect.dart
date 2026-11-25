import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/async_ui.dart';
import '../core/glass.dart';
import '../core/session.dart';

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
          onRetry: () => ref.invalidate(profileProvider),
          data: (p) {
            // The router reacts to sign-in before Riverpod does, so the cached profile can
            // still be the previous user's (or null). Reload until it matches the session.
            final uid = ref.read(supabaseProvider)?.auth.currentUser?.id;
            if (uid != null && p?.id != uid) {
              Future.microtask(() => ref.invalidate(profileProvider));
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go(p?.role == UserRole.admin ? '/admin' : '/browse');
              });
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }
}
