import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';

typedef Submission = ({String id, String name, String status, String duplicateStatus, String? reviewNote});

final mySubmissionsProvider = FutureProvider.autoDispose<List<Submission>>((ref) async {
  final db = ref.watch(supabaseProvider)!;
  final rows = await db
      .from('competitions')
      .select('id, name, status, duplicate_status, review_note')
      .eq('submitted_by', db.auth.currentUser!.id)
      .order('created_at', ascending: false);
  return [
    for (final r in rows)
      (
        id: r['id'] as String,
        name: r['name'] as String,
        status: r['status'] as String,
        duplicateStatus: r['duplicate_status'] as String,
        reviewNote: r['review_note'] as String?,
      ),
  ];
});

/// Result of the AI duplicate check (Figma 15, right panel).
class DuplicateResultCard extends StatelessWidget {
  const DuplicateResultCard({super.key, required this.check, required this.overrideReason});

  final DuplicateCheck check;
  final TextEditingController overrideReason;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (Color color, IconData icon, String title) = switch (check.status) {
      'clear' => (BearchColors.success, Icons.check_circle_rounded, 'No duplicate found'),
      'possible_duplicate' => (BearchColors.warning, Icons.content_copy_rounded, 'Possible duplicate found'),
      _ => (Colors.blueGrey, Icons.manage_search_rounded, 'AI check unavailable'),
    };
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color))),
        ]),
        if (check.duplicateOfName != null) ...[
          const SizedBox(height: 8),
          Text(check.duplicateOfName!, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
        if (check.reasons.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final r in check.reasons.where((r) => r.label != 'AI'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 90, child: Text(r.label, style: t.bodySmall)),
                Expanded(child: Text(r.value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
              ]),
            ),
        ],
        if (check.message != null) ...[const SizedBox(height: 8), Text(check.message!, style: t.bodySmall)],
        if (check.status == 'check_failed')
          Text('You can still submit. Student Affairs will review it manually.', style: t.bodySmall),
        if (check.needsOverrideReason) ...[
          const SizedBox(height: 12),
          TextField(
            controller: overrideReason,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason to submit anyway',
              hintText: 'e.g. This is the 2026 season with a new timeline and theme.',
            ),
          ),
          const SizedBox(height: 6),
          Text('Student Affairs will see it flagged as "possible duplicate".', style: t.bodySmall),
        ],
      ]),
    );
  }
}

/// Figma 16 · Submitted · Pending validation.
class SubmittedCard extends StatelessWidget {
  const SubmittedCard({super.key, required this.name, required this.onAnother});

  final String name;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Icon(Icons.task_alt_rounded, size: 44, color: BearchColors.success),
        const SizedBox(height: 10),
        Text('Submitted for validation', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('$name is now in the Student Affairs queue. You\'ll be notified once it\'s reviewed.',
            textAlign: TextAlign.center, style: t.bodyMedium),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onAnother, child: const Text('Submit another')),
      ]),
    );
  }
}

class MySubmissions extends ConsumerWidget {
  const MySubmissions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('My submissions'),
      AsyncView<List<Submission>>(
        value: ref.watch(mySubmissionsProvider),
        onRetry: () => ref.invalidate(mySubmissionsProvider),
        data: (list) => list.isEmpty
            ? Text('Nothing submitted yet.', style: t.bodySmall)
            : GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [
                  for (final s in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      subtitle: s.reviewNote == null ? null : Text(s.reviewNote!),
                      trailing: Pill(
                        switch (s.status) { 'pending' => 'Under review', 'approved' => 'Live', 'rejected' => 'Rejected', _ => 'Draft' },
                        color: switch (s.status) {
                          'approved' => BearchColors.success,
                          'rejected' => BearchColors.danger,
                          'pending' => BearchColors.warning,
                          _ => Colors.blueGrey,
                        },
                      ),
                    ),
                ]),
              ),
      ),
    ]);
  }
}
