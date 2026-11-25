import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import '../lobbies/lobby_models.dart';
import '../lobbies/lobby_providers.dart';

/// Drawer: Invites. Direct invites to me (48h) + my join requests.
class InvitesScreen extends ConsumerWidget {
  const InvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    final t = Theme.of(context).textTheme;
    final api = ref.watch(bearchApiProvider);
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(myRequestsProvider);
        return ref.refresh(myInvitesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionLabel('Invites for you'),
          AsyncView<List<InviteView>>(
            loading: const SkeletonList(count: 1, lines: 2),
            value: ref.watch(myInvitesProvider),
            onRetry: () => ref.invalidate(myInvitesProvider),
            data: (invites) => invites.isEmpty
                ? Text('No pending invites.', style: t.bodySmall)
                : Column(children: [
                    for (final i in invites)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(i.teamName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                              Pill('Expires in ${i.expiresAt.difference(DateTime.now()).inHours}h', color: BearchColors.warning),
                            ]),
                            Text(i.competitionName, style: t.bodySmall),
                            if (i.roleLabel != null) ...[const SizedBox(height: 6), Text('Role: ${i.roleLabel}', style: t.bodyMedium)],
                            if (i.message.isNotEmpty) ...[const SizedBox(height: 6), Text('“${i.message}”', style: t.bodyMedium)],
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              OutlinedButton(
                                onPressed: api == null ? null : () => _respond(context, ref, api, i, false),
                                child: const Text('Decline'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: api == null ? null : () => _respond(context, ref, api, i, true),
                                child: const Text('Accept'),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                  ]),
          ),
          const SectionLabel('My join requests'),
          AsyncView<List<JoinRequestView>>(
            loading: const SkeletonList(count: 2, lines: 0),
            value: ref.watch(myRequestsProvider),
            onRetry: () => ref.invalidate(myRequestsProvider),
            data: (reqs) => reqs.isEmpty
                ? Text('You haven\'t requested to join any lobby yet.', style: t.bodySmall)
                : GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(children: [
                      for (final r in reqs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.teamName ?? 'Lobby'),
                          subtitle: Text('${r.competitionName ?? ''} · ${formatDate(r.createdAt)}'),
                          trailing: r.status == 'pending' && api != null
                              ? TextButton(
                                  onPressed: () async {
                                    if (await runAction(context, () => api.cancelJoinRequest(r.id), success: 'Request cancelled')) {
                                      ref.invalidate(myRequestsProvider);
                                    }
                                  },
                                  child: const Text('Cancel'),
                                )
                              : _RequestStatus(r.status),
                        ),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _respond(BuildContext context, WidgetRef ref, BearchApi api, InviteView i, bool accept) async {
    final ok = await runAction(context, () => api.respondInvite(i.id, accept: accept),
        success: accept ? 'Welcome to ${i.teamName}!' : 'Invite declined');
    if (!ok) return;
    ref.invalidate(myInvitesProvider);
    ref.invalidate(myTeamsProvider);
    if (accept && context.mounted) context.push('/lobby/${i.teamId}');
  }
}

class _RequestStatus extends StatelessWidget {
  const _RequestStatus(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Approved', BearchColors.success),
      'declined' => ('Declined', BearchColors.danger),
      'auto_rejected' => ('Auto-rejected (team locked)', BearchColors.danger),
      'cancelled' => ('Cancelled', Colors.grey),
      _ => ('Pending', BearchColors.warning),
    };
    return Pill(label, color: color);
  }
}
