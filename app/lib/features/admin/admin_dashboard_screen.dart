import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(bearchApiProvider)!.adminDashboardStats(),
);

/// Figma 17 · Admin · Student Affairs Dashboard.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminStatsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Good to see you, Student Affairs', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text('Semester overview (last 6 months)', style: t.bodySmall),
          const SizedBox(height: 12),
          AsyncView<Map<String, dynamic>>(
            loading: const SkeletonGrid(),
            value: ref.watch(adminStatsProvider),
            onRetry: () => ref.invalidate(adminStatsProvider),
            data: (s) {
              String num(Object? v, [String suffix = '']) => v == null ? '—' : '$v$suffix';
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    _Metric('Avg. time-to-team', num(s['avg_time_to_team_days'], ' days'), 'Target < 3 days'),
                    _Metric('Cross-major teams', num(s['cross_major_pct'], '%'), 'Target ≥ 35%'),
                    _Metric('Member retention', num(s['retention_pct'], '%'), 'Target ≥ 80%'),
                    _Metric('SEP credited', num(s['sep_credited']), 'across ${s['sep_students'] ?? 0} students'),
                  ],
                ),
                const SectionLabel('Needs your attention'),
                _QueueTile(Icons.fact_check_outlined, 'Competition validation', s['pending_competitions'], '/admin/competitions'),
                _QueueTile(Icons.gavel_rounded, 'Reports & appeals', s['open_reports'], '/admin/reports'),
                _QueueTile(Icons.verified_outlined, 'SEP claims to verify', s['sep_to_verify'], '/admin/sep'),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.caption);

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: t.bodySmall),
        Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: BearchColors.accent)),
        Text(caption, style: t.labelSmall),
      ]),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile(this.icon, this.label, this.count, this.path);

  final IconData icon;
  final String label;
  final Object? count;
  final String path;

  @override
  Widget build(BuildContext context) {
    final n = (count as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => context.go(path),
        child: Row(children: [
          Icon(icon, color: BearchColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          Pill(n == 0 ? 'All clear' : '$n pending', color: n == 0 ? BearchColors.success : BearchColors.warning),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}
