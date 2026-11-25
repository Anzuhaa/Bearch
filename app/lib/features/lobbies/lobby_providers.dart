import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/session.dart';
import 'lobby_models.dart';

SupabaseClient _db(Ref ref) {
  final c = ref.watch(supabaseProvider);
  if (c == null) throw StateError('Supabase is not configured (preview mode).');
  return c;
}

String uid(Ref ref) => _db(ref).auth.currentUser!.id;

final competitionDetailProvider = FutureProvider.autoDispose.family<CompetitionDetail, String>((ref, id) async {
  final row = await _db(ref).from('competitions').select(CompetitionDetail.select).eq('id', id).single();
  return CompetitionDetail.fromJson(row);
});

final competitionTeamsProvider = FutureProvider.autoDispose.family<List<TeamView>, String>((ref, competitionId) async {
  final rows = await _db(ref)
      .from('teams')
      .select(TeamView.select)
      .eq('competition_id', competitionId)
      .order('created_at', ascending: true);
  return rows.map(TeamView.fromJson).toList();
});

final teamProvider = FutureProvider.autoDispose.family<TeamView, String>((ref, teamId) async {
  final row = await _db(ref).from('teams').select(TeamView.select).eq('id', teamId).single();
  return TeamView.fromJson(row);
});

/// Lobbies I'm a member of (leader or member), newest first.
final myTeamsProvider = FutureProvider.autoDispose<List<TeamView>>((ref) async {
  final db = _db(ref);
  final mine = await db.from('team_members').select('team_id').eq('profile_id', uid(ref));
  final ids = [for (final r in mine) r['team_id'] as String];
  if (ids.isEmpty) return [];
  final rows = await db.from('teams').select(TeamView.select).inFilter('id', ids).order('created_at', ascending: false);
  return rows.map(TeamView.fromJson).toList();
});

final pendingRequestsProvider = FutureProvider.autoDispose.family<List<JoinRequestView>, String>((ref, teamId) async {
  final rows = await _db(ref)
      .from('join_requests')
      .select(JoinRequestView.select)
      .eq('team_id', teamId)
      .eq('status', 'pending')
      .order('created_at', ascending: true);
  return rows.map(JoinRequestView.fromJson).toList();
});

final teamInvitesProvider = FutureProvider.autoDispose.family<List<InviteView>, String>((ref, teamId) async {
  final rows = await _db(ref)
      .from('team_invites')
      .select(InviteView.select)
      .eq('team_id', teamId)
      .eq('status', 'pending')
      .gt('expires_at', DateTime.now().toUtc().toIso8601String());
  return rows.map(InviteView.fromJson).toList();
});

/// My own join requests (all statuses, newest first).
final myRequestsProvider = FutureProvider.autoDispose<List<JoinRequestView>>((ref) async {
  final rows = await _db(ref)
      .from('join_requests')
      .select(JoinRequestView.select)
      .eq('profile_id', uid(ref))
      .order('created_at', ascending: false)
      .limit(30);
  return rows.map(JoinRequestView.fromJson).toList();
});

/// Invites waiting for me (not expired).
final myInvitesProvider = FutureProvider.autoDispose<List<InviteView>>((ref) async {
  final rows = await _db(ref)
      .from('team_invites')
      .select(InviteView.select)
      .eq('invitee_id', uid(ref))
      .eq('status', 'pending')
      .gt('expires_at', DateTime.now().toUtc().toIso8601String())
      .order('expires_at', ascending: true);
  return rows.map(InviteView.fromJson).toList();
});

final skillsCatalogProvider = FutureProvider<List<SkillOption>>((ref) async {
  final rows = await _db(ref).from('skills').select('id, name, kind').order('name');
  return [
    for (final r in rows) (id: r['id'] as String, name: r['name'] as String, kind: r['kind'] as String),
  ];
});
