import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/session.dart';

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

const competitionCategories = <String, String>{
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
