import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

class CompetitionSummary {
  const CompetitionSummary({
    required this.id,
    required this.name,
    required this.organizer,
    required this.category,
    required this.level,
    required this.registrationDeadline,
    required this.teamMin,
    required this.teamMax,
    required this.lobbyCount,
  });

  final String id;
  final String name;
  final String organizer;
  final String category;
  final String level;
  final DateTime registrationDeadline;
  final int teamMin;
  final int teamMax;
  final int lobbyCount;

  factory CompetitionSummary.fromJson(Map<String, dynamic> j) => CompetitionSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        organizer: j['organizer'] as String,
        category: j['category'] as String,
        level: j['level'] as String,
        registrationDeadline: DateTime.parse(j['registration_deadline'] as String),
        teamMin: (j['team_min'] as num).toInt(),
        teamMax: (j['team_max'] as num).toInt(),
        lobbyCount: ((j['teams'] as List?)?.firstOrNull as Map?)?['count'] as int? ?? 0,
      );
}

const _categories = <String, String>{
  'all': 'All',
  'technology': 'Technology',
  'business': 'Business',
  'design': 'Design',
  'science': 'Science',
  'social_impact': 'Social Impact',
  'non_academic': 'Non-academic',
};

/// Sample rows for preview mode only (mirrors supabase/seed.sql).
final _previewCompetitions = [
  CompetitionSummary(
    id: 'preview-stack',
    name: 'UPH STACK Hackathon 2026',
    organizer: 'UPH Faculty of Computer Science',
    category: 'technology',
    level: 'campus',
    registrationDeadline: DateTime(2026, 12, 12),
    teamMin: 3,
    teamMax: 5,
    lobbyCount: 3,
  ),
  CompetitionSummary(
    id: 'preview-gemastik',
    name: 'Gemastik XIX: Smart City',
    organizer: 'Kemdikbudristek',
    category: 'technology',
    level: 'national',
    registrationDeadline: DateTime(2027, 1, 5),
    teamMin: 3,
    teamMax: 3,
    lobbyCount: 5,
  ),
  CompetitionSummary(
    id: 'preview-nbcc',
    name: 'National Business Case Competition',
    organizer: 'Universitas Indonesia',
    category: 'business',
    level: 'national',
    registrationDeadline: DateTime(2026, 12, 20),
    teamMin: 3,
    teamMax: 4,
    lobbyCount: 2,
  ),
  CompetitionSummary(
    id: 'preview-ysic',
    name: 'Youth Social Innovation Challenge',
    organizer: 'ASEAN Foundation',
    category: 'social_impact',
    level: 'regional',
    registrationDeadline: DateTime(2027, 1, 10),
    teamMin: 2,
    teamMax: 4,
    lobbyCount: 0,
  ),
];

final competitionsProvider = FutureProvider<List<CompetitionSummary>>((ref) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return _previewCompetitions;
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final rows = await client
      .from('competitions')
      .select('id, name, organizer, category, level, registration_deadline, team_min, team_max, teams(count)')
      .eq('status', 'approved')
      .gte('registration_deadline', today)
      .order('registration_deadline');
  return rows.map(CompetitionSummary.fromJson).toList();
});

/// Figma 04 · Browse Competitions (mobile).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  String _category = 'all';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final competitions = ref.watch(competitionsProvider);
    final profile = ref.watch(profileProvider).value;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(competitionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Verified by UPH Student Affairs', style: t.bodySmall),
          const SizedBox(height: 12),
          if (profile != null && !profile.onboarded) ...[
            GlassCard(
              onTap: () => context.push('/onboarding'),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: BearchColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Finish your skill profile so teams can find you',
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final key = _categories.keys.elementAt(i);
                return ChoiceChip(
                  label: Text(_categories[key]!),
                  selected: _category == key,
                  onSelected: (_) => setState(() => _category = key),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          ...competitions.when(
            loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [
              EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn\'t load competitions',
                message: '$e',
                action: OutlinedButton(onPressed: () => ref.invalidate(competitionsProvider), child: const Text('Retry')),
              ),
            ],
            data: (list) {
              final shown = _category == 'all' ? list : list.where((c) => c.category == _category).toList();
              if (shown.isEmpty) {
                return [
                  EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No open competitions here yet',
                    message: 'Know one that\'s missing? Submit it for validation.',
                    action: FilledButton(onPressed: () => context.go('/submit'), child: const Text('Submit a competition')),
                  ),
                ];
              }
              return [
                for (final c in shown) ...[_CompetitionCard(c), const SizedBox(height: 12)],
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard(this.c);

  final CompetitionSummary c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final deadline = DateFormat('d MMM yyyy').format(c.registrationDeadline);
    final size = c.teamMin == c.teamMax ? '${c.teamMax} members' : '${c.teamMin}–${c.teamMax} members';
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

    return GlassCard(
      onTap: () => context.go('/browse/${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Pill(cap(c.level), color: BearchColors.purple),
                    const Pill('Verified', color: BearchColors.success, icon: Icons.verified_rounded),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(cap(c.category), style: t.labelSmall, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(c.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(c.organizer, style: t.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Meta(Icons.event_rounded, 'Reg. closes $deadline'),
              _Meta(Icons.group_outlined, size),
              _Meta(Icons.meeting_room_outlined, '${c.lobbyCount} open lobbies'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 15, color: style?.color), const SizedBox(width: 4), Text(label, style: style)],
    );
  }
}
