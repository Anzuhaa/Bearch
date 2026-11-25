import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import '../reports/reports_screen.dart' show Json, reasonLabel, reportStatusPill;
import 'admin_dashboard_screen.dart';

const _open = ['appealed', 'info_requested', 'awaiting_appeal'];

final adminReportsProvider = FutureProvider.autoDispose<List<Json>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)!
      .from('reports')
      .select('id, code, reason, description, status, appeal_text, appeal_deadline, decision_note, created_at, '
          'reporter:profiles!reports_reporter_id_fkey(full_name), '
          'reported:profiles!reports_reported_id_fkey(full_name, reputation), '
          'teams(name, competitions(name)), report_evidence(side, label, external_url)')
      .order('created_at', ascending: false);
  // Open cases first (appealed = ready to decide).
  rows.sort((a, b) => _rank(a['status'] as String).compareTo(_rank(b['status'] as String)));
  return rows;
});

int _rank(String s) => _open.contains(s) ? _open.indexOf(s) : 9;

/// Figma 20 · Admin · Report & Appeal Review.
class ReportsReviewScreen extends ConsumerWidget {
  const ReportsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminReportsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AsyncView<List<Json>>(
          value: ref.watch(adminReportsProvider),
          onRetry: () => ref.invalidate(adminReportsProvider),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.gavel_rounded, title: 'No reports', message: 'Nothing to review.')
              : Column(children: [for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Case(r))]),
        ),
      ]),
    );
  }
}

class _Case extends ConsumerWidget {
  const _Case(this.r);

  final Json r;

  Future<void> _decide(BuildContext context, WidgetRef ref, String decision) async {
    final api = ref.read(bearchApiProvider);
    if (api == null) return;
    var falseReport = false;
    if (decision == 'dismissed') {
      falseReport = await confirmDialog(context,
          title: 'Mark as a false report?',
          message: 'A false report lowers the reporter\'s reputation. Choose Cancel to just dismiss.',
          confirmLabel: 'False report');
      if (!context.mounted) return;
    }
    final note = await promptText(context,
        title: switch (decision) { 'upheld' => 'Uphold report', 'dismissed' => 'Dismiss report', _ => 'Request more info' },
        label: 'Note to both students',
        confirmLabel: 'Confirm');
    if (note == null || !context.mounted) return;
    final ok = await runAction(context, () => api.adminDecideReport(r['id'] as String, decision, note: note, falseReport: falseReport),
        success: 'Decision sent to both students');
    if (ok) {
      ref.invalidate(adminReportsProvider);
      ref.invalidate(adminStatsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final status = r['status'] as String;
    final reported = r['reported'] as Json?;
    final team = r['teams'] as Json?;
    final evidence = (r['report_evidence'] as List? ?? const []).cast<Json>();
    Widget side(String title, String who, String? text, String sideKey) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$title · $who', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (text != null) Text('“$text”', style: t.bodyMedium),
            for (final e in evidence.where((e) => e['side'] == sideKey))
              Text('• ${e['label']}${e['external_url'] != null ? ' (${e['external_url']})' : ''}', style: t.bodySmall),
          ]),
        );
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Case #R-${(r['code'] as num).toString().padLeft(4, '0')} · ${reasonLabel(r['reason'] as String)}',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          reportStatusPill(status),
        ]),
        Text('${team?['name'] ?? ''} · ${(team?['competitions'] as Json?)?['name'] ?? ''}', style: t.bodySmall),
        side('REPORT', (r['reporter'] as Json?)?['full_name'] as String? ?? '—', r['description'] as String?, 'report'),
        side('APPEAL', reported?['full_name'] as String? ?? '—', r['appeal_text'] as String? ?? 'No appeal yet', 'appeal'),
        const SizedBox(height: 8),
        Text('Reported member reputation: ${reported?['reputation'] ?? 'not rated yet'}', style: t.bodySmall),
        if (r['decision_note'] != null) Text('Decision: ${r['decision_note']}', style: t.bodySmall),
        if (_open.contains(status)) ...[
          const SizedBox(height: 10),
          Text('Your decision notifies both students. Upheld reports reduce reputation.', style: t.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            TextButton(onPressed: () => _decide(context, ref, 'info_requested'), child: const Text('Request info')),
            OutlinedButton(onPressed: () => _decide(context, ref, 'dismissed'), child: const Text('Dismiss')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BearchColors.danger),
              onPressed: () => _decide(context, ref, 'upheld'),
              child: const Text('Uphold'),
            ),
          ]),
        ],
      ]),
    );
  }
}
