import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/choice.dart';
import '../../core/session.dart';
import '../../data/bearch_api.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';
import 'reports_screen.dart' show reasonLabel;

const _reasons = ['non_contribution', 'missed_deadlines', 'no_show', 'disrespectful', 'other'];

/// Figma 18 · Report a member. Returns true when filed.
Future<bool?> showReportSheet(BuildContext context, {String? teamId}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportSheet(initialTeamId: teamId),
    );

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({this.initialTeamId});

  final String? initialTeamId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  TeamView? _team;
  String? _member;
  String _reason = 'non_contribution';
  final _facts = TextEditingController();
  final _evidence = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_facts, _evidence, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _team != null && _member != null && _facts.text.trim().length >= 20 && _evidence.text.trim().isNotEmpty;

  Future<void> _submit(BearchApi api) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => api.fileReport(
        teamId: _team!.id,
        reportedId: _member!,
        reason: _reason,
        description: _facts.text.trim(),
        evidence: [
          {'label': _evidence.text.trim(), if (_link.text.trim().isNotEmpty) 'external_url': _link.text.trim()},
        ],
      ),
      success: 'Report filed. The member has 7 days to appeal.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final api = ref.watch(bearchApiProvider);
    final me = ref.watch(supabaseProvider)?.auth.currentUser?.id;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: AsyncView<List<TeamView>>(
          value: ref.watch(myTeamsProvider),
          data: (teams) {
            // Opened from a team hub: preselect that team.
            _team ??= teams.where((tm) => tm.id == widget.initialTeamId).firstOrNull ?? (teams.length == 1 ? teams.first : null);
            final others = _team?.members.where((m) => m.profileId != me).toList() ?? const <MemberView>[];
            if (_member == null && others.length == 1) _member = others.first.profileId;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Report a member', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('Reports must be backed by concrete facts. False reports lower your own reputation.', style: t.bodySmall),
            const SizedBox(height: 12),
            ChoiceGroup<String>(
              label: 'Team',
              options: [for (final tm in teams) (value: tm.id, label: tm.name)],
              value: _team?.id,
              onChanged: (id) => setState(() {
                _team = teams.firstWhere((tm) => tm.id == id);
                _member = null;
              }),
            ),
            if (_team != null) ...[
              const SizedBox(height: 12),
              ChoiceGroup<String>(
                label: 'Member',
                options: [for (final m in others) (value: m.profileId, label: m.fullName)],
                value: _member,
                onChanged: (v) => setState(() => _member = v),
              ),
            ],
            const SizedBox(height: 10),
            ChoiceGroup<String>(
              label: 'Reason',
              options: [for (final r in _reasons) (value: r, label: reasonLabel(r))],
              value: _reason,
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _facts,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'What happened? (facts, dates)', helperText: 'At least 20 characters'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _evidence,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Evidence (required)', hintText: 'e.g. Team chat excerpts 2–12 Nov'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _link, decoration: const InputDecoration(labelText: 'Evidence link (optional)')),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: api == null || !_valid || _busy ? null : () => _submit(api),
              child: Text(_busy ? 'Submitting…' : 'Submit report'),
            ),
          ]);
          },
        ),
      ),
    );
  }
}
