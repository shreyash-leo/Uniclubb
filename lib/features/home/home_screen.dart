import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/event_post_card.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../club/clubs_hub_screen.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UniClub'),
            Text(
              'Your campus feed',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: const [NotificationAction()],
      ),
      body: _HomeFeed(repo: repo),
    );
  }
}

class _FeedData {
  const _FeedData({required this.posts, required this.events});
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> events;
}

class _FeedEntry {
  const _FeedEntry.post(this.value) : isEvent = false;
  const _FeedEntry.event(this.value) : isEvent = true;
  final Map<String, dynamic> value;
  final bool isEvent;
}

class _HomeFeed extends StatefulWidget {
  const _HomeFeed({required this.repo});
  final UniClubRepository repo;

  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  late Future<_FeedData> future = load();

  Future<_FeedData> load() async {
    final values = await Future.wait<dynamic>([
      widget.repo.homeFeedPosts(),
      widget.repo.recommendedEvents(limit: 30),
    ]);
    return _FeedData(
      posts: List<Map<String, dynamic>>.from(values[0] as List),
      events: List<Map<String, dynamic>>.from(values[1] as List),
    );
  }

  List<_FeedEntry> mixedFeed(_FeedData data) {
    final posts = [...data.posts];
    final events = [...data.events];
    final result = <_FeedEntry>[];
    var postIndex = 0;
    var eventIndex = 0;
    while (postIndex < posts.length || eventIndex < events.length) {
      for (var count = 0; count < 3 && postIndex < posts.length; count++) {
        result.add(_FeedEntry.post(posts[postIndex++]));
      }
      if (eventIndex < events.length) {
        result.add(_FeedEntry.event(events[eventIndex++]));
      }
      if (postIndex >= posts.length) {
        while (eventIndex < events.length) {
          result.add(_FeedEntry.event(events[eventIndex++]));
        }
      }
    }
    return result;
  }

  Future<void> refresh() async {
    final next = load();
    setState(() {
      future = next;
    });
    await next;
  }

  Future<void> toggleLike(Map<String, dynamic> post) async {
    final originalLikes = List<Map<String, dynamic>>.from(
        post['post_likes'] as List? ?? const []);
    final liked =
        originalLikes.any((row) => row['user_id'] == widget.repo.userId);
    final updatedLikes = List<Map<String, dynamic>>.from(originalLikes);
    if (liked) {
      updatedLikes.removeWhere((row) => row['user_id'] == widget.repo.userId);
    } else {
      updatedLikes.add({'user_id': widget.repo.userId});
    }
    setState(() => post['post_likes'] = updatedLikes);
    try {
      await widget.repo.setPostLiked('${post['id']}', !liked);
    } catch (error) {
      if (!mounted) return;
      setState(() => post['post_likes'] = originalLikes);
      showErrorSnackBar(context, error);
    }
  }

  Future<void> comment(Map<String, dynamic> post) async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Add a comment…'),
                onSubmitted: (text) => Navigator.pop(context, text.trim()),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
    await disposeTextControllersAfterRoute([controller]);
    if (value == null || value.isEmpty) return;
    try {
      await widget.repo.client.from('post_comments').insert({
        'post_id': post['id'],
        'author_id': widget.repo.userId,
        'body': value,
      });
      if (mounted) await refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FeedData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error, onRetry: refresh);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        final feed = mixedFeed(snapshot.data!);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            children: [
              const _StoryStrip(),
              const SizedBox(height: 12),
              if (feed.isEmpty)
                _HomeEventFallback(repo: widget.repo)
              else
                ...feed.map((entry) {
                  if (entry.isEvent) {
                    return EventPostCard(
                      event: entry.value,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => EventDetailScreen(event: entry.value),
                        ),
                      ),
                    );
                  }
                  return _PostCard(
                    post: entry.value,
                    currentUserId: widget.repo.userId,
                    onLike: () => toggleLike(entry.value),
                    onComment: () => comment(entry.value),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

/*
 * Feed ranking is intentionally kept server/data driven in the repository:
 * followed clubs receive priority, trending campus posts are interleaved, and
 * upcoming campus events ensure the feed remains useful for new users.
 */

class _HomeEventFallback extends StatelessWidget {
  const _HomeEventFallback({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        repo.recommendedEvents(limit: 6),
        repo.discoverClubs(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final events =
            List<Map<String, dynamic>>.from(snapshot.data![0] as List);
        final clubs =
            List<Map<String, dynamic>>.from(snapshot.data![1] as List);
        if (events.isEmpty && clubs.isEmpty) {
          return const SizedBox(
            height: 280,
            child: EmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: 'Your campus feed is quiet',
              message: 'Create or follow a club to start your campus feed.',
            ),
          );
        }
        if (events.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Popular clubs on campus'),
              const SizedBox(height: 8),
              ...clubs.take(6).map((club) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: NetworkPicture(
                        url: club['logo_url'] as String?,
                        width: 52,
                        height: 52,
                        borderRadius: 15,
                      ),
                      title: Text('${club['name']}'),
                      subtitle: Text(
                          '${club['category']} · ${club['location'] ?? 'Campus'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ClubDiscoverDetailScreen(club: club),
                        ),
                      ),
                    ),
                  )),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Recommended near you'),
            const SizedBox(height: 8),
            ...events.map((event) {
              final club = event['clubs'] as Map<String, dynamic>? ?? const {};
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: NetworkPicture(
                    url: event['flyer_url'] as String?,
                    width: 56,
                    height: 56,
                    borderRadius: 12,
                  ),
                  title: Text('${event['title']}'),
                  subtitle: Text(
                      '${club['name'] ?? 'Campus'} · ${formatDate(event['starts_at'])}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => EventDetailScreen(event: event),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
  });
  final Map<String, dynamic> post;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    final profile = post['profiles'] as Map<String, dynamic>? ?? const {};
    final club = post['clubs'] as Map<String, dynamic>? ?? const {};
    final likes = List<Map<String, dynamic>>.from(
        post['post_likes'] as List? ?? const []);
    final comments = (post['post_comments'] as List?)?.length ?? 0;
    final liked = likes.any((row) => row['user_id'] == currentUserId);
    final media = post['media'] as List? ?? const [];
    final firstMedia = media.isEmpty
        ? null
        : Map<String, dynamic>.from(media.first as Map? ?? const {});
    final mediaUrl =
        firstMedia?['url'] as String? ?? firstMedia?['media_url'] as String?;
    final source =
        '${post['feed_source']}' == 'following' ? 'Following' : 'Trending';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: NetworkPicture(
              url: (club['logo_url'] ?? profile['avatar_url']) as String?,
              width: 44,
              height: 44,
              borderRadius: 22,
            ),
            title: Text('${club['name'] ?? profile['full_name'] ?? 'Campus'}'),
            subtitle: Text(
              '$source · ${formatDate(post['created_at'])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mediaUrl != null)
            AspectRatio(
              aspectRatio: 4 / 5,
              child: NetworkPicture(
                url: mediaUrl,
                width: double.infinity,
                height: double.infinity,
                borderRadius: 0,
              ),
            ),
          if ('${post['body'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('${post['body']}'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: liked ? 'Unlike' : 'Like',
                  onPressed: onLike,
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                Text('${likes.length}'),
                IconButton(
                  tooltip: 'Comment',
                  onPressed: onComment,
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
                Text('$comments'),
                const Spacer(),
                IconButton(
                  tooltip: 'Share',
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          '${club['name'] ?? profile['full_name'] ?? 'UniClub'}: ${post['body'] ?? ''}',
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final values = await Future.wait<dynamic>([
      repo.profile(),
      repo.client
          .from('stories')
          .select('*, clubs(name, logo_url, college_id)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(40),
      repo.myMemberships(),
    ]);
    final profile =
        values[0] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final collegeId = profile['college_id'];
    final stories =
        List<Map<String, dynamic>>.from(values[1] as List).where((story) {
      if (collegeId == null) return true;
      final club = story['clubs'] as Map? ?? const {};
      return club['college_id'] == collegeId;
    }).toList(growable: false);
    final memberships = List<Map<String, dynamic>>.from(values[2] as List);
    final eligible = memberships.where((membership) {
      final position = membership['club_positions'] as Map<String, dynamic>?;
      final permissions =
          List<String>.from(position?['permissions'] as List? ?? const []);
      return permissions.contains('all') ||
          permissions.contains('manage_social');
    }).toList(growable: false);
    return _StoryData(
      stories: stories,
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
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final captionController = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                    ),
                    const Expanded(
                      child: Text(
                        'Story preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, captionController.text.trim()),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Image.memory(
                    bytes,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 14,
                ),
                child: TextField(
                  controller: captionController,
                  maxLength: 180,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Write a caption…',
                    hintStyle: const TextStyle(color: Colors.white70),
                    counterStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await disposeTextControllersAfterRoute([captionController]);
    if (caption == null) return;
    try {
      final clubId = '${club['club_id']}';
      final url = await repo.upload(
        bucket: 'event-media',
        bytes: bytes,
        extension: picked.name.split('.').last.toLowerCase(),
        folder: 'stories/$clubId',
      );
      await repo.client.from('stories').insert({
        'author_id': repo.userId,
        'club_id': clubId,
        'media_url': url,
        'media_type': 'image',
        'caption': caption.isEmpty ? null : caption,
      });
      if (mounted) {
        final next = load();
        setState(() {
          future = next;
        });
      }
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
            if (mounted) {
              final next = load();
              setState(() {
                future = next;
              });
            }
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

class _StoryViewerState extends State<_StoryViewer>
    with SingleTickerProviderStateMixin {
  late final PageController pageController;
  late final AnimationController progressController;
  late List<Map<String, dynamic>> stories = [...widget.stories];
  int index = 0;

  @override
  void initState() {
    super.initState();
    pageController = PageController();
    progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) next();
      });
    markViewed();
    progressController.forward();
  }

  void restartProgress() {
    progressController
      ..stop()
      ..value = 0
      ..forward();
  }

  void next() {
    if (!mounted || stories.isEmpty) return;
    if (index < stories.length - 1) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void previous() {
    if (!mounted || stories.isEmpty) return;
    if (index > 0) {
      pageController.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      restartProgress();
    }
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
    progressController.stop();
    try {
      final deleted = await widget.repo.client
          .from('stories')
          .delete()
          .eq('id', story['id'])
          .select('id')
          .maybeSingle();
      if (deleted == null) {
        throw StateError('The story could not be deleted.');
      }
      final mediaUrl = '${story['media_url'] ?? ''}';
      const storageMarker = '/storage/v1/object/public/event-media/';
      final markerIndex = mediaUrl.indexOf(storageMarker);
      if (markerIndex >= 0) {
        final path = Uri.decodeComponent(
            mediaUrl.substring(markerIndex + storageMarker.length));
        try {
          await widget.repo.client.storage.from('event-media').remove([path]);
        } catch (_) {
          // The database row is authoritative. Storage cleanup can be retried
          // independently if the object was already missing or unavailable.
        }
      }
      if (!mounted) return;
      final shouldClose = stories.length == 1;
      if (shouldClose) {
        stories.clear();
      } else {
        setState(() {
          stories.removeAt(index);
          if (index >= stories.length) index = stories.length - 1;
        });
      }
      widget.onDeleted();
      if (!mounted) return;
      if (shouldClose) {
        Navigator.pop(context);
      } else {
        pageController.jumpToPage(index);
        restartProgress();
      }
    } catch (error) {
      if (mounted) {
        restartProgress();
        showErrorSnackBar(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const SizedBox.shrink();
    final story = stories[index];
    final club = story['clubs'] as Map? ?? const {};
    return GestureDetector(
      onLongPressStart: (_) => progressController.stop(),
      onLongPressEnd: (_) => progressController.forward(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: pageController,
            itemCount: stories.length,
            onPageChanged: (value) {
              setState(() => index = value);
              markViewed();
              restartProgress();
            },
            itemBuilder: (_, page) => InteractiveViewer(
              child: NetworkPicture(
                url: stories[page]['media_url'] as String?,
                fit: BoxFit.contain,
                borderRadius: 0,
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: previous,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: next,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 18,
            child: AnimatedBuilder(
              animation: progressController,
              builder: (context, _) => Row(
                children: List.generate(
                  stories.length,
                  (value) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: LinearProgressIndicator(
                        value: value < index
                            ? 1
                            : value == index
                                ? progressController.value
                                : 0,
                        backgroundColor: Colors.white38,
                        color: Colors.white,
                      ),
                    ),
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
          if ('${story['caption'] ?? ''}'.isNotEmpty)
            Positioned(
              left: 24,
              right: 24,
              bottom: 42,
              child: Text(
                '${story['caption']}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
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
      ),
    );
  }

  @override
  void dispose() {
    progressController.dispose();
    pageController.dispose();
    super.dispose();
  }
}
