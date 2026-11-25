import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../lobbies/lobby_models.dart';
import 'rating_sheet.dart';
import 'sep_claim_section.dart';
import 'team_page.dart';

final canRateProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, teamId) async => await ref.watch(supabaseProvider)!.rpc('can_rate_team', params: {'p_team': teamId}) as bool,
);

/// Rate teammates & claim SEP for one locked team (opened from the team hub).
class RateClaimPage extends StatelessWidget {
  const RateClaimPage({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context) => TeamPage(teamId: teamId, title: 'Rate & SEP', builder: (team) => _RateClaim(team: team));
}

class _RateClaim extends ConsumerWidget {
  const _RateClaim({required this.team});

  final TeamView team;

  void _refresh(WidgetRef ref) {
    ref.invalidate(ratingProgressProvider(team.id));
    ref.invalidate(sepBlockersProvider(team.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () {
        _refresh(ref);
        ref.invalidate(sepClaimProvider(team.id));
        return ref.refresh(canRateProvider(team.id).future);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text('${team.name} · ${team.competitionName}', style: t.bodySmall),
        AsyncView<bool>(
          value: ref.watch(canRateProvider(team.id)),
          onRetry: () => ref.invalidate(canRateProvider(team.id)),
          data: (canRate) {
            if (!canRate) {
              return const Padding(
                padding: EdgeInsets.only(top: 12),
                child: EmptyState(
                  icon: Icons.hourglass_top_rounded,
                  title: 'Competition not finished yet',
                  message: 'Rating opens after the event ends. Then rate each teammate to unlock result upload & SEP claim.',
                ),
              );
            }
            return AsyncView<List<Teammate>>(
              value: ref.watch(ratingProgressProvider(team.id)),
              onRetry: () => ref.invalidate(ratingProgressProvider(team.id)),
              data: (mates) {
                final done = mates.where((m) => m.rated).length;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionLabel('1 · Rate teammates · $done of ${mates.length} rated'),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(children: [
                      for (final m in mates)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: InitialsAvatar(m.fullName, size: 36),
                          title: Text(m.fullName),
                          subtitle: m.roleLabel == null ? null : Text(m.roleLabel!),
                          trailing: m.rated
                              ? const Pill('Rated', color: BearchColors.success, icon: Icons.check_rounded)
                              : FilledButton.tonal(
                                  onPressed: () async {
                                    if (await showRatingSheet(context, team.id, m) == true) _refresh(ref);
                                  },
                                  child: const Text('Rate'),
                                ),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Didn\'t contribute? Use "Report a member" in the team hub instead.', style: t.bodySmall),
                  ),
                  const SectionLabel('2 · Upload result · 3 · SEP claim'),
                  SepClaimSection(teamId: team.id),
                ]);
              },
            );
          },
        ),
      ]),
    );
  }
}
