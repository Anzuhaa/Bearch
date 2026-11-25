import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/async_ui.dart';
import '../../core/choice.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../data/bearch_api.dart';
import 'competitions_data.dart';
import 'submit_widgets.dart';

const _levels = {'campus': 'Campus', 'regional': 'Regional', 'national': 'National', 'international': 'International'};

/// Figma 15 · Submit Competition (+ AI duplicate check) and 16 · Pending validation.
class SubmitCompetitionScreen extends ConsumerStatefulWidget {
  const SubmitCompetitionScreen({super.key});

  @override
  ConsumerState<SubmitCompetitionScreen> createState() => _SubmitState();
}

class _SubmitState extends ConsumerState<SubmitCompetitionScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _organizer = TextEditingController();
  final _description = TextEditingController();
  final _officialUrl = TextEditingController();
  final _proofUrl = TextEditingController();
  final _override = TextEditingController();
  String _category = 'technology';
  String _level = 'campus';
  DateTime? _deadline;
  int _min = 3, _max = 5; // most common team size
  PlatformFile? _file;
  bool _fileUploaded = false;
  String? _draftId;
  DuplicateCheck? _check;
  bool _busy = false;
  String? _submittedName;

  @override
  void dispose() {
    for (final c in [_name, _organizer, _description, _officialUrl, _proofUrl, _override]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (_check != null) setState(() => _check = null); // details changed -> re-check
  }

  Map<String, Object?> get _fields => {
        'name': _name.text.trim(),
        'organizer': _organizer.text.trim(),
        'category': _category,
        'level': _level,
        'description': _description.text.trim(),
        'official_url': _officialUrl.text.trim().isEmpty ? null : _officialUrl.text.trim(),
        'guidebook_url': _proofUrl.text.trim().isEmpty ? null : _proofUrl.text.trim(),
        'registration_deadline': DateFormat('yyyy-MM-dd').format(_deadline!),
        'team_min': _min,
        'team_max': _max,
      };

  Future<void> _runCheck(BearchApi api) async {
    if (!_form.currentState!.validate() || _deadline == null) return;
    if (_file == null && _proofUrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attach the official poster/guidebook or paste its link as proof.')));
      return;
    }
    setState(() => _busy = true);
    await runAction(context, () async {
      _draftId = await api.saveCompetitionDraft(_draftId, _fields);
      if (_file != null && !_fileUploaded) {
        await api.uploadCompetitionProof(_draftId!, _file!.name, await _file!.readAsBytes());
        _fileUploaded = true;
      }
      try {
        _check = await api.checkDuplicate(_draftId!);
      } catch (_) {
        _check = const DuplicateCheck(status: 'check_failed', message: 'Duplicate check unavailable right now.');
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit(BearchApi api) async {
    setState(() => _busy = true);
    final ok = await runAction(context, () => api.submitCompetition(_draftId!, overrideReason: _override.text.trim()));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _submittedName = _name.text.trim();
    });
    ref.invalidate(mySubmissionsProvider);
  }

  void _reset() => setState(() {
        _form.currentState?.reset();
        for (final c in [_name, _organizer, _description, _officialUrl, _proofUrl, _override]) {
          c.clear();
        }
        _deadline = null;
        _file = null;
        _fileUploaded = false;
        _draftId = null;
        _check = null;
        _submittedName = null;
      });

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(bearchApiProvider);
    if (ref.watch(supabaseProvider) == null || api == null) return const NeedsBackend();
    final t = Theme.of(context).textTheme;
    final needsReason = _check?.needsOverrideReason ?? false;
    String? req(String? v) => (v ?? '').trim().length < 2 ? 'Required' : null;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      Text('Not on Bearch yet? Submit it. Student Affairs validates it before it goes live.', style: t.bodySmall),
      const SizedBox(height: 12),
      if (_submittedName != null)
        SubmittedCard(name: _submittedName!, onAnother: _reset)
      else
        GlassCard(
          child: Form(
            key: _form,
            onChanged: _edited,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(controller: _name, validator: req, decoration: const InputDecoration(labelText: 'Competition name')),
              const SizedBox(height: 10),
              TextFormField(controller: _organizer, validator: req, decoration: const InputDecoration(labelText: 'Organizer')),
              const SizedBox(height: 10),
              ChoiceGroup<String>(
                label: 'Category',
                options: [
                  for (final e in competitionCategories.entries.where((e) => e.key != 'all')) (value: e.key, label: e.value),
                ],
                value: _category,
                onChanged: (v) => setState(() {
                  _category = v;
                  _check = null; // category is part of the duplicate check
                }),
              ),
              const SizedBox(height: 12),
              ChoiceGroup<String>(
                label: 'Level',
                options: [for (final e in _levels.entries) (value: e.key, label: e.value)],
                value: _level,
                onChanged: (v) => setState(() => _level = v),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(_deadline == null ? 'Registration deadline' : 'Deadline: ${formatDate(_deadline!)}'),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 2), initialDate: now.add(const Duration(days: 14)));
                  if (d != null) {
                    setState(() {
                      _deadline = d;
                      _check = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TeamSizePicker(
                min: _min,
                max: _max,
                onChanged: (lo, hi) => setState(() {
                  _min = lo;
                  _max = hi;
                }),
              ),
              const SizedBox(height: 10),
              TextFormField(controller: _officialUrl, decoration: const InputDecoration(labelText: 'Official link (optional)')),
              const SizedBox(height: 10),
              TextFormField(controller: _description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Short description')),
              const SizedBox(height: 10),
              Text('Proof of legitimacy (poster or guidebook)', style: t.labelLarge),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_file?.name ?? 'Attach PDF / image', overflow: TextOverflow.ellipsis),
                onPressed: () async {
                  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp']);
                  if (picked.isNotEmpty) {
                    setState(() {
                      _file = picked.first;
                      _fileUploaded = false;
                    });
                  }
                },
              ),
              const SizedBox(height: 6),
              TextFormField(controller: _proofUrl, decoration: const InputDecoration(labelText: 'or paste a guidebook link')),
              const SizedBox(height: 6),
              Text('AI checks organizer, category, timeline & name against existing listings.', style: t.bodySmall),
            ]),
          ),
        ),
      if (_check != null && _submittedName == null) ...[
        const SizedBox(height: 12),
        DuplicateResultCard(check: _check!, overrideReason: _override),
      ],
      if (_submittedName == null) ...[
        const SizedBox(height: 12),
        if (_check == null)
          FilledButton(onPressed: _busy ? null : () => _runCheck(api), child: Text(_busy ? 'Checking…' : 'Check for duplicates'))
        else
          ListenableBuilder(
            listenable: _override,
            builder: (context, _) => FilledButton(
              onPressed: _busy || (needsReason && _override.text.trim().length < 5) ? null : () => _submit(api),
              child: Text(needsReason ? 'Submit with reason' : 'Submit for validation'),
            ),
          ),
      ],
      const MySubmissions(),
    ]);
  }
}
