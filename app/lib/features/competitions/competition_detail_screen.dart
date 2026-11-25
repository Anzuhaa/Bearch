import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import '../lobbies/create_lobby_sheet.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';
import '../lobbies/lobby_widgets.dart';

/// Figma 05 · Competition Detail: info, H-1 lock rule, open lobbies.
class CompetitionDetailScreen extends ConsumerWidget {
  const CompetitionDetailScreen({super.key, required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const PageScaffold(title: 'Competition', body: NeedsBackend());
    final comp = ref.watch(competitionDetailProvider(competitionId));
    return PageScaffold(
      title: 'Competition',
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(competitionTeamsProvider(competitionId));
          ref.invalidate(myRequestsProvider);
          return ref.refresh(competitionDetailProvider(competitionId).future);
        },
        child: AsyncView<CompetitionDetail>(
          loading: const SkeletonDetail(),
          value: comp,
          onRetry: () => ref.invalidate(competitionDetailProvider(competitionId)),
          data: (c) => _Body(competition: c),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.competition});

  final CompetitionDetail competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final t = Theme.of(context).textTheme;
    final me = ref.watch(supabaseProvider)?.auth.currentUser?.id;
    final teams = ref.watch(competitionTeamsProvider(c.id));
    final myRequests = ref.watch(myRequestsProvider).value ?? const <JoinRequestView>[];
    final lockPassed = daysUntil(c.deadline) < 1;
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                const Pill('Verified', color: BearchColors.success, icon: Icons.verified_rounded),
                Pill(cap(c.category)),
                Pill('${cap(c.level)} level', color: BearchColors.purple),
              ]),
              const SizedBox(height: 10),
              Text(c.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(c.organizer, style: t.bodySmall),
              if (c.description.isNotEmpty) ...[const SizedBox(height: 10), Text(c.description, style: t.bodyMedium)],
              const SizedBox(height: 14),
              _Fact('Registration closes', formatDate(c.deadline)),
              _Fact('Team size', c.teamMin == c.teamMax ? '${c.teamMax} members' : '${c.teamMin}–${c.teamMax} members'),
              if (c.prize != null) _Fact('Prize', c.prize!),
              if (c.eventStart != null)
                _Fact('Event', '${formatDate(c.eventStart!)}${c.eventEnd != null ? ' – ${formatDate(c.eventEnd!)}' : ''}'),
              if (c.officialUrl != null) _Fact('Official link', c.officialUrl!),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Row(children: [
            const Icon(Icons.lock_clock_rounded, color: BearchColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Lobbies auto-lock at H-1 (${lockTimeLabel(c.deadline)}). Leaders can lock earlier. '
                'Locking registers the team, so there is no unlock.',
                style: t.bodySmall,
              ),
            ),
          ]),
        ),
        AsyncView<List<TeamView>>(
          loading: const Padding(padding: EdgeInsets.only(top: 20), child: SkeletonList(count: 2, avatar: true, chips: true)),
          value: teams,
          onRetry: () => ref.invalidate(competitionTeamsProvider(c.id)),
          data: (list) {
            final mine = list.where((tm) => tm.hasMember(me)).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('Lobbies · ${list.length}'),
                if (mine == null && !lockPassed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Open a lobby'),
                      onPressed: () async {
                        final id = await showCreateLobbySheet(context, c);
                        ref.invalidate(competitionTeamsProvider(c.id));
                        if (id != null && context.mounted) context.push('/lobby/$id');
                      },
                    ),
                  ),
                if (list.isEmpty)
                  const EmptyState(
                    icon: Icons.groups_rounded,
                    title: 'No lobbies yet',
                    message: 'Be the first: open a lobby and broadcast who you need.',
                  ),
                for (final (i, team) in list.indexed) ...[
                  Entrance(index: i, child: TeamCard(
                    team: team,
                    onTap: team.hasMember(me) ? () => context.push('/lobby/${team.id}') : null,
                    action: _teamAction(context, ref, team, mine, myRequests),
                  )),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget? _teamAction(BuildContext context, WidgetRef ref, TeamView team, TeamView? mine, List<JoinRequestView> req) {
    if (mine?.id == team.id) {
      return FilledButton.tonal(onPressed: () => context.push('/lobby/${team.id}'), child: const Text('Manage'));
    }
    if (team.isLocked || mine != null || team.openSlots <= 0) return null;
    if (req.any((r) => r.status == 'pending' && r.teamId == team.id)) {
      return const Pill('Requested', color: BearchColors.warning);
    }
    return FilledButton(
      onPressed: () async {
        final api = ref.read(bearchApiProvider);
        if (api == null) return;
        final msg = await promptText(context,
            title: 'Request to join ${team.name}', label: 'Message to the leader (optional)', confirmLabel: 'Send');
        if (msg == null || !context.mounted) return;
        final ok = await runAction(context, () => api.requestJoin(team.id, message: msg),
            success: team.approvalBased ? 'Request sent. The leader will review it.' : 'You joined ${team.name}!');
        if (ok) {
          ref.invalidate(myRequestsProvider);
          ref.invalidate(competitionTeamsProvider(competition.id));
        }
      },
      child: const Text('Request to join'),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: t.bodySmall)),
        Expanded(child: Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
