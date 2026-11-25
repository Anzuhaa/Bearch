import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/choice.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';
import '../lobbies/skills_picker_sheet.dart';
import '../team/availability_sheet.dart';
import 'major_picker_sheet.dart';

typedef ProfileForm = ({String name, String? majorId, int? batch, Map<String, int> skills});

final majorsProvider = FutureProvider<List<Major>>((ref) async {
  final rows = await ref.watch(supabaseProvider)!.from('majors').select('id, name, faculty').order('name');
  return [for (final r in rows) (id: r['id'] as String, name: r['name'] as String, faculty: r['faculty'] as String)];
});

final _profileFormProvider = FutureProvider.autoDispose<ProfileForm>((ref) async {
  final db = ref.watch(supabaseProvider)!;
  final uid = db.auth.currentUser!.id;
  final p = await db.from('profiles').select('full_name, major_id, batch').eq('id', uid).single();
  final skills = await db.from('profile_skills').select('skill_id, level').eq('profile_id', uid);
  return (
    name: (p['full_name'] as String?) ?? '',
    majorId: p['major_id'] as String?,
    batch: (p['batch'] as num?)?.toInt(),
    skills: {for (final s in skills) s['skill_id'] as String: (s['level'] as num).toInt()},
  );
});

const _levels = ['Beginner', 'Intermediate', 'Advanced', 'Expert'];

/// Figma 03 · Set Up Skill Profile (also "My profile" from the drawer).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const PageScaffold(title: 'Skill profile', body: NeedsBackend());
    return PageScaffold(
      title: 'Skill profile',
      body: AsyncView<ProfileForm>(
        loading: const SkeletonDetail(),
        value: ref.watch(_profileFormProvider),
        onRetry: () => ref.invalidate(_profileFormProvider),
        data: (f) => _Form(initial: f),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial});

  final ProfileForm initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _name = TextEditingController(text: widget.initial.name);
  late String? _major = widget.initial.majorId;
  late int? _batch = widget.initial.batch;
  late final Map<String, int> _skills = {...widget.initial.skills};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(supabaseProvider)!;
    final uid = db.auth.currentUser!.id;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await db.from('profiles').update({'full_name': _name.text.trim(), 'major_id': _major, 'batch': _batch, 'onboarded': true}).eq('id', uid);
      await db.from('profile_skills').delete().eq('profile_id', uid);
      if (_skills.isNotEmpty) {
        await db.from('profile_skills').insert([
          for (final e in _skills.entries) {'profile_id': uid, 'skill_id': e.key, 'level': e.value},
        ]);
      }
    }, success: 'Profile saved. Teams can find you now.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(profileProvider);
      context.canPop() ? context.pop() : context.go('/browse');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final catalog = {for (final s in ref.watch(skillsCatalogProvider).value ?? const <SkillOption>[]) s.id: s};
    final year = DateTime.now().year;
    final valid = _name.text.trim().length >= 2 && _major != null && _skills.isNotEmpty;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      Text('Your hard & soft skills power Bearch\'s matchmaking. Teammates rate them after each competition.', style: t.bodySmall),
      const SizedBox(height: 12),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          AsyncView<List<Major>>(
            loading: const SkeletonPulse(child: SkeletonBox(height: 56, radius: 14)),
            value: ref.watch(majorsProvider),
            data: (majors) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final id = await pickMajor(context, majors: majors, selected: _major);
                if (id != null) setState(() => _major = id);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Study program', suffixIcon: Icon(Icons.search_rounded)),
                child: Text(majors.where((m) => m.id == _major).firstOrNull?.name ?? 'Choose your program'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChoiceGroup<int>(
            label: 'Batch',
            options: [
              for (var y = year; y >= year - 4; y--) (value: y, label: '$y'),
              if (_batch != null && _batch! < year - 4) (value: _batch!, label: '$_batch'),
            ],
            value: _batch,
            onChanged: (v) => setState(() => _batch = v),
          ),
        ]),
      ),
      SectionLabel(
        'Skills · pick your level',
        trailing: TextButton(
          onPressed: () async {
            final picked = await pickSkills(context, initial: _skills.keys.toSet(), title: 'Your skills');
            if (picked == null) return;
            setState(() {
              _skills.removeWhere((k, _) => !picked.contains(k));
              for (final id in picked) {
                _skills.putIfAbsent(id, () => 2);
              }
            });
          },
          child: const Text('Add / remove'),
        ),
      ),
      if (_skills.isEmpty) Text('Add at least one skill.', style: t.bodySmall),
      for (final e in _skills.entries) ...[
        Text('${catalog[e.key]?.name ?? '…'}${catalog[e.key]?.kind == 'soft' ? ' · soft' : ''}',
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (var i = 0; i < 4; i++) ButtonSegment(value: i + 1, label: Text(_levels[i], style: const TextStyle(fontSize: 11)))],
          selected: {e.value},
          onSelectionChanged: (v) => setState(() => _skills[e.key] = v.first),
        ),
        const SizedBox(height: 10),
      ],
      const SectionLabel('Availability'),
      OutlinedButton.icon(
        icon: const Icon(Icons.edit_calendar_rounded),
        label: const Text('Edit my weekly free time'),
        onPressed: () => showAvailabilitySheet(context),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: !valid || _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save profile')),
    ]);
  }
}
