import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';

/// Full-screen page for one team (opened from the team hub). Loads the team,
/// shows "Title · Team name" and builds [builder] for it.
class TeamPage extends ConsumerWidget {
  const TeamPage({super.key, required this.teamId, required this.title, required this.builder});

  final String teamId;
  final String title;
  final Widget Function(TeamView team) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return PageScaffold(title: title, body: const NeedsBackend());
    final team = ref.watch(teamProvider(teamId));
    return PageScaffold(
      title: team.value == null ? title : '$title · ${team.value!.name}',
      body: AsyncView<TeamView>(
        value: team,
        loading: const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3)),
        onRetry: () => ref.invalidate(teamProvider(teamId)),
        data: builder,
      ),
    );
  }
}
