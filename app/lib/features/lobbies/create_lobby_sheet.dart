import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../data/bearch_api.dart';
import 'lobby_models.dart';
import 'skills_picker_sheet.dart';

/// "Open a lobby" sheet. Returns the new team id, or null if cancelled.
Future<String?> showCreateLobbySheet(BuildContext context, CompetitionDetail competition) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CreateLobbySheet(competition: competition),
  );
}

class _CreateLobbySheet extends ConsumerStatefulWidget {
  const _CreateLobbySheet({required this.competition});

  final CompetitionDetail competition;

  @override
  ConsumerState<_CreateLobbySheet> createState() => _CreateLobbySheetState();
}

class _CreateLobbySheetState extends ConsumerState<_CreateLobbySheet> {
  final _name = TextEditingController();
  final _pitch = TextEditingController();
  late int _max = widget.competition.teamMax;
  bool _approval = true;
  bool _crossMajor = true;
  Set<String> _skills = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pitch.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final api = ref.read(bearchApiProvider);
    if (api == null || _name.text.trim().length < 2) return;
    setState(() => _busy = true);
    String? id;
    final ok = await runAction(context, () async {
      id = await api.createTeam(
        competitionId: widget.competition.id,
        name: _name.text.trim(),
        pitch: _pitch.text.trim(),
        maxMembers: _max,
        approvalBased: _approval,
        crossMajorPreferred: _crossMajor,
        requiredSkills: [for (final s in _skills) (skillId: s, roleLabel: null)],
      );
    }, success: 'Lobby created. Broadcasting to UPH students.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = widget.competition;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Open a lobby', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(c.name, style: t.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Team name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pitch,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Pitch (what you build, who you need)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _max,
              decoration: const InputDecoration(labelText: 'Team size'),
              items: [
                for (var n = c.teamMin.clamp(1, c.teamMax); n <= c.teamMax; n++)
                  DropdownMenuItem(value: n, child: Text('$n members')),
              ],
              onChanged: (v) => setState(() => _max = v ?? _max),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Approval-based'),
              subtitle: const Text('You approve each join request'),
              value: _approval,
              onChanged: (v) => setState(() => _approval = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cross-major preferred'),
              value: _crossMajor,
              onChanged: (v) => setState(() => _crossMajor = v),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.psychology_alt_rounded),
              label: Text(_skills.isEmpty ? 'Skills needed (optional, AI can infer)' : '${_skills.length} skills needed'),
              onPressed: () async {
                final picked = await pickSkills(context, initial: _skills);
                if (picked != null) setState(() => _skills = picked);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _name.text.trim().length < 2 ? null : _create,
              child: Text(_busy ? 'Creating…' : 'Open lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
