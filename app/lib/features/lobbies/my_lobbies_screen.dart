import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import 'lobby_models.dart';
import 'lobby_providers.dart';
import 'lobby_widgets.dart';

/// Drawer: My Lobbies. Lists every lobby I lead or joined.
class MyLobbiesScreen extends ConsumerWidget {
  const MyLobbiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    final me = ref.watch(supabaseProvider)?.auth.currentUser?.id;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myTeamsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AsyncView<List<TeamView>>(
            value: ref.watch(myTeamsProvider),
            onRetry: () => ref.invalidate(myTeamsProvider),
            data: (teams) => teams.isEmpty
                ? EmptyState(
                    icon: Icons.groups_rounded,
                    title: 'No lobbies yet',
                    message: 'Open a lobby or request to join one from a competition.',
                    action: FilledButton(onPressed: () => context.go('/browse'), child: const Text('Browse competitions')),
                  )
                : Column(children: [
                    for (final team in teams) ...[
                      TeamCard(
                        team: team,
                        subtitle: '${team.competitionName} · ${team.leaderId == me ? 'You lead' : 'Member'}',
                        onTap: () => context.push('/lobby/${team.id}'),
                        action: const Icon(Icons.chevron_right_rounded),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ]),
          ),
        ],
      ),
    );
  }
}
