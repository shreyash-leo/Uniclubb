import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';
import '../club/clubs_hub_screen.dart';
import '../event/event_detail_screen.dart';
import '../messaging/messages_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final repo = UniClubRepository();
  Map<String, dynamic>? profile;
  bool following = false;
  bool blocked = false;
  bool loading = true;
  Object? loadError;
  int followers = 0;
  int followingCount = 0;
  late Future<_PublicProfileActivity> activity = loadActivity();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<_PublicProfileActivity> loadActivity() async {
    final values = await Future.wait<dynamic>([
      repo.client
          .from('club_memberships')
          .select('status, joined_at, clubs(*), club_positions(name)')
          .eq('user_id', widget.userId)
          .eq('status', 'active')
          .order('joined_at', ascending: false),
      repo.client
          .from('events')
          .select('*, clubs(name,logo_url,college_id)')
          .eq('created_by', widget.userId)
          .eq('status', 'published')
          .order('starts_at', ascending: false),
    ]);
    return _PublicProfileActivity(
      memberships: List<Map<String, dynamic>>.from(values[0] as List),
      events: List<Map<String, dynamic>>.from(values[1] as List),
    );
  }

  Future<void> load() async {
    try {
      final loadedProfile = await repo.profile(widget.userId);
      final followState = repo.client
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', repo.userId)
          .eq('followed_id', widget.userId)
          .maybeSingle();
      final blockState = repo.client
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', repo.userId)
          .eq('blocked_id', widget.userId)
          .maybeSingle();
      final states = await Future.wait<dynamic>([
        followState.then((value) => value),
        blockState.then((value) => value),
        repo.profilePublicCounts(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          profile = loadedProfile;
          following = states[0] != null;
          blocked = states[1] != null;
          final counts = Map<String, dynamic>.from(states[2] as Map);
          followers = (counts['followers'] as num?)?.toInt() ?? 0;
          followingCount = (counts['following'] as num?)?.toInt() ?? 0;
          loadError = null;
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          loadError = error;
          loading = false;
        });
      }
    }
  }

  Future<void> toggleFollow() async {
    final wasFollowing = following;
    setState(() {
      following = !wasFollowing;
      followers += wasFollowing ? -1 : 1;
    });
    try {
      if (wasFollowing) {
        await repo.client
            .from('user_follows')
            .delete()
            .eq('follower_id', repo.userId)
            .eq('followed_id', widget.userId);
      } else {
        await repo.client
            .from('user_follows')
            .insert({'follower_id': repo.userId, 'followed_id': widget.userId});
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        following = wasFollowing;
        followers += wasFollowing ? 1 : -1;
      });
      showErrorSnackBar(context, error);
    }
  }

  Future<void> toggleBlock() async {
    if (blocked) {
      await repo.client
          .from('user_blocks')
          .delete()
          .eq('blocker_id', repo.userId)
          .eq('blocked_id', widget.userId);
    } else {
      await repo.client
          .from('user_blocks')
          .insert({'blocker_id': repo.userId, 'blocked_id': widget.userId});
    }
    if (mounted) setState(() => blocked = !blocked);
  }

  Future<void> message() async {
    try {
      final conversation = await repo.directConversation(widget.userId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(
            conversationId: '${conversation['id']}',
            title: '${profile?['full_name'] ?? 'Conversation'}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: AsyncErrorState(
          error: loadError,
          onRetry: () {
            setState(() => loading = true);
            load();
          },
        ),
      );
    }
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (profile == null) {
      return const Scaffold(
          body: EmptyState(
              icon: Icons.person_off_outlined, title: 'Profile unavailable'));
    }
    final skills = List<String>.from(profile!['skills'] as List? ?? const []);
    final interests =
        List<String>.from(profile!['interests'] as List? ?? const []);
    return Scaffold(
      appBar: AppBar(
        title: Text('${profile!['full_name']}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => toggleBlock(),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'block',
                  child: Text(blocked ? 'Unblock user' : 'Block user')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: NetworkPicture(
              url: profile!['avatar_url'] as String?,
              width: 112,
              height: 112,
              borderRadius: 56,
            ),
          ),
          const SizedBox(height: 14),
          Text('${profile!['full_name']}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          if (profile!['username'] != null)
            Text('@${profile!['username']}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileStat(value: followers, label: 'Followers'),
              const SizedBox(width: 36),
              _ProfileStat(value: followingCount, label: 'Following'),
            ],
          ),
          const SizedBox(height: 12),
          Text('${profile!['bio'] ?? ''}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              FilledButton.tonal(
                  onPressed: blocked ? null : toggleFollow,
                  child: Text(following ? 'Following' : 'Follow')),
              OutlinedButton.icon(
                  onPressed: blocked ? null : message,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message')),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader('Skills'),
          Wrap(
              spacing: 8,
              children:
                  skills.map((value) => Chip(label: Text(value))).toList()),
          const SizedBox(height: 20),
          const SectionHeader('Interests'),
          Wrap(
              spacing: 8,
              children:
                  interests.map((value) => Chip(label: Text(value))).toList()),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.school_outlined),
            title: Text('${profile!['department'] ?? 'Department not set'}'),
            subtitle: Text('${profile!['academic_year'] ?? 'Year not set'}'),
          ),
          const SizedBox(height: 18),
          FutureBuilder<_PublicProfileActivity>(
            future: activity,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AsyncErrorState(error: snapshot.error);
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ProfileStat(
                          value: data.memberships.length, label: 'Clubs'),
                      _ProfileStat(
                          value: data.events.length, label: 'Events organized'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('Club positions'),
                  const SizedBox(height: 8),
                  if (data.memberships.isEmpty)
                    const Text('No active club positions.')
                  else
                    ...data.memberships.map((membership) {
                      final club =
                          membership['clubs'] as Map<String, dynamic>? ?? {};
                      final position = membership['club_positions']
                              as Map<String, dynamic>? ??
                          {};
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: NetworkPicture(
                            url: club['logo_url'] as String?,
                            width: 48,
                            height: 48,
                            borderRadius: 24,
                          ),
                          title: Text('${club['name'] ?? 'Club'}'),
                          subtitle: Text(
                              '${position['name'] ?? 'Member'} · Since ${formatDate(membership['joined_at'], time: false)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: club.isEmpty
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ClubDiscoverDetailScreen(club: club),
                                    ),
                                  ),
                        ),
                      );
                    }),
                  const SizedBox(height: 22),
                  const SectionHeader('Events organized'),
                  const SizedBox(height: 8),
                  if (data.events.isEmpty)
                    const Text('No published events organized yet.')
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 4 / 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: data.events.length,
                      itemBuilder: (context, index) {
                        final event = data.events[index];
                        return InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => EventDetailScreen(event: event),
                            ),
                          ),
                          child: NetworkPicture(
                            url: event['flyer_url'] as String?,
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: 12,
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PublicProfileActivity {
  const _PublicProfileActivity({
    required this.memberships,
    required this.events,
  });
  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> events;
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value', style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
