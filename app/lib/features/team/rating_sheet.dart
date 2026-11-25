import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';

typedef Teammate = ({String profileId, String fullName, String? roleLabel, bool rated});

final ratingProgressProvider = FutureProvider.autoDispose.family<List<Teammate>, String>((ref, teamId) async {
  final rows = await ref.watch(supabaseProvider)!.rpc('my_rating_progress', params: {'p_team': teamId}) as List;
  return [
    for (final r in rows.cast<Map<String, dynamic>>())
      (
        profileId: r['profile_id'] as String,
        fullName: r['full_name'] as String,
        roleLabel: r['role_label'] as String?,
        rated: r['rated'] as bool,
      ),
  ];
});

final _hardSkillsProvider = FutureProvider.autoDispose.family<List<({String id, String name})>, String>((ref, profileId) async {
  final rows = await ref
      .watch(supabaseProvider)!
      .from('profile_skills')
      .select('skill_id, skills!inner(name, kind)')
      .eq('profile_id', profileId)
      .eq('skills.kind', 'hard');
  return [for (final r in rows) (id: r['skill_id'] as String, name: (r['skills'] as Map)['name'] as String)];
});

const _tierLabels = ['Novice', 'Competent', 'Proficient', 'Expert'];
const _criteria = {
  'communication': 'Communication',
  'time_management': 'Time management',
  'teamwork': 'Teamwork',
  'responsibility': 'Responsibility',
};

/// Figma 12 · Rate Teammates · Multi-Tier. Returns true when saved.
Future<bool?> showRatingSheet(BuildContext context, String teamId, Teammate mate) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RatingSheet(teamId: teamId, mate: mate),
    );

class _RatingSheet extends ConsumerStatefulWidget {
  const _RatingSheet({required this.teamId, required this.mate});

  final String teamId;
  final Teammate mate;

  @override
  ConsumerState<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<_RatingSheet> {
  final Map<String, int> _skillTiers = {};
  final Map<String, int> _stars = {};
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save(BearchApi api) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => api.submitRating(
        teamId: widget.teamId,
        rateeId: widget.mate.profileId,
        skillTiers: _skillTiers,
        criteria: _stars,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      ),
      success: 'Rating saved for ${widget.mate.fullName}',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final api = ref.watch(bearchApiProvider);
    final complete = _stars.length == _criteria.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.mate.fullName, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text('Ratings are anonymous and aggregated into one reputation score.', style: t.bodySmall),
          const SectionLabel('Hard skills · tier shown in this competition'),
          AsyncView<List<({String id, String name})>>(
            value: ref.watch(_hardSkillsProvider(widget.mate.profileId)),
            data: (skills) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (skills.isEmpty) Text('No hard skills on their profile.', style: t.bodySmall),
              for (final s in skills) ...[
                Text(s.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: [for (var i = 0; i < 4; i++) ButtonSegment(value: i + 1, label: Text(_tierLabels[i], style: const TextStyle(fontSize: 11)))],
                  selected: {?_skillTiers[s.id]},
                  onSelectionChanged: (v) => setState(() {
                    if (v.isEmpty) {
                      _skillTiers.remove(s.id);
                    } else {
                      _skillTiers[s.id] = v.first;
                    }
                  }),
                ),
                const SizedBox(height: 10),
              ],
            ]),
          ),
          const SectionLabel('Soft skills · 1–5 stars'),
          for (final e in _criteria.entries)
            Row(children: [
              Expanded(child: Text(e.value, style: t.bodyMedium)),
              for (var s = 1; s <= 5; s++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '$s star${s > 1 ? 's' : ''} for ${e.value}',
                  onPressed: () => setState(() => _stars[e.key] = s),
                  icon: Icon(
                    s <= (_stars[e.key] ?? 0) ? Icons.star_rounded : Icons.star_border_rounded,
                    color: BearchColors.warning,
                  ),
                ),
            ]),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Comment (optional, visible to admins only)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: api == null || !complete || _busy ? null : () => _save(api),
            child: Text(complete ? 'Save rating' : 'Rate all 4 soft skills'),
          ),
        ]),
      ),
    );
  }
}
