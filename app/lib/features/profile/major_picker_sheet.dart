import 'package:flutter/material.dart';

import '../../core/theme.dart';

typedef Major = ({String id, String name, String faculty});

/// Study-program picker: search box + programs grouped by faculty (two short
/// scans instead of one long list). Returns the chosen id, or null.
Future<String?> pickMajor(BuildContext context, {required List<Major> majors, String? selected}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MajorPicker(majors: majors, selected: selected),
    );

class _MajorPicker extends StatefulWidget {
  const _MajorPicker({required this.majors, this.selected});

  final List<Major> majors;
  final String? selected;

  @override
  State<_MajorPicker> createState() => _MajorPickerState();
}

class _MajorPickerState extends State<_MajorPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _q.trim().toLowerCase();
    final shown = widget.majors.where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.faculty.toLowerCase().contains(q));
    final byFaculty = <String, List<Major>>{};
    for (final m in shown) {
      (byFaculty[m.faculty] ??= []).add(m);
    }
    final faculties = byFaculty.keys.toList()..sort();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Study program', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search program or faculty'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: faculties.isEmpty
                  ? Center(child: Text('No program matches "$_q"', style: t.bodyMedium))
                  : ListView(children: [
                      for (final f in faculties) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                          child: Text(f.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                        ),
                        for (final m in byFaculty[f]!)
                          ListTile(
                            dense: true,
                            title: Text(m.name),
                            trailing: m.id == widget.selected ? const Icon(Icons.check_rounded, color: BearchColors.accent) : null,
                            onTap: () => Navigator.pop(context, m.id),
                          ),
                      ],
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
