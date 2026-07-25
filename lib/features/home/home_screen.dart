import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../event/event_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final repo = UniClubRepository();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UniClub'),
              Text(
                'What’s happening on campus',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: const [NotificationAction()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Events'),
              Tab(text: 'Hackathons'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EventsFeed(
              repo: repo,
              types: const ['event', 'workshop', 'meetup'],
              showStories: true,
            ),
            _EventsFeed(
              repo: repo,
              types: const ['hackathon', 'competition'],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsFeed extends StatelessWidget {
  const _EventsFeed({
    required this.repo,
    required this.types,
    this.showStories = false,
  });

  final UniClubRepository repo;
  final List<String> types;
  final bool showStories;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repo.upcomingEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final rows = snapshot.data!
            .where((event) =>
                types.contains('${event['event_type']}') &&
                (DateTime.tryParse('${event['ends_at']}')?.isAfter(now) ??
                    true))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            children: [
              if (showStories) ...[
                const _StoryStrip(),
                const SizedBox(height: 10),
              ],
              if (rows.isEmpty)
                const SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Nothing scheduled yet',
                    message: 'Published campus events will appear here.',
                  ),
                )
              else
                ...rows.map((event) => _EventCard(event: event)),
            ],
          ),
        );
      },
    );
  }
}

class _StoryData {
  const _StoryData({required this.stories, required this.eligibleClubs});
  final List<Map<String, dynamic>> stories;
  final List<Map<String, dynamic>> eligibleClubs;
}

class _StoryStrip extends StatefulWidget {
  const _StoryStrip();

  @override
  State<_StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<_StoryStrip> {
  final repo = UniClubRepository();
  late Future<_StoryData> future = load();

  Future<_StoryData> load() async {
    final values = await Future.wait([
      repo.client
          .from('stories')
          .select('*, clubs(name, logo_url)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(40),
      repo.myMemberships(),
    ]);
    final memberships = List<Map<String, dynamic>>.from(values[1] as List);
    final eligible = memberships.where((membership) {
      final position = membership['club_positions'] as Map<String, dynamic>?;
      final permissions =
          List<String>.from(position?['permissions'] as List? ?? const []);
      return permissions.contains('all') ||
          permissions.contains('manage_social');
    }).toList(growable: false);
    return _StoryData(
      stories: List<Map<String, dynamic>>.from(values[0] as List),
      eligibleClubs: eligible,
    );
  }

  Future<void> create(List<Map<String, dynamic>> memberships) async {
    if (memberships.isEmpty) return;
    final club = memberships.length == 1
        ? memberships.first
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Post a story for'),
                    subtitle:
                        Text('Only authorized club officials can publish.'),
                  ),
                  ...memberships.map((membership) {
                    final club =
                        membership['clubs'] as Map<String, dynamic>? ?? {};
                    return ListTile(
                      leading: NetworkPicture(
                        url: club['logo_url'] as String?,
                        width: 42,
                        height: 42,
                        borderRadius: 21,
                      ),
                      title: Text('${club['name'] ?? 'Club'}'),
                      onTap: () => Navigator.pop(context, membership),
                    );
                  }),
                ],
              ),
            ),
          );
    if (club == null) return;
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (picked == null) return;
    try {
      final clubId = '${club['club_id']}';
      final url = await repo.upload(
        bucket: 'event-media',
        bytes: await picked.readAsBytes(),
        extension: picked.name.split('.').last.toLowerCase(),
        folder: 'stories/$clubId',
      );
      await repo.client.from('stories').insert({
        'author_id': repo.userId,
        'club_id': clubId,
        'media_url': url,
        'media_type': 'image',
      });
      if (mounted) setState(() => future = load());
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> view(List<Map<String, dynamic>> stories) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _StoryViewer(
          stories: stories,
          repo: repo,
          onDeleted: () {
            if (mounted) setState(() => future = load());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StoryData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            height: 104,
            child: Center(child: Text('Stories are unavailable right now.')),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 104,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        if (data.stories.isEmpty && data.eligibleClubs.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (data.eligibleClubs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: () => create(data.eligibleClubs),
                    borderRadius: BorderRadius.circular(40),
                    child: const SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            child: Icon(Icons.add_a_photo_outlined),
                          ),
                          SizedBox(height: 5),
                          Text('Add story',
                              maxLines: 1, style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ..._groupStories(data.stories).map((stories) {
                final story = stories.first;
                final club = story['clubs'] as Map<String, dynamic>? ?? {};
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: () => view(stories),
                    borderRadius: BorderRadius.circular(40),
                    child: SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                  colors: [Colors.deepPurple, Colors.orange]),
                            ),
                            child: NetworkPicture(
                              url: story['media_url'] as String?,
                              width: 56,
                              height: 56,
                              borderRadius: 28,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${club['name'] ?? 'Story'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  List<List<Map<String, dynamic>>> _groupStories(
      List<Map<String, dynamic>> rows) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final story in rows.reversed) {
      grouped.putIfAbsent('${story['club_id']}', () => []).add(story);
    }
    return grouped.values.toList().reversed.toList();
  }
}

class _StoryViewer extends StatefulWidget {
  const _StoryViewer(
      {required this.stories, required this.repo, required this.onDeleted});
  final List<Map<String, dynamic>> stories;
  final UniClubRepository repo;
  final VoidCallback onDeleted;

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  late final PageController pageController;
  late List<Map<String, dynamic>> stories = [...widget.stories];
  int index = 0;

  @override
  void initState() {
    super.initState();
    pageController = PageController();
    markViewed();
  }

  Future<void> markViewed() async {
    if (stories.isEmpty) return;
    try {
      await widget.repo.client.from('story_views').upsert(
        {'story_id': stories[index]['id'], 'viewer_id': widget.repo.userId},
        onConflict: 'story_id,viewer_id',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // Viewing must remain available if analytics recording is unavailable.
    }
  }

  Future<void> deleteCurrent() async {
    final story = stories[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete story?'),
        content: const Text('This story will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.client.from('stories').delete().eq('id', story['id']);
      widget.onDeleted();
      if (!mounted) return;
      setState(() {
        stories.removeAt(index);
        if (index >= stories.length) index = stories.length - 1;
      });
      if (stories.isEmpty) Navigator.pop(context);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const SizedBox.shrink();
    final story = stories[index];
    final club = story['clubs'] as Map? ?? const {};
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: pageController,
          itemCount: stories.length,
          onPageChanged: (value) {
            setState(() => index = value);
            markViewed();
          },
          itemBuilder: (_, page) => InteractiveViewer(
            child: NetworkPicture(
              url: stories[page]['media_url'] as String?,
              fit: BoxFit.contain,
              borderRadius: 0,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 18,
          child: Row(
            children: List.generate(
              stories.length,
              (value) => Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: value <= index ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 100,
          top: 42,
          child: Text(
            '${club['name'] ?? 'Club story'}  ${index + 1}/${stories.length}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        Positioned(
          top: 30,
          right: 8,
          child: Row(
            children: [
              if (story['author_id'] == widget.repo.userId)
                IconButton(
                  tooltip: 'Delete story',
                  onPressed: deleteCurrent,
                  color: Colors.white,
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                color: Colors.white,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => EventDetailScreen(event: event)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkPicture(
              url: event['flyer_url'] as String?,
              width: double.infinity,
              height: 194,
              borderRadius: 0,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusChip('${event['event_type'] ?? 'event'}'),
                      const Spacer(),
                      Text('${event['category'] ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('${event['title'] ?? 'Untitled'}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(formatDate(event['starts_at']))),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${event['venue_name'] ?? 'Venue to be announced'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
