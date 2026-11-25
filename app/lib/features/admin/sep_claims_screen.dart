import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';
import '../reports/reports_screen.dart' show Json;
import 'admin_dashboard_screen.dart';

final adminSepClaimsProvider = FutureProvider.autoDispose<List<Json>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)!
      .from('sep_claims')
      .select('id, placement_label, announcement_url, estimated_points, verified_points, status, uph_mobile_sync_status, created_at, '
          'teams(name, competitions(name, level), team_members(count)), sep_claim_files(file_name)')
      .order('created_at', ascending: false);
  rows.sort((a, b) => (a['status'] == 'submitted' ? 0 : 1).compareTo(b['status'] == 'submitted' ? 0 : 1));
  return rows;
});

/// Admin: verify SEP claims (certificate + points) before they go to UPH Mobile.
class SepClaimsScreen extends ConsumerWidget {
  const SepClaimsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseProvider) == null) return const NeedsBackend();
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminSepClaimsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AsyncView<List<Json>>(
          value: ref.watch(adminSepClaimsProvider),
          onRetry: () => ref.invalidate(adminSepClaimsProvider),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.verified_outlined, title: 'No SEP claims', message: 'Nothing to verify.')
              : Column(children: [for (final c in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Claim(c))]),
        ),
      ]),
    );
  }
}

class _Claim extends ConsumerWidget {
  const _Claim(this.c);

  final Json c;

  Future<void> _verify(BuildContext context, WidgetRef ref, bool approve) async {
    final api = ref.read(bearchApiProvider);
    if (api == null) return;
    int? points;
    String? note;
    if (approve) {
      final input = await promptText(context,
          title: 'Verify & credit SEP', label: 'Points per member (estimate ${c['estimated_points'] ?? 0})', confirmLabel: 'Verify');
      if (input == null) return;
      points = int.tryParse(input) ?? (c['estimated_points'] as num?)?.toInt();
    } else {
      note = await promptText(context, title: 'Reject claim', label: 'Reason', confirmLabel: 'Reject', minLength: 5);
      if (note == null) return;
    }
    if (!context.mounted) return;
    final ok = await runAction(context, () => api.adminVerifySepClaim(c['id'] as String, approve: approve, points: points, note: note),
        success: approve ? 'SEP verified · queued for UPH Mobile' : 'Claim rejected');
    if (ok) {
      ref.invalidate(adminSepClaimsProvider);
      ref.invalidate(adminStatsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final team = c['teams'] as Json?;
    final comp = team?['competitions'] as Json?;
    final members = ((team?['team_members'] as List?)?.firstOrNull as Json?)?['count'] ?? '?';
    final files = [for (final f in (c['sep_claim_files'] as List? ?? const [])) (f as Json)['file_name']];
    final status = c['status'] as String;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(team?['name'] as String? ?? '—', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          Pill(
            switch (status) { 'verified' => 'Verified', 'rejected' => 'Rejected', _ => 'To verify' },
            color: switch (status) { 'verified' => BearchColors.success, 'rejected' => BearchColors.danger, _ => BearchColors.warning },
          ),
        ]),
        Text('${c['placement_label']} · ${comp?['name'] ?? ''} · $members members', style: t.bodySmall),
        const SizedBox(height: 6),
        Text('Proof: ${files.isEmpty ? 'none' : files.join(', ')}', style: t.bodySmall),
        if (c['announcement_url'] != null) Text('Announcement: ${c['announcement_url']}', style: t.bodySmall),
        Text(
          status == 'verified'
              ? '+${c['verified_points']} SEP per member · UPH Mobile: ${c['uph_mobile_sync_status']}'
              : 'Estimate: +${c['estimated_points'] ?? 0} SEP per member',
          style: t.bodyMedium,
        ),
        if (status == 'submitted') ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => _verify(context, ref, false), child: const Text('Reject')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _verify(context, ref, true), child: const Text('Verify & push to UPH Mobile')),
          ]),
        ],
      ]),
    );
  }
}
