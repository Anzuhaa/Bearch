import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../lobbies/lobby_models.dart';
import 'availability_sheet.dart';
import 'team_page.dart';

typedef HeatCell = ({int weekday, int hour, int free, int members});

final heatmapProvider = FutureProvider.autoDispose.family<List<HeatCell>, String>((ref, teamId) async {
  final rows = await ref.watch(supabaseProvider)!.rpc('team_availability_heatmap', params: {'p_team': teamId}) as List;
  return [
    for (final r in rows.cast<Map<String, dynamic>>())
      (
        weekday: (r['weekday'] as num).toInt(),
        hour: int.parse((r['slot_start'] as String).split(':').first),
        free: (r['free_count'] as num).toInt(),
        members: (r['member_count'] as num).toInt(),
      ),
  ];
});

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Figma 10 · Team Calendar · Shared Availability.
class TeamCalendarPage extends StatelessWidget {
  const TeamCalendarPage({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context) => TeamPage(teamId: teamId, title: 'Calendar', builder: (team) => _Calendar(team: team));
}

class _Calendar extends ConsumerWidget {
  const _Calendar({required this.team});

  final TeamView team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(heatmapProvider(team.id).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text('${team.name} · everyone\'s free slots in one heatmap (WIB)', style: t.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_calendar_rounded),
          label: const Text('Edit my availability'),
          onPressed: () async {
            await showAvailabilitySheet(context);
            ref.invalidate(heatmapProvider(team.id));
          },
        ),
        const SizedBox(height: 12),
        AsyncView<List<HeatCell>>(
          loading: const SkeletonPulse(child: SkeletonBox(height: 380, radius: 20)),
          value: ref.watch(heatmapProvider(team.id)),
          onRetry: () => ref.invalidate(heatmapProvider(team.id)),
          data: (cells) {
            if (cells.isEmpty) return const SizedBox.shrink();
            final members = cells.first.members;
            final best = [...cells.where((c) => c.free > 0)]..sort((a, b) => b.free.compareTo(a.free));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassCard(padding: const EdgeInsets.all(10), child: _Heatmap(cells: cells, members: members)),
              const SectionLabel('Best slots this week'),
              if (best.isEmpty)
                Text('No overlapping free time yet. Ask everyone to add their availability.', style: t.bodySmall),
              for (final c in best.take(3))
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.event_available_rounded, color: BearchColors.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_days[c.weekday - 1]} · ${c.hour.toString().padLeft(2, '0')}:00 – ${(c.hour + 1).toString().padLeft(2, '0')}:00')),
                    Pill('${c.free}/$members free', color: c.free == members ? BearchColors.success : BearchColors.warning),
                  ]),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.cells, required this.members});

  final List<HeatCell> cells;
  final int members;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hours = {for (final c in cells) c.hour}.toList()..sort();
    final byKey = {for (final c in cells) '${c.weekday}-${c.hour}': c.free};
    return Column(children: [
      Row(children: [
        const SizedBox(width: 40),
        for (final d in _days) Expanded(child: Center(child: Text(d, style: t.labelSmall))),
      ]),
      for (final h in hours)
        Row(children: [
          SizedBox(width: 40, child: Text('${h.toString().padLeft(2, '0')}:00', style: t.labelSmall)),
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Container(
                height: 18,
                margin: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: BearchColors.accent.withValues(
                    alpha: members == 0 ? 0.05 : 0.08 + 0.85 * (byKey['$d-$h'] ?? 0) / members,
                  ),
                ),
              ),
            ),
        ]),
      const SizedBox(height: 6),
      Text('Stronger blue = more teammates free · $members members', style: t.labelSmall),
    ]);
  }
}
