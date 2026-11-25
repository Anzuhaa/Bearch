import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session.dart';
import 'models.dart';

export 'models.dart';


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

  Future<void> cancelInvite(String inviteId) => _db.rpc('cancel_invite', params: {'p_invite': inviteId});

  /// Leader-only (RLS): replace the skills the lobby still needs.
  Future<void> setRequiredSkills(String teamId, Iterable<String> skillIds) async {
    await _db.from('team_required_skills').delete().eq('team_id', teamId);
    final rows = [for (final id in skillIds) {'team_id': teamId, 'skill_id': id}];
    if (rows.isNotEmpty) await _db.from('team_required_skills').insert(rows);
  }

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
  /// Insert (id == null) or update a draft submission. `fields` use DB column names.
  Future<String> saveCompetitionDraft(String? id, Map<String, Object?> fields) async {
    if (id != null) {
      await _db.from('competitions').update(fields).eq('id', id);
      return id;
    }
    final row = await _db
        .from('competitions')
        .insert({...fields, 'submitted_by': _db.auth.currentUser!.id})
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Upload a poster/guidebook to `competition-proofs/{competitionId}/` and record it.
  Future<void> uploadCompetitionProof(String competitionId, String fileName, List<int> bytes) async {
    final path = '$competitionId/${DateTime.now().millisecondsSinceEpoch}-$fileName';
    await _db.storage.from('competition-proofs').uploadBinary(path, Uint8List.fromList(bytes));
    await _db.from('competition_files').insert({
      'competition_id': competitionId,
      'storage_path': path,
      'file_name': fileName,
      'size_bytes': bytes.length,
      'uploaded_by': _db.auth.currentUser!.id,
    });
  }

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

  Future<int?> sepEstimate(String teamId, String placement) async =>
      (await _db.rpc('sep_estimate', params: {'p_team': teamId, 'p_placement': placement}) as num?)?.toInt();

  /// Winning-result upload. Storage RLS blocks it until you rated every teammate.
  Future<String> uploadSepProof(String teamId, String fileName, List<int> bytes) async {
    final path = '$teamId/${DateTime.now().millisecondsSinceEpoch}-$fileName';
    await _db.storage.from('sep-proofs').uploadBinary(path, Uint8List.fromList(bytes));
    return path;
  }

  Future<void> attachSepFile(String claimId, String path, String fileName, int size) =>
      _db.from('sep_claim_files').insert({'claim_id': claimId, 'storage_path': path, 'file_name': fileName, 'size_bytes': size});

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

final bearchApiProvider = Provider<BearchApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : BearchApi(client);
});
