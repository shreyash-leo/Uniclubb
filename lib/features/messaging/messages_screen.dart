import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';
import '../event/event_detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final repo = UniClubRepository();
  String filter = 'all';

  Future<List<Map<String, dynamic>>> conversations() async {
    final rows = List<Map<String, dynamic>>.from(await repo.client
        .from('conversation_members')
        .select(
          '*, conversations(*, clubs(name,logo_url), '
          'messages(body,created_at,sender_id,attachment), '
          'conversation_members!conversation_members_conversation_id_fkey('
          'user_id, profiles!conversation_members_user_id_fkey('
          'full_name,avatar_url)))',
        )
        .eq('user_id', repo.userId)
        .order('joined_at', ascending: false));
    final allowedDirectUsers = await repo.sharedClubMemberIds();
    return rows.where((row) {
      final conversation = row['conversations'] as Map? ?? const {};
      if (conversation['kind'] != 'direct') return true;
      final members = conversation['conversation_members'] as List? ?? const [];
      return members.any((value) {
        final member = value as Map? ?? const {};
        final id = '${member['user_id']}';
        return id != repo.userId && allowedDirectUsers.contains(id);
      });
    }).toList(growable: false);
  }

  Future<void> startDirect() async {
    final target = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewMessageDialog(repo: repo),
    );
    if (target == null) return;
    try {
      final conversation = await repo.directConversation('${target['id']}');
      if (!mounted) return;
      setState(() {});
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(
            conversationId: '${conversation['id']}',
            title: '${target['title']}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> openFilter() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Filter chats'),
              subtitle: Text('Choose which conversations to show'),
            ),
            RadioGroup<String>(
              groupValue: filter,
              onChanged: (value) => Navigator.pop(context, value),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'all',
                    title: Text('All chats'),
                    secondary: Icon(Icons.forum_outlined),
                  ),
                  RadioListTile<String>(
                    value: 'unread',
                    title: Text('Unread'),
                    secondary: Icon(Icons.mark_chat_unread_outlined),
                  ),
                  RadioListTile<String>(
                    value: 'muted',
                    title: Text('Muted'),
                    secondary: Icon(Icons.notifications_off_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) {
      setState(() => filter = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<List<Map<String, dynamic>>>(
      future: conversations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return TabBarView(
          children: [
            _conversationList(
              snapshot.data!,
              kind: 'direct',
              emptyTitle: 'No direct messages',
              emptyMessage:
                  'Message a member from one of your clubs to get started.',
            ),
            _conversationList(
              snapshot.data!,
              kind: 'club',
              emptyTitle: 'No club chats',
              emptyMessage: 'Club chats appear when you become a member.',
            ),
          ],
        );
      },
    );
    final tabs = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: const [
        Tab(height: 40, text: 'Direct'),
        Tab(height: 40, text: 'Club chats'),
      ],
    );
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(child: tabs),
          const SizedBox(width: 8),
          ActionChip(
            avatar: Icon(
              filter == 'all' ? Icons.filter_list : Icons.filter_alt,
              size: 17,
            ),
            label: Text(switch (filter) {
              'unread' => 'Unread',
              'muted' => 'Muted',
              _ => 'Filter',
            }),
            onPressed: openFilter,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('Messages')),
        floatingActionButton: FloatingActionButton.extended(
            heroTag: 'messages-compose',
            onPressed: startDirect,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('New message')),
        body: widget.embedded
            ? Column(
                children: [
                  controls,
                  Expanded(child: content),
                ],
              )
            : Column(
                children: [
                  controls,
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }

  Widget _conversationList(
    List<Map<String, dynamic>> rows, {
    required String kind,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    final filtered = rows.where((row) {
      final conversation = row['conversations'] as Map? ?? const {};
      if (conversation['kind'] != kind) return false;
      if (filter == 'muted') return row['muted'] == true;
      if (filter == 'unread') return _isUnread(row, conversation);
      return true;
    }).toList(growable: false);
    if (filtered.isEmpty) {
      return EmptyState(
        icon: kind == 'direct' ? Icons.person_outline : Icons.groups_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final conversation =
            Map<String, dynamic>.from(filtered[index]['conversations'] as Map);
        final peer = _directPeer(conversation);
        final title = kind == 'direct'
            ? '${peer?['full_name'] ?? 'Club member'}'
            : '${_club(conversation)?['name'] ?? conversation['title'] ?? _kind(conversation['kind'])}';
        final latest = _latestMessage(conversation);
        final unread = _isUnread(filtered[index], conversation);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: kind == 'direct'
                ? NetworkPicture(
                    url: peer?['avatar_url'] as String?,
                    width: 44,
                    height: 44,
                    borderRadius: 22,
                  )
                : NetworkPicture(
                    url: _club(conversation)?['logo_url'] as String?,
                    width: 44,
                    height: 44,
                    borderRadius: 22,
                  ),
            title: Text(title),
            subtitle: Text(
              latest == null
                  ? (kind == 'club' ? 'Club chat' : 'Start a conversation')
                  : latest['attachment'] is Map &&
                          (latest['attachment'] as Map)['type'] == 'event'
                      ? 'Shared an event'
                      : '${latest['body'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (latest != null)
                  Text(
                    _messageTime(latest['created_at']),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                const SizedBox(height: 4),
                if (unread)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else if (filtered[index]['muted'] == true)
                  const Icon(Icons.notifications_off_outlined, size: 16),
              ],
            ),
            onTap: () async {
              await repo.client
                  .from('conversation_members')
                  .update({'last_read_at': DateTime.now().toIso8601String()})
                  .eq('conversation_id', conversation['id'])
                  .eq('user_id', repo.userId);
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ConversationScreen(
                    conversationId: '${conversation['id']}',
                    title: title,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        );
      },
    );
  }

  static String _kind(dynamic value) =>
      '${value ?? 'conversation'}'.replaceAll('_', ' ');

  Map<String, dynamic>? _directPeer(Map<dynamic, dynamic> conversation) {
    final members = conversation['conversation_members'] as List? ?? const [];
    for (final value in members) {
      final member = value as Map? ?? const {};
      if ('${member['user_id']}' == repo.userId) continue;
      return Map<String, dynamic>.from(member['profiles'] as Map? ?? {});
    }
    return null;
  }

  Map<String, dynamic>? _club(Map<dynamic, dynamic> conversation) {
    final value = conversation['clubs'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  bool _isUnread(
      Map<String, dynamic> membership, Map<dynamic, dynamic> conversation) {
    final latestMessage = _latestMessage(conversation);
    final latest = DateTime.tryParse('${latestMessage?['created_at']}');
    if (latest == null) return false;
    final lastRead = DateTime.tryParse('${membership['last_read_at']}');
    return lastRead == null || latest.isAfter(lastRead);
  }

  Map<String, dynamic>? _latestMessage(Map<dynamic, dynamic> conversation) {
    final messages = conversation['messages'] as List? ?? const [];
    Map<String, dynamic>? latest;
    for (final value in messages) {
      final message = Map<String, dynamic>.from(value as Map);
      if (latest == null ||
          '${message['created_at']}'.compareTo('${latest['created_at']}') > 0) {
        latest = message;
      }
    }
    return latest;
  }
}

class _NewMessageDialog extends StatefulWidget {
  const _NewMessageDialog({required this.repo});

  final UniClubRepository repo;

  @override
  State<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends State<_NewMessageDialog> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  int request = 0;

  Future<void> search(String value) async {
    final currentRequest = ++request;
    if (value.trim().length < 2) {
      setState(() => results = []);
      return;
    }
    setState(() => loading = true);
    try {
      final rows = await widget.repo.clubPeopleSearch(value);
      if (!mounted || currentRequest != request) return;
      setState(() => results =
          rows.where((row) => row['kind'] == 'user').toList(growable: false));
    } finally {
      if (mounted && currentRequest == request) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search people…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: search,
            ),
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('Type at least two characters'))
                  : ListView(
                      children: results
                          .map((row) => ListTile(
                                leading: NetworkPicture(
                                    url: row['image_url'] as String?,
                                    width: 42,
                                    height: 42,
                                    borderRadius: 21),
                                title: Text('${row['title']}'),
                                subtitle: Text('${row['subtitle'] ?? ''}'),
                                onTap: () => Navigator.pop(context, row),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen(
      {super.key, required this.conversationId, required this.title});
  final String conversationId;
  final String title;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final repo = UniClubRepository();
  final controller = TextEditingController();
  final scrollController = ScrollController();
  late final Stream<List<Map<String, dynamic>>> messageStream;
  bool sending = false;
  int visibleMessages = 0;

  @override
  void initState() {
    super.initState();
    messageStream = repo.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at');
  }

  Future<void> send() async {
    final body = controller.text.trim();
    if (body.isEmpty || sending) return;
    setState(() => sending = true);
    controller.clear();
    try {
      await repo.sendMessage(
        conversationId: widget.conversationId,
        body: body,
      );
    } catch (error) {
      controller.text = body;
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> openSharedEvent(Map<String, dynamic> attachment) async {
    try {
      final event = Map<String, dynamic>.from(await repo.client
          .from('events')
          .select('*, clubs(name,logo_url,college_id)')
          .eq('id', attachment['event_id'])
          .single());
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(event: event),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AsyncErrorState(error: snapshot.error);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = uniqueMessagesById(snapshot.data!);
                if (messages.length != visibleMessages) {
                  visibleMessages = messages.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !scrollController.hasClients) return;
                    scrollController.animateTo(
                      scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  });
                }
                return ListView.builder(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  itemBuilder: (_, index) {
                    final row = messages[index];
                    final mine = row['sender_id'] == repo.userId;
                    final attachment = row['attachment'] is Map
                        ? Map<String, dynamic>.from(row['attachment'] as Map)
                        : null;
                    final sharedEvent =
                        attachment?['type'] == 'event' ? attachment : null;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 340),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(mine ? 20 : 6),
                            bottomRight: Radius.circular(mine ? 6 : 20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (sharedEvent != null)
                              _SharedEventMessage(
                                attachment: sharedEvent,
                                textColor: mine
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                                onTap: () => openSharedEvent(sharedEvent),
                              )
                            else
                              Text(
                                '${row['body'] ?? ''}',
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              _messageTime(row['created_at']),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: mine
                                        ? Colors.white70
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                      child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => send(),
                    decoration:
                        const InputDecoration(hintText: 'Write a message…'),
                  )),
                  IconButton.filled(
                    onPressed: sending ? null : send,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

class _SharedEventMessage extends StatelessWidget {
  const _SharedEventMessage({
    required this.attachment,
    required this.textColor,
    required this.onTap,
  });

  final Map<String, dynamic> attachment;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: NetworkPicture(
                url: attachment['flyer_url'] as String?,
                width: 250,
                height: double.infinity,
                borderRadius: 12,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              '${attachment['title'] ?? 'Campus event'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: textColor),
            ),
            const SizedBox(height: 3),
            Text(
              '${attachment['club_name'] ?? 'UniClub'} · ${formatDate(attachment['starts_at'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: textColor.withValues(alpha: .8)),
            ),
            const SizedBox(height: 5),
            Text(
              '${attachment['venue_name'] ?? 'Venue to be announced'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: textColor.withValues(alpha: .8)),
            ),
          ],
        ),
      ),
    );
  }
}

String _messageTime(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:${date.minute.toString().padLeft(2, '0')} '
      '${date.hour >= 12 ? 'PM' : 'AM'}';
}

List<Map<String, dynamic>> uniqueMessagesById(
  List<Map<String, dynamic>> rows,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final id = row['id'];
    if (id == null) continue;
    byId['$id'] = row;
  }
  final result = byId.values.toList();
  result.sort((a, b) =>
      '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}'));
  return result;
}
