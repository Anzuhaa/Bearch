import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import 'browse_filter_sheet.dart';
import 'competitions_data.dart';
import 'lobby_buzz.dart';

/// Figma 04 · Browse Competitions (mobile).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowseFilter _filter = (category: 'all', sort: 'deadline');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final competitions = ref.watch(competitionsProvider);
    final profile = ref.watch(profileProvider).value;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(competitionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Verified by UPH Student Affairs', style: t.bodySmall),
          const SizedBox(height: 12),
          if (profile != null && !profile.onboarded) ...[
            GlassCard(
              onTap: () => context.push('/onboarding'),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: BearchColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Finish your skill profile so teams can find you',
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _FilterBar(
            filter: _filter,
            onTap: () async {
              final all = competitions.value ?? const <CompetitionSummary>[];
              final counts = <String, int>{'all': all.length};
              for (final c in all) {
                counts[c.category] = (counts[c.category] ?? 0) + 1;
              }
              final f = await showBrowseFilterSheet(context, _filter, counts);
              if (f != null) setState(() => _filter = f);
            },
            onClear: () => setState(() => _filter = (category: 'all', sort: _filter.sort)),
          ),
          const SizedBox(height: 12),
          ...competitions.when(
            loading: () => [const SkeletonList(count: 4, lines: 1, chips: true)],
            error: (e, _) => [
              EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn\'t load competitions',
                message: '$e',
                action: OutlinedButton(onPressed: () => ref.invalidate(competitionsProvider), child: const Text('Retry')),
              ),
            ],
            data: (list) {
              final shown = [
                for (final c in list)
                  if (_filter.category == 'all' || c.category == _filter.category) c,
              ]..sort(switch (_filter.sort) {
                  'lobbies' => (a, b) => b.lobbyCount.compareTo(a.lobbyCount),
                  'name' => (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  _ => (a, b) => a.registrationDeadline.compareTo(b.registrationDeadline),
                });
              if (shown.isEmpty) {
                return [
                  EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No open competitions here yet',
                    message: 'Know one that\'s missing? Submit it for validation.',
                    action: FilledButton(onPressed: () => context.go('/submit'), child: const Text('Submit a competition')),
                  ),
                ];
              }
              return [
                for (final (i, c) in shown.indexed) ...[Entrance(index: i, child: _CompetitionCard(c)), const SizedBox(height: 12)],
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard(this.c);

  final CompetitionSummary c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final deadline = DateFormat('d MMM yyyy').format(c.registrationDeadline);
    final size = c.teamMin == c.teamMax ? '${c.teamMax} members' : '${c.teamMin}–${c.teamMax} members';
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

    return GlassCard(
      onTap: () => context.push('/competition/${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Pill(cap(c.level), color: BearchColors.purple),
              const Pill('Verified', color: BearchColors.success, icon: Icons.verified_rounded),
              Pill(cap(c.category), color: BearchColors.accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(c.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(c.organizer, style: t.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Meta(Icons.event_rounded, 'Reg. closes $deadline'),
              _Meta(Icons.group_outlined, size),
            ],
          ),
          const SizedBox(height: 12),
          LobbyBuzz(count: c.lobbyCount),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 15, color: style?.color), const SizedBox(width: 4), Text(label, style: style)],
    );
  }
}

/// One tappable summary of the active filter + sort (opens the sheet).
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onTap, required this.onClear});

  final BrowseFilter filter;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final filtered = filter.category != 'all';
    return Row(children: [
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: InputDecorator(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.tune_rounded),
              suffixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            child: Text(
              '${competitionCategories[filter.category]} · ${browseSorts[filter.sort]}',
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      if (filtered) IconButton(tooltip: 'Clear category', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
    ]);
  }
}
