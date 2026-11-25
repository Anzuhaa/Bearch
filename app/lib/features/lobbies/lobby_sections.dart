import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import 'lobby_models.dart';
import 'lobby_providers.dart';

/// Leader view: pending join requests with approve / decline.
class JoinRequestsSection extends ConsumerWidget {
  const JoinRequestsSection({super.key, required this.team, required this.onChanged});

  final TeamView team;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final api = ref.watch(bearchApiProvider);
    final requests = ref.watch(pendingRequestsProvider(team.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Join requests · ${requests.value?.length ?? '…'}'),
        AsyncView<List<JoinRequestView>>(
          value: requests,
          onRetry: () => ref.invalidate(pendingRequestsProvider(team.id)),
          data: (list) => list.isEmpty
              ? Text('No pending requests.', style: t.bodySmall)
              : Column(children: [
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            InitialsAvatar(r.fullName, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r.fullName, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                Text(
                                  [r.majorName, if (r.reputation != null) '★ ${r.reputation!.toStringAsFixed(1)} rep']
                                      .whereType<String>()
                                      .join(' · '),
                                  style: t.bodySmall,
                                ),
                              ]),
                            ),
                          ]),
                          if (r.message.isNotEmpty) ...[const SizedBox(height: 8), Text('“${r.message}”', style: t.bodyMedium)],
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            OutlinedButton(
                              onPressed: api == null ? null : () => _decide(context, api, r, false),
                              child: const Text('Decline'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: api == null ? null : () => _decide(context, api, r, true),
                              child: const Text('Approve'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                ]),
        ),
      ],
    );
  }

  Future<void> _decide(BuildContext context, BearchApi api, JoinRequestView r, bool approve) async {
    final ok = await runAction(
      context,
      () => api.decideJoinRequest(r.id, approve: approve),
      success: approve ? '${r.fullName} joined ${team.name}' : 'Request declined',
    );
    if (ok) onChanged();
  }
}

/// Leader view: direct invites still waiting (slot reserved 48h).
class PendingInvitesSection extends ConsumerWidget {
  const PendingInvitesSection({super.key, required this.team, required this.onChanged});

  final TeamView team;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(bearchApiProvider);
    final invites = ref.watch(teamInvitesProvider(team.id)).value ?? const <InviteView>[];
    if (invites.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Invites sent · ${invites.length}'),
        for (final i in invites)
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: InitialsAvatar(i.inviteeName, size: 36),
              title: Text(i.inviteeName),
              subtitle: Text('Slot reserved · expires in ${i.expiresAt.difference(DateTime.now()).inHours}h'),
              trailing: TextButton(
                style: TextButton.styleFrom(foregroundColor: BearchColors.danger),
                onPressed: api == null
                    ? null
                    : () async {
                        if (await runAction(context, () => api.cancelInvite(i.id), success: 'Invite cancelled')) {
                          onChanged();
                        }
                      },
                child: const Text('Cancel'),
              ),
            ),
          ),
      ],
    );
  }
}
