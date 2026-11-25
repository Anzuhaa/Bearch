import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/bearch_api.dart';

typedef SepClaim = ({String id, String status, String label, int? estimated, int? verified, String sync, String? note});

final sepClaimProvider = FutureProvider.autoDispose.family<SepClaim?, String>((ref, teamId) async {
  final r = await ref
      .watch(supabaseProvider)!
      .from('sep_claims')
      .select('id, status, placement_label, estimated_points, verified_points, uph_mobile_sync_status, review_note')
      .eq('team_id', teamId)
      .maybeSingle();
  if (r == null) return null;
  return (
    id: r['id'] as String,
    status: r['status'] as String,
    label: r['placement_label'] as String,
    estimated: (r['estimated_points'] as num?)?.toInt(),
    verified: (r['verified_points'] as num?)?.toInt(),
    sync: r['uph_mobile_sync_status'] as String,
    note: r['review_note'] as String?,
  );
});

final sepBlockersProvider = FutureProvider.autoDispose.family<List<String>, String>(
  (ref, teamId) => ref.watch(bearchApiProvider)!.sepClaimBlockers(teamId),
);

const _placements = {
  'winner_1': '🏆 1st Place',
  'winner_2': '🥈 2nd Place',
  'winner_3': '🥉 3rd Place',
  'finalist': 'Finalist',
  'participant': 'Participant',
};

/// Figma 13/14 · Upload winning result & claim SEP (gated by ratings + no open reports).
class SepClaimSection extends ConsumerStatefulWidget {
  const SepClaimSection({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<SepClaimSection> createState() => _SepClaimSectionState();
}

class _SepClaimSectionState extends ConsumerState<SepClaimSection> {
  String _placement = 'winner_1';
  final _url = TextEditingController();
  PlatformFile? _file;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit(BearchApi api) async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      final file = _file!;
      final bytes = await file.readAsBytes();
      final path = await api.uploadSepProof(widget.teamId, file.name, bytes);
      final claimId = await api.submitSepClaim(widget.teamId,
          placement: _placement, placementLabel: _placements[_placement]!, announcementUrl: _url.text.trim());
      await api.attachSepFile(claimId, path, file.name, bytes.length);
    }, success: 'Result submitted to Student Affairs');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(sepClaimProvider(widget.teamId));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final api = ref.watch(bearchApiProvider);
    return AsyncView<SepClaim?>(
      value: ref.watch(sepClaimProvider(widget.teamId)),
      onRetry: () => ref.invalidate(sepClaimProvider(widget.teamId)),
      data: (claim) {
        if (claim != null) return _ClaimStatus(claim);
        return AsyncView<List<String>>(
          value: ref.watch(sepBlockersProvider(widget.teamId)),
          onRetry: () => ref.invalidate(sepBlockersProvider(widget.teamId)),
          data: (blockers) => GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Upload result & claim SEP', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (blockers.isNotEmpty) ...[
                Text('Locked until:', style: t.bodySmall),
                for (final b in blockers)
                  Row(children: [
                    const Icon(Icons.lock_outline_rounded, size: 16, color: BearchColors.warning),
                    const SizedBox(width: 6),
                    Expanded(child: Text(b, style: t.bodyMedium)),
                  ]),
              ] else ...[
                const Pill('Unlocked · requirements met', color: BearchColors.success, icon: Icons.lock_open_rounded),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _placement,
                  decoration: const InputDecoration(labelText: 'Result / placement'),
                  items: [for (final e in _placements.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _placement = v ?? _placement),
                ),
                const SizedBox(height: 10),
                TextField(controller: _url, decoration: const InputDecoration(labelText: 'Announcement link (optional)')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_file?.name ?? 'Attach certificate / photo', overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final f = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp']);
                    if (f.isNotEmpty) setState(() => _file = f.first);
                  },
                ),
                const SizedBox(height: 8),
                FutureBuilder<int?>(
                  future: api?.sepEstimate(widget.teamId, _placement),
                  builder: (context, snap) => Text(
                    snap.data == null ? 'SEP estimate: —' : 'SEP estimate: +${snap.data} per member (confirmed by Student Affairs)',
                    style: t.bodySmall,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: api == null || _file == null || _busy ? null : () => _submit(api),
                  child: Text(_busy ? 'Submitting…' : 'Submit result & claim SEP'),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _ClaimStatus extends StatelessWidget {
  const _ClaimStatus(this.c);

  final SepClaim c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (label, color) = switch (c.status) {
      'verified' => ('Verified by Student Affairs', BearchColors.success),
      'rejected' => ('Rejected', BearchColors.danger),
      _ => ('Verifying certificate', BearchColors.warning),
    };
    final sync = switch (c.sync) {
      'pending' => 'Queued for UPH Mobile',
      'synced' => 'Synced to UPH Mobile',
      'failed' => 'UPH Mobile sync failed',
      _ => 'Not synced yet',
    };
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SEP claim · ${c.label}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Pill(label, color: color),
        const SizedBox(height: 8),
        Text(c.verified != null ? '+${c.verified} SEP per member' : 'Estimate: +${c.estimated ?? 0} SEP per member', style: t.bodyLarge),
        Text('UPH Mobile: $sync', style: t.bodySmall),
        if (c.note != null) Text('Note: ${c.note}', style: t.bodySmall),
      ]),
    );
  }
}
