import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session.dart';

/// Shown when no required skills exist and AI inference is unavailable.
const kSkillsNotSetMessage = 'Skill yang dibutuhkan belum diatur';

/// Thin typed wrapper over the Supabase RPCs and Edge Functions.
/// All business rules (locking, slots, eligibility) live in the database;
/// this class only maps arguments and results.
class BearchApi {
  BearchApi(this._db);

  final SupabaseClient _db;

  // ---------------------------------------------------------------- lobbies
  Future<String> createTeam({
    required String competitionId,
    required String name,
    String pitch = '',
    int? maxMembers,
    bool approvalBased = true,
    bool crossMajorPreferred = true,
    List<({String skillId, String? roleLabel})> requiredSkills = const [],
  }) async =>
      await _db.rpc('create_team', params: {
        'p_competition': competitionId,
        'p_name': name,
        'p_pitch': pitch,
        'p_max_members': maxMembers,
        'p_approval_based': approvalBased,
        'p_cross_major_preferred': crossMajorPreferred,
        'p_required_skills': [
          for (final s in requiredSkills) {'skill_id': s.skillId, 'role_label': s.roleLabel},
        ],
      }) as String;

  Future<String> requestJoin(String teamId, {String message = ''}) async =>
      await _db.rpc('request_join', params: {'p_team': teamId, 'p_message': message}) as String;

  Future<void> cancelJoinRequest(String requestId) =>
      _db.rpc('cancel_join_request', params: {'p_request': requestId});

  Future<void> decideJoinRequest(String requestId, {required bool approve}) =>
      _db.rpc('decide_join_request', params: {'p_request': requestId, 'p_approve': approve});

  Future<String> sendInvite(String teamId, String inviteeId, {String? roleLabel, String message = ''}) async =>
      await _db.rpc('send_invite', params: {
        'p_team': teamId,
        'p_invitee': inviteeId,
        'p_role_label': roleLabel,
        'p_message': message,
      }) as String;

  Future<void> respondInvite(String inviteId, {required bool accept}) =>
      _db.rpc('respond_invite', params: {'p_invite': inviteId, 'p_accept': accept});

  /// Locks even if the team is not full. There is no unlock.
  Future<void> lockTeam(String teamId) => _db.rpc('lock_team', params: {'p_team': teamId});

  Future<void> leaveTeam(String teamId) => _db.rpc('leave_team', params: {'p_team': teamId});

  Future<void> disbandTeam(String teamId) => _db.rpc('disband_team', params: {'p_team': teamId});

  // --------------------------------------------------------------- matching
  /// Ensures the team has skills to match on. Uses the leader's skills if set,
  /// otherwise the competition's cached AI inference (Gemini, once per competition).
  Future<InferSkillsResult> inferSkills(String teamId) async {
    final res = await _db.functions.invoke('infer-skills', body: {'team_id': teamId});
    return InferSkillsResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Candidate>> recommendCandidates(String teamId, {int limit = 20}) async {
    final rows = await _db.rpc('recommend_candidates', params: {'p_team': teamId, 'p_limit': limit}) as List;
    return rows.map((r) => Candidate.fromJson(r as Map<String, dynamic>)).toList();
  }

  // ----------------------------------------------------------- competitions
  Future<DuplicateCheck> checkDuplicate(String competitionId) async {
    final res = await _db.functions.invoke('check-duplicate', body: {'competition_id': competitionId});
    return DuplicateCheck.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> submitCompetition(String competitionId, {String? overrideReason}) =>
      _db.rpc('submit_competition', params: {
        'p_competition': competitionId,
        'p_override_reason': overrideReason,
      });

  // ------------------------------------------------- ratings, reports, SEP
  Future<void> submitRating({
    required String teamId,
    required String rateeId,
    required Map<String, int> skillTiers, // skill_id -> 1..4
    required Map<String, int> criteria, // communication, time_management, teamwork, responsibility -> 1..5
    String? comment,
  }) =>
      _db.rpc('submit_rating', params: {
        'p_team': teamId,
        'p_ratee': rateeId,
        'p_skill_tiers': [
          for (final e in skillTiers.entries) {'skill_id': e.key, 'tier': e.value},
        ],
        'p_criteria': criteria,
        'p_comment': comment,
      });

  Future<List<String>> sepClaimBlockers(String teamId) async =>
      ((await _db.rpc('sep_claim_blockers', params: {'p_team': teamId})) as List).cast<String>();

  Future<String> submitSepClaim(String teamId, {
    required String placement, // winner_1 | winner_2 | winner_3 | finalist | participant
    required String placementLabel,
    String? announcementUrl,
  }) async =>
      await _db.rpc('submit_sep_claim', params: {
        'p_team': teamId,
        'p_placement': placement,
        'p_placement_label': placementLabel,
        'p_announcement_url': announcementUrl,
      }) as String;

  Future<String> fileReport({
    required String teamId,
    required String reportedId,
    required String reason, // non_contribution | missed_deadlines | no_show | disrespectful | other
    required String description,
    required List<Map<String, String>> evidence, // [{label, storage_path?|external_url?}]
  }) async =>
      await _db.rpc('file_report', params: {
        'p_team': teamId,
        'p_reported': reportedId,
        'p_reason': reason,
        'p_description': description,
        'p_evidence': evidence,
      }) as String;

  Future<void> submitAppeal(String reportId, String text, {List<Map<String, String>> evidence = const []}) =>
      _db.rpc('submit_appeal', params: {'p_report': reportId, 'p_text': text, 'p_evidence': evidence});

  // ------------------------------------------------------------------ admin
  Future<Map<String, dynamic>> adminDashboardStats() async =>
      await _db.rpc('admin_dashboard_stats') as Map<String, dynamic>;

  Future<void> adminReviewCompetition(String competitionId, {required bool approve, String? note}) =>
      _db.rpc('admin_review_competition', params: {
        'p_competition': competitionId,
        'p_approve': approve,
        'p_note': note,
      });

  /// decision: upheld | dismissed | info_requested
  Future<void> adminDecideReport(String reportId, String decision, {String? note, bool falseReport = false}) =>
      _db.rpc('admin_decide_report', params: {
        'p_report': reportId,
        'p_decision': decision,
        'p_note': note,
        'p_false_report': falseReport,
      });

  Future<void> adminVerifySepClaim(String claimId, {required bool approve, int? points, String? note}) =>
      _db.rpc('admin_verify_sep_claim', params: {
        'p_claim': claimId,
        'p_approve': approve,
        'p_points': points,
        'p_note': note,
      });
}

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

final bearchApiProvider = Provider<BearchApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : BearchApi(client);
});
