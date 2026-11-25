import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/skeleton.dart';
import 'lobby_models.dart';
import 'lobby_providers.dart';

/// Bottom sheet to pick skills from the catalog. Returns null when dismissed.
Future<Set<String>?> pickSkills(BuildContext context, {required Set<String> initial, String title = 'Skills needed'}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SkillsPicker(initial: initial, title: title),
  );
}

class _SkillsPicker extends ConsumerStatefulWidget {
  const _SkillsPicker({required this.initial, required this.title});

  final Set<String> initial;
  final String title;

  @override
  ConsumerState<_SkillsPicker> createState() => _SkillsPickerState();
}

class _SkillsPickerState extends ConsumerState<_SkillsPicker> {
  late final Set<String> _selected = {...widget.initial};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${_selected.length} selected', style: t.bodySmall),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search skills'),
              ),
              Expanded(
                child: AsyncView<List<SkillOption>>(
                  loading: const SkeletonList(count: 2, lines: 2),
                  value: ref.watch(skillsCatalogProvider),
                  onRetry: () => ref.invalidate(skillsCatalogProvider),
                  data: (skills) => ListView(
                    children: [
                      for (final kind in ['hard', 'soft']) ...[
                        SectionLabel(kind == 'hard' ? 'Hard skills' : 'Soft skills'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in skills.where((s) => s.kind == kind && (_q.isEmpty || s.name.toLowerCase().contains(_q))))
                              FilterChip(
                                label: Text(s.name),
                                selected: _selected.contains(s.id),
                                onSelected: (on) => setState(() => on ? _selected.add(s.id) : _selected.remove(s.id)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
