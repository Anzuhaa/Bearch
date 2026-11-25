import 'package:flutter/material.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/theme.dart';
import 'lobby_models.dart';

/// Lobby summary card used on competition detail and My Lobbies.
class TeamCard extends StatelessWidget {
  const TeamCard({super.key, required this.team, this.action, this.subtitle, this.onTap});

  final TeamView team;
  final Widget? action;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final leader = team.members.where((m) => m.isLeader).firstOrNull;
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(team.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              StatusPill(locked: team.isLocked),
            ],
          ),
          Text(
            subtitle ?? 'by ${leader?.fullName ?? '—'}${leader?.majorName != null ? ' · ${leader!.majorName}' : ''}',
            style: t.bodySmall,
          ),
          if (team.pitch.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${team.pitch}”', style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (team.neededSkills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Looking for', style: t.labelSmall),
            const SizedBox(height: 4),
            SkillChips([for (final s in team.neededSkills) s.roleLabel ?? s.name]),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              MemberAvatars(team.members),
              const SizedBox(width: 8),
              Text('${team.members.length}/${team.maxMembers}', style: t.labelLarge),
              const Spacer(),
              ?action,
            ],
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) => locked
      ? const Pill('Locked', color: BearchColors.success, icon: Icons.lock_rounded)
      : const Pill('Broadcasting', color: BearchColors.accent, icon: Icons.podcasts_rounded);
}

class SkillChips extends StatelessWidget {
  const SkillChips(this.names, {super.key, this.color = BearchColors.accent});

  final List<String> names;
  final Color color;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final n in names) Pill(n, color: color)],
      );
}

class MemberAvatars extends StatelessWidget {
  const MemberAvatars(this.members, {super.key});

  final List<MemberView> members;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(4).toList();
    return SizedBox(
      width: shown.isEmpty ? 0 : 24.0 * shown.length + 8,
      height: 32,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: i * 24.0, child: InitialsAvatar(shown[i].fullName, size: 32)),
        ],
      ),
    );
  }
}

class MemberTile extends StatelessWidget {
  const MemberTile(this.member, {super.key});

  final MemberView member;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final role = [member.majorName, member.isLeader ? 'Leader' : member.roleLabel].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          InitialsAvatar(member.fullName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (role.isNotEmpty) Text(role, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// H-1 lock rule banner: neutral info, H-3/H-2 warning, or locked confirmation.
class LockBanner extends StatelessWidget {
  const LockBanner({super.key, required this.team});

  final TeamView team;

  @override
  Widget build(BuildContext context) {
    final days = daysUntil(team.deadline);
    final (Color color, IconData icon, String text) = team.isLocked
        ? (BearchColors.success, Icons.verified_rounded,
            'Team locked & registered · ${team.members.length} members. Locked teams can\'t be unlocked.')
        : days <= 3
            ? (BearchColors.warning, Icons.notifications_active_rounded,
                'H-$days reminder · ${team.openSlots} slot(s) open. Auto-locks ${lockTimeLabel(team.deadline)} '
                    'even if not full; pending requests will be auto-rejected.')
            : (BearchColors.accent, Icons.lock_clock_rounded,
                'Auto-locks H-1 · ${lockTimeLabel(team.deadline)} · no unlock. Leaders can lock earlier.');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
