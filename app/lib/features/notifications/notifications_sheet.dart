import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_ui.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

typedef AppNotification = ({
  String id,
  String kind,
  String title,
  String body,
  Map<String, dynamic> data,
  bool read,
  DateTime createdAt,
});

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final uid = db?.auth.currentUser?.id;
  if (db == null || uid == null) return [];
  final rows = await db
      .from('notifications')
      .select('id, kind, title, body, data, read_at, created_at')
      .eq('profile_id', uid)
      .order('created_at', ascending: false)
      .limit(50);
  return [
    for (final r in rows)
      (
        id: r['id'] as String,
        kind: r['kind'] as String,
        title: r['title'] as String,
        body: (r['body'] as String?) ?? '',
        data: (r['data'] as Map<String, dynamic>?) ?? const {},
        read: r['read_at'] != null,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      ),
  ];
});

final unreadCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0,
);

/// Where a notification should take you.
String? _routeFor(AppNotification n) {
  final d = n.data;
  if (d['team_id'] != null && !n.kind.contains('disbanded')) return '/lobby/${d['team_id']}';
  if (d['invite_id'] != null) return '/invites';
  if (d['report_id'] != null) return '/reports';
  if (d['claim_id'] != null) return '/team/rate';
  if (n.kind.startsWith('competition_')) return n.kind == 'competition_submitted' ? '/admin/competitions' : '/submit';
  return null;
}

/// App-bar bell with unread badge.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _NotificationsSheet(),
      ).then((_) => ref.invalidate(notificationsProvider)),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  Future<void> _markRead(WidgetRef ref, {String? id}) async {
    final db = ref.read(supabaseProvider);
    if (db == null) return;
    final q = db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).isFilter('read_at', null);
    await (id == null ? q.eq('profile_id', db.auth.currentUser!.id) : q.eq('id', id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text('Notifications', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () async {
                  await _markRead(ref);
                  ref.invalidate(notificationsProvider);
                },
                child: const Text('Mark all read'),
              ),
            ]),
          ),
          Expanded(
            child: AsyncView<List<AppNotification>>(
              value: ref.watch(notificationsProvider),
              onRetry: () => ref.invalidate(notificationsProvider),
              data: (list) => list.isEmpty
                  ? Center(child: Text('You\'re all caught up.', style: t.bodyMedium))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = list[i];
                        final warn = n.kind == 'lock_warning' || n.kind.contains('rejected');
                        return ListTile(
                          leading: Icon(
                            warn ? Icons.notifications_active_rounded : Icons.notifications_rounded,
                            color: n.read ? Colors.grey : (warn ? BearchColors.warning : BearchColors.accent),
                          ),
                          title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                          subtitle: Text('${n.body}\n${formatDate(n.createdAt)}'),
                          isThreeLine: true,
                          onTap: () async {
                            await _markRead(ref, id: n.id);
                            final route = _routeFor(n);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            // Detail pages stack on top; drawer destinations replace (keeps shell title right).
                            if (route == null) return;
                            route.startsWith('/lobby/') ? context.push(route) : context.go(route);
                          },
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
