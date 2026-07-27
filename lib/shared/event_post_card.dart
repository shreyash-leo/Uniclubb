import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/supabase/uniclub_repository.dart';
import 'widgets.dart';

final savedEventStore = SavedEventStore();

class SavedEventStore extends ChangeNotifier {
  final repo = UniClubRepository();
  Set<String> _ids = {};
  String? _loadedUser;
  Future<void>? _loading;

  bool contains(String eventId) => _ids.contains(eventId);

  Future<void> ensureLoaded() {
    final userId = repo.userId;
    if (_loadedUser == userId && _loading == null) {
      return Future.value();
    }
    if (_loadedUser != userId) {
      _ids = {};
      _loadedUser = userId;
      _loading = null;
    }
    return _loading ??= repo.savedEventIds().then((ids) {
      _ids = ids;
      notifyListeners();
    }).whenComplete(() => _loading = null);
  }

  Future<bool> toggle(String eventId) async {
    await ensureLoaded();
    final shouldSave = !_ids.contains(eventId);
    if (shouldSave) {
      _ids.add(eventId);
    } else {
      _ids.remove(eventId);
    }
    notifyListeners();
    try {
      await repo.setEventSaved(eventId, shouldSave);
      return shouldSave;
    } catch (_) {
      if (shouldSave) {
        _ids.remove(eventId);
      } else {
        _ids.add(eventId);
      }
      notifyListeners();
      rethrow;
    }
  }
}

class EventPostCard extends StatefulWidget {
  const EventPostCard({
    super.key,
    required this.event,
    required this.onTap,
    this.status,
    this.headerTrailing,
    this.onSaveChanged,
  });

  final Map<String, dynamic> event;
  final VoidCallback onTap;
  final String? status;
  final Widget? headerTrailing;
  final VoidCallback? onSaveChanged;

  @override
  State<EventPostCard> createState() => _EventPostCardState();
}

class _EventPostCardState extends State<EventPostCard> {
  bool saving = false;

  @override
  void initState() {
    super.initState();
    savedEventStore.ensureLoaded().catchError((_) {});
  }

  Future<void> toggleSave() async {
    final eventId = '${widget.event['id'] ?? ''}';
    if (eventId.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      final saved = await savedEventStore.toggle(eventId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? 'Event saved' : 'Event removed from saved'),
          duration: const Duration(seconds: 1),
        ),
      );
      widget.onSaveChanged?.call();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void share() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EventShareSheet(event: widget.event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final club = event['clubs'] as Map<String, dynamic>? ?? const {};
    final type = '${event['event_type'] ?? 'event'}';
    final venue = '${event['venue_name'] ?? 'Venue to be announced'}';
    final eventId = '${event['id'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: NetworkPicture(
                url: club['logo_url'] as String?,
                width: 44,
                height: 44,
                borderRadius: 22,
              ),
              title: Text('${club['name'] ?? 'Campus'}'),
              subtitle: Text(
                '${_label(type)} · ${formatDate(event['starts_at'])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: widget.headerTrailing ??
                  (widget.status == null ? null : StatusChip(widget.status!)),
            ),
            NetworkPicture(
              url: event['flyer_url'] as String?,
              width: double.infinity,
              height: 280,
              borderRadius: 0,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event['title'] ?? _label(type)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule_outlined, size: 17),
                      const SizedBox(width: 6),
                      Expanded(child: Text(formatDate(event['starts_at']))),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 17),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if ('${event['description'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      '${event['description']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 10, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Share to chat',
                    onPressed: share,
                    icon: const Icon(Icons.send_outlined),
                  ),
                  AnimatedBuilder(
                    animation: savedEventStore,
                    builder: (context, _) {
                      final saved = savedEventStore.contains(eventId);
                      return IconButton(
                        tooltip: saved ? 'Remove from saved' : 'Save event',
                        onPressed: saving ? null : toggleSave,
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 19,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                saved ? Icons.bookmark : Icons.bookmark_border),
                      );
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onTap,
                    child: const Text('View details'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(String value) {
    if (value.isEmpty) return 'Event';
    return value
        .split('_')
        .map((part) =>
            part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _EventShareSheet extends StatefulWidget {
  const _EventShareSheet({required this.event});
  final Map<String, dynamic> event;

  @override
  State<_EventShareSheet> createState() => _EventShareSheetState();
}

class _EventShareSheetState extends State<_EventShareSheet> {
  final repo = UniClubRepository();
  final search = TextEditingController();
  late final Future<List<Map<String, dynamic>>> targets =
      repo.directShareTargets();
  final selected = <String>{};
  String query = '';
  bool sending = false;

  Future<void> send() async {
    if (selected.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await repo.shareEventToConversations(widget.event, selected);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Event shared to ${selected.length} conversation${selected.length == 1 ? '' : 's'}'),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void shareExternally() {
    final club = widget.event['clubs'] as Map? ?? const {};
    SharePlus.instance.share(
      ShareParams(
        text:
            '${widget.event['title']} · ${club['name'] ?? 'UniClub'} · ${formatDate(widget.event['starts_at'])}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Share event',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: search,
              onChanged: (value) => setState(() => query = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Search direct messages',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: targets,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AsyncErrorState(error: snapshot.error);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!
                    .where((row) =>
                        query.isEmpty ||
                        '${row['name']}'
                            .toLowerCase()
                            .contains(query.toLowerCase()))
                    .toList(growable: false);
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No direct chats found',
                    message:
                        'Start a direct chat with a club member, then share events here.',
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final id = '${row['conversation_id']}';
                    final checked = selected.contains(id);
                    return InkWell(
                      onTap: () => setState(
                        () => checked ? selected.remove(id) : selected.add(id),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              NetworkPicture(
                                url: row['avatar_url'] as String?,
                                width: 62,
                                height: 62,
                                borderRadius: 31,
                              ),
                              if (checked)
                                const Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: CircleAvatar(
                                    radius: 11,
                                    child: Icon(Icons.check, size: 15),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${row['name']}',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: shareExternally,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('More apps'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: selected.isEmpty || sending ? null : send,
                    child: Text(sending
                        ? 'Sending…'
                        : 'Send${selected.isEmpty ? '' : ' (${selected.length})'}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}
