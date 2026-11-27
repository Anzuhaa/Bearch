import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/choice.dart';
import '../../core/skeleton.dart';
import '../../data/bearch_api.dart';
import 'lobby_models.dart';
import 'lobby_providers.dart';

/// Leader changes max members while the lobby is open. Range: current members
/// (and the competition minimum) up to the competition maximum; the DB also
/// counts pending invites and refuses anything below them.
Future<bool> showTeamSizeSheet(BuildContext context, TeamView team) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TeamSizeSheet(team: team),
    ) ??
    false;

class _TeamSizeSheet extends ConsumerStatefulWidget {
  const _TeamSizeSheet({required this.team});

  final TeamView team;

  @override
  ConsumerState<_TeamSizeSheet> createState() => _TeamSizeSheetState();
}

class _TeamSizeSheetState extends ConsumerState<_TeamSizeSheet> {
  late int _max = widget.team.maxMembers;
  bool _busy = false;

  Future<void> _save() async {
    final api = ref.read(bearchApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => api.setTeamSize(widget.team.id, _max), success: 'Team size set to $_max');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final team = widget.team;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: AsyncView<CompetitionDetail>(
          loading: const SkeletonPulse(child: SkeletonBox(height: 120, radius: 14)),
          value: ref.watch(competitionDetailProvider(team.competitionId)),
          data: (c) {
            final low = [c.teamMin, team.members.length, 1].reduce((a, b) => a > b ? a : b);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Team size', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${team.members.length} joined · ${c.name} allows ${c.teamMin}–${c.teamMax}', style: t.bodySmall),
              const SizedBox(height: 14),
              ChoiceGroup<int>(
                label: 'Max members',
                options: [for (var n = low; n <= c.teamMax; n++) (value: n, label: '$n')],
                value: _max,
                onChanged: (v) => setState(() => _max = v),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy || _max == team.maxMembers ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save'),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
