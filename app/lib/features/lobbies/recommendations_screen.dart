import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import 'lobby_providers.dart';
import 'lobby_widgets.dart';
import 'skills_picker_sheet.dart';

typedef Recommendations = ({InferSkillsResult skills, List<Candidate> candidates});

/// Leader skills if set, else AI-inferred (cached per competition), then DB ranking.
final recommendationsProvider = FutureProvider.autoDispose.family<Recommendations, String>((ref, teamId) async {
  final api = ref.watch(bearchApiProvider)!;
  final skills = await api.inferSkills(teamId);
  final candidates = skills.fallback ? <Candidate>[] : await api.recommendCandidates(teamId);
  return (skills: skills, candidates: candidates);
});

/// Figma 07 · AI Teammate Recommendations.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const PageScaffold(title: 'Recommended', body: NeedsBackend());
    final recs = ref.watch(recommendationsProvider(teamId));
    return PageScaffold(
      title: 'Recommended teammates',
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(recommendationsProvider(teamId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            AsyncView<Recommendations>(
              loading: const SkeletonList(avatar: true, chips: true, caption: 'AI is reading the competition details and ranking candidates…'),
              value: recs,
              onRetry: () => ref.invalidate(recommendationsProvider(teamId)),
              data: (r) => _Body(teamId: teamId, recs: r),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.teamId, required this.recs});

  final String teamId;
  final Recommendations recs;

  Future<void> _setSkills(BuildContext context, WidgetRef ref) async {
    final api = ref.read(bearchApiProvider);
    final picked = await pickSkills(context, initial: {});
    if (api == null || picked == null || picked.isEmpty || !context.mounted) return;
    if (await runAction(context, () => api.setRequiredSkills(teamId, picked), success: 'Skills saved')) {
      ref.invalidate(teamProvider(teamId));
      ref.invalidate(recommendationsProvider(teamId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final s = recs.skills;
    if (s.fallback || s.skills.isEmpty) {
      return EmptyState(
        icon: Icons.psychology_alt_rounded,
        title: kSkillsNotSetMessage,
        message: 'Set the skills your team needs to get recommendations.',
        action: FilledButton(onPressed: () => _setSkills(context, ref), child: const Text('Set required skills')),
      );
    }
    final fromAi = s.source == 'ai';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(fromAi ? Icons.auto_awesome_rounded : Icons.checklist_rounded, color: BearchColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(fromAi ? 'Required skills inferred by AI' : 'Required skills set by the leader',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (fromAi) const Pill('Gemini · cached', color: BearchColors.purple),
            ]),
            const SizedBox(height: 10),
            SkillChips(s.skills),
            if (fromAi) ...[
              const SizedBox(height: 10),
              Text(
                'You haven\'t set required skills, so AI read the competition details once. '
                'Only competition details are sent to AI; ranking runs on Bearch\'s own database.',
                style: t.bodySmall,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _setSkills(context, ref), child: const Text('Edit skills')),
              ),
            ],
          ]),
        ),
        SectionLabel('Candidates · ${recs.candidates.length}'),
        if (recs.candidates.isEmpty)
          const EmptyState(
            icon: Icons.person_search_rounded,
            title: 'No matching students yet',
            message: 'Nobody available covers these skills right now. Try other skills or check back later.',
          ),
        for (final (i, c) in recs.candidates.indexed) ...[
          Entrance(index: i, child: _CandidateCard(teamId: teamId, candidate: c)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CandidateCard extends ConsumerWidget {
  const _CandidateCard({required this.teamId, required this.candidate});

  final String teamId;
  final Candidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = candidate;
    final api = ref.watch(bearchApiProvider);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(c.fullName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.fullName, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (c.majorName != null) Text(c.majorName!, style: t.bodySmall),
            ]),
          ),
          Pill('${c.matchScore}% match', color: c.matchScore >= 70 ? BearchColors.success : BearchColors.warning),
        ]),
        const SizedBox(height: 10),
        SkillChips(c.matchedSkills),
        const SizedBox(height: 10),
        Text('Why: ${c.reasons.join(' · ')}', style: t.bodySmall),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: c.pendingWithTeam
              ? const Pill('Pending', color: BearchColors.warning)
              : FilledButton.icon(
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Invite'),
                  onPressed: api == null
                      ? null
                      : () async {
                          final msg = await promptText(context,
                              title: 'Invite ${c.fullName}', label: 'Personal message (optional)', confirmLabel: 'Send invite');
                          if (msg == null || !context.mounted) return;
                          final ok = await runAction(
                            context,
                            () => api.sendInvite(teamId, c.profileId,
                                roleLabel: c.matchedSkills.isEmpty ? null : c.matchedSkills.take(2).join(' / '), message: msg),
                            success: 'Invite sent. Slot reserved for 48h.',
                          );
                          if (ok) {
                            ref.invalidate(recommendationsProvider(teamId));
                            ref.invalidate(teamInvitesProvider(teamId));
                          }
                        },
                ),
        ),
      ]),
    );
  }
}
