import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import 'reports_screen.dart' show Json, reasonLabel, reportStatusPill;

/// Figma 19 · a report about me (reporter hidden) + appeal form.
class AppealCard extends ConsumerStatefulWidget {
  const AppealCard({super.key, required this.report, required this.onChanged});

  final Json report;
  final VoidCallback onChanged;

  @override
  ConsumerState<AppealCard> createState() => _AppealCardState();
}

class _AppealCardState extends ConsumerState<AppealCard> {
  final _text = TextEditingController();
  final _evidence = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _submit(BearchApi api) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => api.submitAppeal(
        widget.report['id'] as String,
        _text.text.trim(),
        evidence: [if (_evidence.text.trim().isNotEmpty) {'label': _evidence.text.trim()}],
      ),
      success: 'Appeal submitted. Student Affairs reviews within 3 working days.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.report;
    final api = ref.watch(bearchApiProvider);
    final status = r['status'] as String;
    final deadline = DateTime.parse(r['appeal_deadline'] as String).toLocal();
    final daysLeft = deadline.difference(DateTime.now()).inDays;
    final canAppeal = status == 'info_requested' || (status == 'awaiting_appeal' && deadline.isAfter(DateTime.now()));
    final evidence = (r['evidence'] as List? ?? const []).cast<Json>();

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(reasonLabel(r['reason'] as String), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          reportStatusPill(status),
        ]),
        Text('${r['team_name']} · ${r['competition_name']}', style: t.bodySmall),
        if (status == 'awaiting_appeal') Text('Appeal window · $daysLeft days left', style: t.bodySmall?.copyWith(color: BearchColors.warning)),
        const SizedBox(height: 8),
        Text('Reporter\'s statement', style: t.labelSmall),
        Text('“${r['description']}”', style: t.bodyMedium),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Evidence', style: t.labelSmall),
          for (final e in evidence)
            Text('• ${e['label']}${e['side'] == 'appeal' ? ' (your appeal)' : ''}', style: t.bodySmall),
        ],
        if (r['appeal_text'] != null) ...[
          const SizedBox(height: 8),
          Text('Your appeal', style: t.labelSmall),
          Text('“${r['appeal_text']}”', style: t.bodyMedium),
        ],
        if (r['decision_note'] != null) ...[const SizedBox(height: 8), Text('Decision: ${r['decision_note']}', style: t.bodySmall)],
        if (canAppeal) ...[
          const SizedBox(height: 10),
          Text('No reputation impact until Student Affairs decides.', style: t.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Your side of the story', helperText: 'At least 20 characters'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _evidence, decoration: const InputDecoration(labelText: 'Counter-evidence (optional)')),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: api == null || _busy || _text.text.trim().length < 20 ? null : () => _submit(api),
            child: const Text('Submit appeal'),
          ),
        ],
      ]),
    );
  }
}
