// Result models for BearchApi (RPC / Edge Function responses).

/// Shown when no required skills exist and AI inference is unavailable.
const kSkillsNotSetMessage = 'Skill yang dibutuhkan belum diatur';

class InferSkillsResult {
  const InferSkillsResult({required this.source, required this.fallback, required this.skills, this.message});

  /// leader | ai | none
  final String source;
  final bool fallback;
  final List<String> skills;
  final String? message;

  factory InferSkillsResult.fromJson(Map<String, dynamic> j) => InferSkillsResult(
        source: j['source'] as String? ?? 'none',
        fallback: j['fallback'] as bool? ?? false,
        skills: [
          for (final s in (j['skills'] as List? ?? const []))
            if (s is Map && s['name'] != null) s['name'] as String,
        ],
        message: j['message'] as String? ?? (j['fallback'] == true ? kSkillsNotSetMessage : null),
      );
}

class Candidate {
  const Candidate({
    required this.profileId,
    required this.fullName,
    required this.matchScore,
    required this.matchedSkills,
    required this.reasons,
    required this.crossMajor,
    required this.pendingWithTeam,
    this.majorName,
    this.reputation,
    this.availabilityOverlap,
  });

  final String profileId;
  final String fullName;
  final String? majorName;
  final double? reputation;
  final int matchScore;
  final List<String> matchedSkills;
  final List<String> reasons;
  final int? availabilityOverlap;
  final bool crossMajor;
  final bool pendingWithTeam;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        profileId: j['profile_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        majorName: j['major_name'] as String?,
        reputation: (j['reputation'] as num?)?.toDouble(),
        matchScore: (j['match_score'] as num).toInt(),
        matchedSkills: (j['matched_skills'] as List? ?? const []).cast<String>(),
        reasons: (j['reasons'] as List? ?? const []).cast<String>(),
        availabilityOverlap: (j['availability_overlap'] as num?)?.toInt(),
        crossMajor: j['cross_major'] as bool? ?? false,
        pendingWithTeam: j['pending_with_team'] as bool? ?? false,
      );
}

class DuplicateCheck {
  const DuplicateCheck({required this.status, this.duplicateOfName, this.reasons = const [], this.message});

  /// clear | possible_duplicate | check_failed
  final String status;
  final String? duplicateOfName;
  final List<({String label, String value})> reasons;
  final String? message;

  bool get needsOverrideReason => status == 'possible_duplicate';

  factory DuplicateCheck.fromJson(Map<String, dynamic> j) => DuplicateCheck(
        status: j['status'] as String? ?? 'check_failed',
        duplicateOfName: (j['duplicate_of'] as Map?)?['name'] as String?,
        reasons: [
          for (final r in (j['reasons'] as List? ?? const []))
            (label: (r as Map)['label'] as String, value: r['value'] as String),
        ],
        message: j['message'] as String? ?? j['summary'] as String?,
      );
}
