import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import '../lobbies/lobby_models.dart';
import 'admin_dashboard_screen.dart';

class PendingCompetition {
  const PendingCompetition(this.j, this.duplicateOfName);

  final Json j;
  final String? duplicateOfName;

  String get id => j['id'] as String;
  String get name => j['name'] as String;
  String get organizer => j['organizer'] as String;
  String get category => j['category'] as String;
  DateTime get deadline => DateTime.parse(j['registration_deadline'] as String);
  String get duplicateStatus => j['duplicate_status'] as String;
  String? get overrideReason => j['duplicate_override_reason'] as String?;
  String? get proofUrl => j['guidebook_url'] as String?;
  String get submitter => ((j['submitter'] as Json?)?['full_name'] as String?) ?? 'unknown';
  List<String> get files => [for (final f in (j['competition_files'] as List? ?? const [])) (f as Json)['file_name'] as String];
  List<String> get reasons => [
        for (final r in (j['duplicate_reasons'] as List? ?? const [])) '${(r as Json)['label']}: ${r['value']}',
      ];
}

final pendingCompetitionsProvider = FutureProvider.autoDispose<List<PendingCompetition>>((ref) async {
  final db = ref.watch(supabaseProvider)!;
  final rows = await db
      .from('competitions')
      .select('id, name, organizer, category, registration_deadline, guidebook_url, duplicate_status, '
          'duplicate_reasons, duplicate_override_reason, duplicate_of, '
          'submitter:profiles!competitions_submitted_by_fkey(full_name), competition_files(file_name)')
      .eq('status', 'pending')
      .order('submitted_at', ascending: true);
  final dupIds = {for (final r in rows) ?r['duplicate_of'] as String?};
  final names = dupIds.isEmpty
      ? <String, String>{}
      : {
          for (final r in await db.from('competitions').select('id, name').inFilter('id', dupIds.toList()))
            r['id'] as String: r['name'] as String,
        };
  return [for (final r in rows) PendingCompetition(r, names[r['duplicate_of']])];
});

/// Admin validation queue with "possible duplicate" badge.
class CompetitionQueueScreen extends ConsumerWidget {
  const CompetitionQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    return RefreshIndicator(
      onRefresh: () => ref.refresh(pendingCompetitionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AsyncView<List<PendingCompetition>>(
            value: ref.watch(pendingCompetitionsProvider),
            onRetry: () => ref.invalidate(pendingCompetitionsProvider),
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.inbox_rounded, title: 'Queue is empty', message: 'No competitions waiting for validation.')
                : Column(children: [for (final c in list) _QueueCard(c)]),
          ),
        ],
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard(this.c);

  final PendingCompetition c;

  Future<void> _decide(BuildContext context, WidgetRef ref, bool approve) async {
    final api = ref.read(bearchApiProvider);
    if (api == null) return;
    String? note;
    if (!approve) {
      note = await promptText(context, title: 'Reject ${c.name}?', label: 'Reason (sent to the student)', confirmLabel: 'Reject', minLength: 5);
      if (note == null) return;
    }
    if (!context.mounted) return;
    final ok = await runAction(context, () => api.adminReviewCompetition(c.id, approve: approve, note: note),
        success: approve ? '${c.name} is live' : 'Submission rejected');
    if (ok) {
      ref.invalidate(pendingCompetitionsProvider);
      ref.invalidate(adminStatsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final badge = switch (c.duplicateStatus) {
      'possible_duplicate' => Pill('Possible duplicate${c.duplicateOfName != null ? ' · ${c.duplicateOfName}' : ''}',
          color: BearchColors.warning, icon: Icons.content_copy_rounded),
      'check_failed' => const Pill('Needs manual check', color: Colors.blueGrey, icon: Icons.manage_search_rounded),
      _ => const Pill('No duplicate', color: BearchColors.success, icon: Icons.check_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          badge,
          const SizedBox(height: 8),
          Text(c.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text('${c.organizer} · ${c.category} · closes ${formatDate(c.deadline)}', style: t.bodySmall),
          Text('Submitted by ${c.submitter}', style: t.bodySmall),
          if (c.reasons.isNotEmpty) ...[const SizedBox(height: 8), for (final r in c.reasons) Text('• $r', style: t.bodySmall)],
          if (c.overrideReason != null) ...[
            const SizedBox(height: 8),
            Text('Student\'s reason: “${c.overrideReason}”', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          Text(
            'Proof: ${[...c.files, ?c.proofUrl].join(' · ').isEmpty ? 'none' : [...c.files, ?c.proofUrl].join(' · ')}',
            style: t.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => _decide(context, ref, false), child: const Text('Reject')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _decide(context, ref, true), child: const Text('Approve')),
          ]),
        ]),
      ),
    );
  }
}
