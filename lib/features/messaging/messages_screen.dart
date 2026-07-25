import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final repo = UniClubRepository();

  Future<List<Map<String, dynamic>>> conversations() async =>
      List<Map<String, dynamic>>.from(await repo.client
          .from('conversation_members')
          .select('*, conversations(*)')
          .eq('user_id', repo.userId)
          .order('joined_at', ascending: false));

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
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              message: 'Start a conversation with someone from your campus.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final conversation = Map<String, dynamic>.from(
                snapshot.data![index]['conversations'] as Map);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(switch (conversation['kind']) {
                    'club' => Icons.groups_outlined,
                    'event' => Icons.event_outlined,
                    _ => Icons.person_outline,
                  }),
                ),
                title: Text(
                    '${conversation['title'] ?? _kind(conversation['kind'])}'),
                subtitle: Text(_kind(conversation['kind'])),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(
                      conversationId: '${conversation['id']}',
                      title:
                          '${conversation['title'] ?? _kind(conversation['kind'])}',
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton(
          heroTag: 'messages-compose',
          onPressed: startDirect,
          child: const Icon(Icons.edit_outlined)),
      body: content,
    );
  }

  static String _kind(dynamic value) =>
      '${value ?? 'conversation'}'.replaceAll('_', ' ');
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
      final rows = await widget.repo.globalSearch(value);
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
  bool sending = false;

  Future<void> send() async {
    final body = controller.text.trim();
    if (body.isEmpty || sending) return;
    setState(() => sending = true);
    controller.clear();
    try {
      await repo.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': repo.userId,
        'body': body,
      });
    } catch (error) {
      controller.text = body;
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
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
              stream: repo.client
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('conversation_id', widget.conversationId)
                  .order('created_at'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AsyncErrorState(error: snapshot.error);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (_, index) {
                    final row = snapshot.data![index];
                    final mine = row['sender_id'] == repo.userId;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 340),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('${row['body'] ?? ''}'),
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
                    onSubmitted: (_) => send(),
                    decoration:
                        const InputDecoration(hintText: 'Write a message…'),
                  )),
                  IconButton(
                    onPressed: sending ? null : send,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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
    super.dispose();
  }
}
