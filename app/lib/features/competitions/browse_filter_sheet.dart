import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'competitions_data.dart';

const browseSorts = {'deadline': 'Closing soon', 'lobbies': 'Most open lobbies', 'name': 'A–Z'};

typedef BrowseFilter = ({String category, String sort});

/// Category + sort in one sheet (same pattern as the Study program picker):
/// search on top, two short groups below instead of a long chip strip.
Future<BrowseFilter?> showBrowseFilterSheet(BuildContext context, BrowseFilter current, Map<String, int> counts) =>
    showModalBottomSheet<BrowseFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(current: current, counts: counts),
    );

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.counts});

  final BrowseFilter current;
  final Map<String, int> counts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String _q = '';
  late String _sort = widget.current.sort;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _q.trim().toLowerCase();
    final cats = competitionCategories.entries.where((e) => q.isEmpty || e.value.toLowerCase().contains(q)).toList();
    const check = Icon(Icons.check_rounded, color: BearchColors.accent);
    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text(s, style: t.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700)),
        );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Filter competitions', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search category'),
            ),
            Expanded(
              child: ListView(children: [
                if (q.isEmpty) ...[
                  header('SORT BY'),
                  for (final e in browseSorts.entries)
                    ListTile(
                      dense: true,
                      title: Text(e.value),
                      trailing: _sort == e.key ? check : null,
                      onTap: () => setState(() => _sort = e.key),
                    ),
                ],
                header('CATEGORY'),
                for (final e in cats)
                  ListTile(
                    dense: true,
                    title: Text(e.value),
                    subtitle: Text(_plural(widget.counts[e.key] ?? 0)),
                    trailing: widget.current.category == e.key ? check : null,
                    onTap: () => Navigator.pop(context, (category: e.key, sort: _sort)),
                  ),
                if (cats.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No category matches "$_q"', style: t.bodyMedium)),
              ]),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (category: widget.current.category, sort: _sort)),
              child: const Text('Apply'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

String _plural(int n) => '$n ${n == 1 ? 'competition' : 'competitions'}';
