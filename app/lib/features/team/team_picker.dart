import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';

/// Which of my teams the "My Team" screens (chat, calendar, rate) show.
class SelectedTeamNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final selectedTeamIdProvider = NotifierProvider<SelectedTeamNotifier, String?>(SelectedTeamNotifier.new);

/// Wraps a team screen: loads my teams, shows a picker when I have several,
/// and builds [builder] for the chosen one. Locked teams are preferred by default.
class TeamScope extends ConsumerWidget {
  const TeamScope({super.key, required this.builder, this.filter, this.emptyMessage});

  final Widget Function(TeamView team) builder;
  final bool Function(TeamView team)? filter;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    final selected = ref.watch(selectedTeamIdProvider);
    return AsyncView<List<TeamView>>(
      value: ref.watch(myTeamsProvider),
      onRetry: () => ref.invalidate(myTeamsProvider),
      data: (all) {
        final teams = filter == null ? all : all.where(filter!).toList();
        if (teams.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: EmptyState(
              icon: Icons.groups_rounded,
              title: 'No team here yet',
              message: emptyMessage ?? 'Join or open a lobby first.',
              action: FilledButton(onPressed: () => context.go('/browse'), child: const Text('Browse competitions')),
            ),
          );
        }
        final team = teams.where((t) => t.id == selected).firstOrNull ??
            teams.where((t) => t.isLocked).firstOrNull ??
            teams.first;
        return Column(children: [
          if (teams.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: DropdownButtonFormField<String>(
                initialValue: team.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Team'),
                items: [
                  for (final t in teams)
                    DropdownMenuItem(value: t.id, child: Text('${t.name} · ${t.competitionName}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) => id == null ? null : ref.read(selectedTeamIdProvider.notifier).select(id),
              ),
            ),
          Expanded(child: builder(team)),
        ]);
      },
    );
  }
}
