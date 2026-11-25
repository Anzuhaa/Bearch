import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'appeal_card.dart';
import 'report_form_sheet.dart';

typedef Json = Map<String, dynamic>;

final filedReportsProvider = FutureProvider.autoDispose<List<Json>>((ref) async {
  final db = ref.watch(supabaseProvider)!;
  return await db
      .from('reports')
      .select('id, code, reason, description, status, appeal_deadline, decision_note, created_at, '
          'reported:profiles!reports_reported_id_fkey(full_name), teams(name, competitions(name))')
      .eq('reporter_id', db.auth.currentUser!.id)
      .order('created_at', ascending: false);
});

final reportsAboutMeProvider = FutureProvider.autoDispose<List<Json>>(
  (ref) async => ((await ref.watch(supabaseProvider)!.rpc('reports_about_me')) as List).cast<Json>(),
);

String reasonLabel(String r) => switch (r) {
      'non_contribution' => 'Non-contribution',
      'missed_deadlines' => 'Missed deadlines',
      'no_show' => 'No-show at meetings',
      'disrespectful' => 'Disrespectful conduct',
      _ => 'Other',
    };

Pill reportStatusPill(String s) => switch (s) {
      'awaiting_appeal' => const Pill('Awaiting appeal', color: BearchColors.warning),
      'appealed' => const Pill('Appeal submitted', color: BearchColors.accent),
      'info_requested' => const Pill('Info requested', color: BearchColors.warning),
      'upheld' => const Pill('Upheld', color: BearchColors.danger),
      _ => const Pill('Dismissed', color: BearchColors.success),
    };

/// Figma 18/19 · Report a member · Reports & Appeals.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    final t = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(child: Text('Reports need concrete facts. The reported member can appeal within 7 days.', style: t.bodySmall)),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report'),
              onPressed: () async {
                if (await showReportSheet(context) == true) ref.invalidate(filedReportsProvider);
              },
            ),
          ]),
        ),
        const TabBar(tabs: [Tab(text: 'Filed by me'), Tab(text: 'About me')]),
        Expanded(
          child: TabBarView(children: [
            _List(
              value: ref.watch(filedReportsProvider),
              empty: 'You haven\'t filed any reports.',
              item: (r) => _FiledCard(r),
            ),
            _List(
              value: ref.watch(reportsAboutMeProvider),
              empty: 'No reports about you. Keep it up!',
              item: (r) => AppealCard(report: r, onChanged: () => ref.invalidate(reportsAboutMeProvider)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.value, required this.empty, required this.item});

  final AsyncValue<List<Json>> value;
  final String empty;
  final Widget Function(Json r) item;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AsyncView<List<Json>>(
            value: value,
            data: (list) => list.isEmpty
                ? Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(empty)))
                : Column(children: [for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: item(r))]),
          ),
        ],
      );
}

class _FiledCard extends StatelessWidget {
  const _FiledCard(this.r);

  final Json r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final team = r['teams'] as Json?;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Your report on ${(r['reported'] as Json?)?['full_name'] ?? '—'}',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          reportStatusPill(r['status'] as String),
        ]),
        Text('${team?['name'] ?? ''} · ${(team?['competitions'] as Json?)?['name'] ?? ''}', style: t.bodySmall),
        const SizedBox(height: 6),
        Text('${reasonLabel(r['reason'] as String)} · #R-${(r['code'] as num).toString().padLeft(4, '0')}', style: t.bodyMedium),
        if (r['decision_note'] != null) Text('Decision: ${r['decision_note']}', style: t.bodySmall),
      ]),
    );
  }
}
