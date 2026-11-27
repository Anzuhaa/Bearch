import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import 'lobby_models.dart';
import 'lobby_providers.dart';
import 'lobby_sections.dart';
import 'lobby_widgets.dart';
import 'skills_picker_sheet.dart';
import 'team_size_sheet.dart';

/// Figma 06 · Lobby · Manage Broadcast (+ 09 Team Locked when locked).
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const PageScaffold(title: 'Lobby', body: NeedsBackend());
    final team = ref.watch(teamProvider(teamId));
    return PageScaffold(
      title: team.value?.competitionName ?? 'Lobby',
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(pendingRequestsProvider(teamId));
          ref.invalidate(teamInvitesProvider(teamId));
          return ref.refresh(teamProvider(teamId).future);
        },
        child: AsyncView<TeamView>(
          loading: const SkeletonDetail(),
          value: team,
          onRetry: () => ref.invalidate(teamProvider(teamId)),
          data: (t) => _LobbyBody(team: t),
        ),
      ),
    );
  }
}

class _LobbyBody extends ConsumerWidget {
  const _LobbyBody({required this.team});

  final TeamView team;

  void _refresh(WidgetRef ref) {
    ref.invalidate(teamProvider(team.id));
    ref.invalidate(pendingRequestsProvider(team.id));
    ref.invalidate(teamInvitesProvider(team.id));
    ref.invalidate(myTeamsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final me = ref.watch(supabaseProvider)?.auth.currentUser?.id;
    final api = ref.watch(bearchApiProvider);
    final isLeader = team.leaderId == me;
    final open = !team.isLocked;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        LockBanner(team: team),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, children: [
                StatusPill(locked: team.isLocked),
                if (team.approvalBased) const Pill('Approval-based', icon: Icons.shield_outlined),
              ]),
              const SizedBox(height: 8),
              Text(team.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (team.pitch.isNotEmpty) Text('“${team.pitch}”', style: t.bodyMedium),
              const SizedBox(height: 12),
              Text('${team.members.length} / ${team.maxMembers} members', style: t.titleSmall),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: team.members.length / team.maxMembers,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                color: BearchColors.accent,
              ),
            ],
          ),
        ),
        if (isLeader && open) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Recommended teammates'),
            onPressed: () => context.push('/lobby/${team.id}/recommend'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline_rounded, color: BearchColors.warning),
            label: const Text('Lock team now'),
            onPressed: api == null
                ? null
                : () async {
                    final yes = await confirmDialog(context,
                        title: 'Lock ${team.name}?',
                        message: 'Locking registers the team with ${team.members.length}/${team.maxMembers} members. '
                            'Pending requests are auto-rejected and there is no unlock.',
                        confirmLabel: 'Lock team',
                        destructive: true);
                    if (!yes || !context.mounted) return;
                    if (await runAction(context, () => api.lockTeam(team.id), success: 'Team locked & registered')) {
                      _refresh(ref);
                    }
                  },
          ),
        ],
        SectionLabel(
          'Team · ${team.members.length}/${team.maxMembers}',
          trailing: isLeader && open && api != null
              ? TextButton(
                  onPressed: () async {
                    if (await showTeamSizeSheet(context, team)) _refresh(ref);
                  },
                  child: const Text('Edit size'),
                )
              : null,
        ),
        GlassCard(
          child: Column(children: [
            for (final m in team.members) MemberTile(m),
            for (var i = 0; i < team.openSlots && open; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
                title: const Text('Open slot'),
                subtitle: i < team.neededSkills.length ? Text('Needs: ${team.neededSkills[i].name}') : null,
              ),
          ]),
        ),
        SectionLabel(
          'Skills needed',
          trailing: isLeader && open && api != null
              ? TextButton(
                  onPressed: () async {
                    final picked = await pickSkills(context, initial: {for (final s in team.neededSkills) s.skillId});
                    if (picked == null || !context.mounted) return;
                    if (await runAction(context, () => api.setRequiredSkills(team.id, picked), success: 'Skills updated')) {
                      _refresh(ref);
                    }
                  },
                  child: const Text('Edit'),
                )
              : null,
        ),
        team.neededSkills.isEmpty
            ? Text('Not set. AI will infer them from the competition details.', style: t.bodySmall)
            : SkillChips([for (final s in team.neededSkills) s.name]),
        if (isLeader && open) ...[
          JoinRequestsSection(team: team, onChanged: () => _refresh(ref)),
          PendingInvitesSection(team: team, onChanged: () => _refresh(ref)),
        ],
        const SizedBox(height: 20),
        if (open && api != null && team.hasMember(me))
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: BearchColors.danger),
            icon: Icon(isLeader ? Icons.delete_outline_rounded : Icons.logout_rounded),
            label: Text(isLeader ? 'Disband lobby' : 'Leave lobby'),
            onPressed: () async {
              final yes = await confirmDialog(context,
                  title: isLeader ? 'Disband ${team.name}?' : 'Leave ${team.name}?',
                  message: isLeader ? 'Members and pending requests will be notified.' : 'You can request another lobby after leaving.',
                  confirmLabel: isLeader ? 'Disband' : 'Leave',
                  destructive: true);
              if (!yes || !context.mounted) return;
              final ok = await runAction(context, () => isLeader ? api.disbandTeam(team.id) : api.leaveTeam(team.id));
              if (ok && context.mounted) {
                ref.invalidate(myTeamsProvider);
                context.pop();
              }
            },
          ),
      ],
    );
  }
}
