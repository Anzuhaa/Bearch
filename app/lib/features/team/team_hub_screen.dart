import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';
import '../lobbies/lobby_widgets.dart';
import '../reports/report_form_sheet.dart';
import 'team_page.dart';

/// One team's home: who's in it, its state, and everything you can do with it.
class TeamHubScreen extends StatelessWidget {
  const TeamHubScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context) => TeamPage(teamId: teamId, title: 'Team', builder: (team) => _Hub(team: team));
}

class _Hub extends ConsumerWidget {
  const _Hub({required this.team});

  final TeamView team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final isLeader = team.leaderId == ref.watch(currentUidProvider);
    final id = team.id;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(teamProvider(id).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatusPill(locked: team.isLocked),
            const SizedBox(height: 8),
            Text(team.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(team.competitionName, style: t.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              MemberAvatars(team.members),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${team.members.length}/${team.maxMembers} members${isLeader ? ' · you lead' : ''}', style: t.labelLarge),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        LockBanner(team: team),
        const SizedBox(height: 16),
        _Tile(
          icon: Icons.groups_rounded,
          title: team.isLocked ? 'Members' : 'Lobby & members',
          subtitle: team.isLocked
              ? 'Registered team · ${team.members.length} members'
              : isLeader
                  ? 'Requests, invites, AI recommendations, lock team'
                  : 'Members, needed skills, leave lobby',
          onTap: () => context.push('/lobby/$id'),
        ),
        _Tile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Chat',
          subtitle: 'Team group chat',
          onTap: () => context.push('/team/$id/chat'),
        ),
        _Tile(
          icon: Icons.calendar_month_rounded,
          title: 'Calendar',
          subtitle: 'Shared free time & best meeting slots',
          onTap: () => context.push('/team/$id/calendar'),
        ),
        _Tile(
          icon: Icons.workspace_premium_outlined,
          title: 'Rate & claim SEP',
          subtitle: team.isLocked
              ? 'After the event: rate teammates, upload result, claim SEP'
              : 'Available once the team is locked',
          onTap: team.isLocked ? () => context.push('/team/$id/rate') : null,
        ),
        _Tile(
          icon: Icons.flag_outlined,
          title: 'Report a member',
          subtitle: 'Fact-based, with evidence. They can appeal within 7 days.',
          color: BearchColors.danger,
          onTap: team.members.length < 2
              ? null
              : () async {
                  if (await showReportSheet(context, teamId: id) == true && context.mounted) context.go('/reports');
                },
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.color});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final c = color ?? BearchColors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: t.bodySmall),
              ]),
            ),
            if (enabled) const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}
