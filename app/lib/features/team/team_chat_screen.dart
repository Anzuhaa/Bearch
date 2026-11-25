import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/async_ui.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../lobbies/lobby_models.dart';
import 'team_picker.dart';

typedef ChatMessage = ({String id, String? senderId, String body, bool isSystem, DateTime at});

/// Realtime messages for a team (RLS: members only).
final teamMessagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, teamId) {
  final db = ref.watch(supabaseProvider)!;
  return db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('team_id', teamId)
      .order('created_at', ascending: true)
      .map((rows) => [
            for (final r in rows)
              (
                id: r['id'] as String,
                senderId: r['sender_id'] as String?,
                body: (r['body'] as String?) ?? '',
                isSystem: (r['is_system'] as bool?) ?? false,
                at: DateTime.parse(r['created_at'] as String).toLocal(),
              ),
          ]);
});

/// Figma 11 · Team Chat.
class TeamChatScreen extends StatelessWidget {
  const TeamChatScreen({super.key});

  @override
  Widget build(BuildContext context) => TeamScope(builder: (team) => _Chat(team: team));
}

class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.team});

  final TeamView team;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final db = ref.read(supabaseProvider);
    final text = _input.text.trim();
    if (db == null || text.isEmpty) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      await db.from('messages').insert({'team_id': widget.team.id, 'sender_id': db.auth.currentUser!.id, 'body': text});
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = ref.watch(supabaseProvider)?.auth.currentUser?.id;
    final names = {for (final m in widget.team.members) m.profileId: m.fullName};
    final time = DateFormat('d MMM, HH:mm');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          '${widget.team.isLocked ? 'Locked team' : 'Lobby'} · ${widget.team.members.length} members · ${widget.team.competitionName}',
          style: t.bodySmall,
        ),
      ),
      Expanded(
        child: AsyncView<List<ChatMessage>>(
          loading: const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3, lines: 0, avatar: true)),
          value: ref.watch(teamMessagesProvider(widget.team.id)),
          onRetry: () => ref.invalidate(teamMessagesProvider(widget.team.id)),
          data: (msgs) => msgs.isEmpty
              ? Center(child: Text('Say hi to your team 👋', style: t.bodyMedium))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[msgs.length - 1 - i];
                    if (m.isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(child: Pill(m.body, color: Colors.blueGrey)),
                      );
                    }
                    final mine = m.senderId == me;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? BearchColors.accent : GlassTokens.of(context).fill,
                          borderRadius: BorderRadius.circular(16),
                          border: mine ? null : Border.all(color: GlassTokens.of(context).border),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!mine)
                            Text(names[m.senderId] ?? 'Former member',
                                style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: BearchColors.accent)),
                          Text(m.body, style: t.bodyMedium?.copyWith(color: mine ? Colors.white : null)),
                          Text(time.format(m.at),
                              style: t.labelSmall?.copyWith(color: mine ? Colors.white70 : null, fontSize: 10)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: 'Message ${widget.team.name}…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }
}
