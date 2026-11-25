// Read models for competitions, lobbies (teams), requests and invites.
// Built from PostgREST selects in lobby_providers.dart.

typedef Json = Map<String, dynamic>;

String? _majorOf(Json? profile) => (profile?['majors'] as Json?)?['name'] as String?;

class CompetitionDetail {
  const CompetitionDetail({
    required this.id,
    required this.name,
    required this.organizer,
    required this.category,
    required this.level,
    required this.description,
    required this.deadline,
    required this.teamMin,
    required this.teamMax,
    this.officialUrl,
    this.prize,
    this.eventStart,
    this.eventEnd,
  });

  final String id;
  final String name;
  final String organizer;
  final String category;
  final String level;
  final String description;
  final DateTime deadline;
  final int teamMin;
  final int teamMax;
  final String? officialUrl;
  final String? prize;
  final DateTime? eventStart;
  final DateTime? eventEnd;

  static const select =
      'id, name, organizer, category, level, description, official_url, prize, registration_deadline, '
      'event_start, event_end, team_min, team_max';

  factory CompetitionDetail.fromJson(Json j) => CompetitionDetail(
        id: j['id'] as String,
        name: j['name'] as String,
        organizer: j['organizer'] as String,
        category: j['category'] as String,
        level: j['level'] as String,
        description: (j['description'] as String?) ?? '',
        deadline: DateTime.parse(j['registration_deadline'] as String),
        teamMin: (j['team_min'] as num).toInt(),
        teamMax: (j['team_max'] as num).toInt(),
        officialUrl: j['official_url'] as String?,
        prize: j['prize'] as String?,
        eventStart: j['event_start'] == null ? null : DateTime.parse(j['event_start'] as String),
        eventEnd: j['event_end'] == null ? null : DateTime.parse(j['event_end'] as String),
      );
}

class MemberView {
  const MemberView({required this.profileId, required this.fullName, required this.isLeader, this.majorName, this.roleLabel});

  final String profileId;
  final String fullName;
  final bool isLeader;
  final String? majorName;
  final String? roleLabel;

  factory MemberView.fromJson(Json j) => MemberView(
        profileId: j['profile_id'] as String,
        fullName: ((j['profiles'] as Json?)?['full_name'] as String?) ?? '',
        isLeader: (j['is_leader'] as bool?) ?? false,
        majorName: _majorOf(j['profiles'] as Json?),
        roleLabel: j['role_label'] as String?,
      );
}

typedef NeededSkill = ({String skillId, String name, String? roleLabel});

class TeamView {
  const TeamView({
    required this.id,
    required this.name,
    required this.pitch,
    required this.maxMembers,
    required this.status,
    required this.leaderId,
    required this.competitionId,
    required this.competitionName,
    required this.deadline,
    required this.members,
    required this.neededSkills,
    required this.approvalBased,
  });

  final String id;
  final String name;
  final String pitch;
  final int maxMembers;
  final String status;
  final String leaderId;
  final String competitionId;
  final String competitionName;
  final DateTime deadline;
  final List<MemberView> members;
  final List<NeededSkill> neededSkills;
  final bool approvalBased;

  bool get isLocked => status == 'locked';
  int get openSlots => maxMembers - members.length;
  bool hasMember(String? uid) => members.any((m) => m.profileId == uid);
  Set<String> get majors => {for (final m in members) ?m.majorName};

  static const select =
      'id, name, pitch, max_members, status, leader_id, competition_id, approval_based, created_at, '
      'competitions(name, registration_deadline), '
      'team_members(profile_id, role_label, is_leader, joined_at, profiles(full_name, majors(name))), '
      'team_required_skills(skill_id, role_label, skills(name))';

  factory TeamView.fromJson(Json j) {
    final comp = j['competitions'] as Json;
    final members = [for (final m in (j['team_members'] as List)) MemberView.fromJson(m as Json)]
      ..sort((a, b) => (b.isLeader ? 1 : 0) - (a.isLeader ? 1 : 0));
    return TeamView(
      id: j['id'] as String,
      name: j['name'] as String,
      pitch: (j['pitch'] as String?) ?? '',
      maxMembers: (j['max_members'] as num).toInt(),
      status: j['status'] as String,
      leaderId: j['leader_id'] as String,
      competitionId: j['competition_id'] as String,
      competitionName: comp['name'] as String,
      deadline: DateTime.parse(comp['registration_deadline'] as String),
      approvalBased: (j['approval_based'] as bool?) ?? true,
      members: members,
      neededSkills: [
        for (final s in (j['team_required_skills'] as List))
          (
            skillId: (s as Json)['skill_id'] as String,
            name: ((s['skills'] as Json?)?['name'] as String?) ?? '',
            roleLabel: s['role_label'] as String?,
          ),
      ],
    );
  }
}

class JoinRequestView {
  const JoinRequestView({
    required this.id,
    required this.teamId,
    required this.profileId,
    required this.fullName,
    required this.message,
    required this.status,
    required this.createdAt,
    this.majorName,
    this.reputation,
    this.teamName,
    this.competitionName,
  });

  final String id;
  final String teamId;
  final String profileId;
  final String fullName;
  final String message;
  final String status;
  final DateTime createdAt;
  final String? majorName;
  final double? reputation;
  final String? teamName;
  final String? competitionName;

  static const select = 'id, team_id, profile_id, message, status, created_at, '
      'profiles!join_requests_profile_id_fkey(full_name, reputation, majors(name)), '
      'teams(name, competitions(name))';

  factory JoinRequestView.fromJson(Json j) {
    final p = j['profiles'] as Json?;
    final t = j['teams'] as Json?;
    return JoinRequestView(
      id: j['id'] as String,
      teamId: j['team_id'] as String,
      profileId: j['profile_id'] as String,
      fullName: (p?['full_name'] as String?) ?? '',
      message: (j['message'] as String?) ?? '',
      status: j['status'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      majorName: _majorOf(p),
      reputation: (p?['reputation'] as num?)?.toDouble(),
      teamName: t?['name'] as String?,
      competitionName: (t?['competitions'] as Json?)?['name'] as String?,
    );
  }
}

class InviteView {
  const InviteView({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.competitionName,
    required this.inviteeName,
    required this.message,
    required this.expiresAt,
    this.roleLabel,
  });

  final String id;
  final String teamId;
  final String teamName;
  final String competitionName;
  final String inviteeName;
  final String message;
  final DateTime expiresAt;
  final String? roleLabel;

  static const select = 'id, team_id, role_label, message, expires_at, '
      'invitee:profiles!team_invites_invitee_id_fkey(full_name), teams(name, competitions(name))';

  factory InviteView.fromJson(Json j) {
    final t = j['teams'] as Json?;
    return InviteView(
      id: j['id'] as String,
      teamId: j['team_id'] as String,
      teamName: (t?['name'] as String?) ?? '',
      competitionName: ((t?['competitions'] as Json?)?['name'] as String?) ?? '',
      inviteeName: ((j['invitee'] as Json?)?['full_name'] as String?) ?? '',
      message: (j['message'] as String?) ?? '',
      expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
      roleLabel: j['role_label'] as String?,
    );
  }
}

typedef SkillOption = ({String id, String name, String kind});
