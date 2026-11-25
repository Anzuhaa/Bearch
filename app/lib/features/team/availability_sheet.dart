import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_ui.dart';
import '../../core/session.dart';

typedef Slot = ({String id, int weekday, String start, String end});

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

final mySlotsProvider = FutureProvider.autoDispose<List<Slot>>((ref) async {
  final db = ref.watch(supabaseProvider)!;
  final rows = await db
      .from('availability_slots')
      .select('id, weekday, start_time, end_time')
      .eq('profile_id', db.auth.currentUser!.id)
      .order('weekday')
      .order('start_time');
  String hm(Object? v) => (v as String).substring(0, 5);
  return [
    for (final r in rows)
      (id: r['id'] as String, weekday: (r['weekday'] as num).toInt(), start: hm(r['start_time']), end: hm(r['end_time'])),
  ];
});

/// "Edit my availability": weekly free slots (WIB), used by the team heatmap and matching.
Future<void> showAvailabilitySheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AvailabilitySheet(),
    );

class _AvailabilitySheet extends ConsumerWidget {
  const _AvailabilitySheet();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final db = ref.read(supabaseProvider);
    if (db == null) return;
    int day = 1;
    final pickedDay = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Day'),
        children: [for (var i = 0; i < 7; i++) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i + 1), child: Text(_days[i]))],
      ),
    );
    if (pickedDay == null || !context.mounted) return;
    day = pickedDay;
    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0), helpText: 'Free from');
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (start.hour + 2) % 24, minute: start.minute), helpText: 'Free until');
    if (end == null || !context.mounted) return;
    String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ok = await runAction(context, () async {
      await db.from('availability_slots').insert({
        'profile_id': db.auth.currentUser!.id,
        'weekday': day,
        'start_time': fmt(start),
        'end_time': fmt(end),
      });
    });
    if (ok) ref.invalidate(mySlotsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final db = ref.watch(supabaseProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('My weekly free time', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('Times are WIB. End must be after start.', style: t.bodySmall),
            Expanded(
              child: AsyncView<List<Slot>>(
                value: ref.watch(mySlotsProvider),
                onRetry: () => ref.invalidate(mySlotsProvider),
                data: (slots) => slots.isEmpty
                    ? Center(child: Text('No free slots yet.', style: t.bodyMedium))
                    : ListView(children: [
                        for (final s in slots)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_rounded),
                            title: Text('${_days[s.weekday - 1]} · ${s.start} – ${s.end}'),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: db == null
                                  ? null
                                  : () async {
                                      if (await runAction(context, () async {
                                        await db.from('availability_slots').delete().eq('id', s.id);
                                      })) {
                                        ref.invalidate(mySlotsProvider);
                                      }
                                    },
                            ),
                          ),
                      ]),
              ),
            ),
            FilledButton.icon(onPressed: () => _add(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Add free slot')),
          ]),
        ),
      ),
    );
  }
}
