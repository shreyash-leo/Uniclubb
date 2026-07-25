import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../event/event_detail_screen.dart';
import 'club_dashboard_screen.dart';

class ClubsHubScreen extends StatefulWidget {
  const ClubsHubScreen({super.key});

  @override
  State<ClubsHubScreen> createState() => _ClubsHubScreenState();
}

class _ClubsHubScreenState extends State<ClubsHubScreen> {
  final repo = UniClubRepository();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your clubs'),
          actions: const [NotificationAction()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My clubs'),
              Tab(text: 'My events'),
              Tab(text: 'Leaderboard'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'clubs-create',
          tooltip: 'Create club',
          onPressed: () async {
            final created = await Navigator.push<bool>(
              context,
              MaterialPageRoute<bool>(builder: (_) => const CreateClubScreen()),
            );
            if (created == true && mounted) setState(() {});
          },
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
        body: TabBarView(
          children: [
            _MyClubs(repo: repo),
            _MyEvents(repo: repo),
            _Leaderboard(repo: repo),
          ],
        ),
      ),
    );
  }
}

class _MyClubs extends StatelessWidget {
  const _MyClubs({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.myMemberships(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.group_off_outlined,
            title: 'You have not joined a club yet',
            message: 'Find clubs from Discover or create your own.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final membership = snapshot.data![index];
            final club = Map<String, dynamic>.from(membership['clubs'] as Map);
            final position =
                membership['club_positions'] as Map<String, dynamic>?;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ClubDashboardScreen(club: club, membership: membership),
                  ),
                ),
                child: Row(
                  children: [
                    NetworkPicture(
                      url: club['logo_url'] as String?,
                      width: 88,
                      height: 88,
                      borderRadius: 0,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${club['name']}',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text('${position?['name'] ?? 'Member'}'),
                            const SizedBox(height: 4),
                            Text(
                                '${club['category']} · ${club['location'] ?? ''}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MyEvents extends StatelessWidget {
  const _MyEvents({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.myRegistrations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No event participation yet',
            message: 'Events you register for will be collected here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final registration = snapshot.data![index];
            final event = registration['events'] as Map<String, dynamic>? ?? {};
            return Card(
              child: ListTile(
                leading: NetworkPicture(
                  url: event['flyer_url'] as String?,
                  width: 58,
                  height: 58,
                  borderRadius: 12,
                ),
                title: Text('${event['title'] ?? 'Event'}'),
                subtitle: Text(formatDate(event['starts_at'])),
                trailing: StatusChip('${registration['status']}'),
                onTap: event.isEmpty
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => EventDetailScreen(event: event),
                          ),
                        ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.client
          .from('club_scores')
          .select('*, clubs(name, logo_url, category)')
          .order('engagement_points', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Leaderboard is waiting for activity');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final row = snapshot.data![index];
            final club = row['clubs'] as Map<String, dynamic>? ?? {};
            final total = (row['engagement_points'] as num? ?? 0) +
                (row['event_points'] as num? ?? 0) +
                (row['attendance_points'] as num? ?? 0) +
                (row['community_points'] as num? ?? 0);
            return Card(
              color: index < 3
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: club['logo_url'] == null
                      ? null
                      : NetworkImage('${club['logo_url']}'),
                  child:
                      club['logo_url'] == null ? Text('#${index + 1}') : null,
                ),
                title: Text('${club['name'] ?? 'Club'}'),
                subtitle: Text('${club['category'] ?? ''}'),
                trailing: Text(
                  '$total pts',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ClubDiscoverDetailScreen extends StatefulWidget {
  const ClubDiscoverDetailScreen({super.key, required this.club});
  final Map<String, dynamic> club;

  @override
  State<ClubDiscoverDetailScreen> createState() =>
      _ClubDiscoverDetailScreenState();
}

class _ClubDiscoverDetailScreenState extends State<ClubDiscoverDetailScreen> {
  final repo = UniClubRepository();
  bool working = false;
  bool following = false;
  String? membershipStatus;
  late Future<Map<String, dynamic>> counts;

  @override
  void initState() {
    super.initState();
    counts = repo.clubPublicCounts('${widget.club['id']}');
    loadRelationship();
  }

  Future<void> loadRelationship() async {
    try {
      final clubId = '${widget.club['id']}';
      final follow = repo.client
          .from('club_follows')
          .select('club_id')
          .eq('club_id', clubId)
          .eq('user_id', repo.userId)
          .maybeSingle();
      final membership = repo.client
          .from('club_memberships')
          .select('status')
          .eq('club_id', clubId)
          .eq('user_id', repo.userId)
          .maybeSingle();
      final values = await Future.wait<dynamic>([
        follow.then((value) => value),
        membership.then((value) => value),
      ]);
      if (!mounted) return;
      setState(() {
        following = values[0] != null;
        membershipStatus = (values[1] as Map?)?['status'] as String?;
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> act(bool follow) async {
    setState(() => working = true);
    try {
      if (follow) {
        await repo.followClub('${widget.club['id']}', !following);
      } else {
        await repo.applyToClub('${widget.club['id']}');
      }
      if (mounted) {
        if (follow) {
          setState(() {
            following = !following;
            counts = repo.clubPublicCounts('${widget.club['id']}');
          });
        } else {
          setState(() => membershipStatus = 'pending');
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(follow
              ? (following ? 'Club followed' : 'Club unfollowed')
              : 'Join request sent'),
        ));
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    return Scaffold(
      appBar: AppBar(
        title: Text('${club['name']}'),
        actions: const [NotificationAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          NetworkPicture(
            url: club['banner_url'] as String?,
            height: 210,
            width: double.infinity,
          ),
          Transform.translate(
            offset: const Offset(16, -32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: NetworkPicture(
                url: club['logo_url'] as String?,
                width: 84,
                height: 84,
                borderRadius: 24,
              ),
            ),
          ),
          Text('${club['name']}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
              '${club['category']} · ${club['club_type'] ?? 'Student club'} · ${club['location'] ?? ''}'),
          const SizedBox(height: 14),
          FutureBuilder<Map<String, dynamic>>(
            future: counts,
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <String, dynamic>{};
              return Row(
                children: [
                  _ClubStat(
                      value: (values['members'] as num?)?.toInt(),
                      label: 'Members'),
                  const SizedBox(width: 28),
                  _ClubStat(
                      value: (values['followers'] as num?)?.toInt(),
                      label: 'Followers'),
                  const SizedBox(width: 28),
                  _ClubStat(
                      value: (values['events'] as num?)?.toInt(),
                      label: 'Events'),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('${club['description'] ?? ''}'),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: working ? null : () => act(true),
                  icon:
                      Icon(following ? Icons.favorite : Icons.favorite_border),
                  label: Text(following ? 'Following' : 'Follow'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: working || membershipStatus == 'active'
                      ? null
                      : membershipStatus == 'pending' ||
                              membershipStatus == 'waitlisted'
                          ? null
                          : () => act(false),
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(switch (membershipStatus) {
                    'active' => 'Member',
                    'pending' => 'Request pending',
                    'waitlisted' => 'Waitlisted',
                    _ => 'Request to join',
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClubStat extends StatelessWidget {
  const _ClubStat({required this.value, required this.label});
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value == null ? '—' : '$value',
              style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  static const categories = [
    'Tech',
    'Cultural',
    'Sports',
    'Academic',
    'Social',
    'Entrepreneurship',
    'Other',
  ];
  static const types = [
    'Student',
    'Departmental',
    'Professional',
    'Community',
    'Faculty supervised',
    'Other',
  ];

  final repo = UniClubRepository();
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  final location = TextEditingController();
  final otherCategory = TextEditingController();
  final otherType = TextEditingController();
  String category = 'Tech';
  String clubType = 'Student';
  String? collegeId;
  XFile? logo;
  XFile? banner;
  Uint8List? logoPreview;
  Uint8List? bannerPreview;
  bool loading = false;
  late Future<List<Map<String, dynamic>>> colleges = loadColleges();

  Future<List<Map<String, dynamic>>> loadColleges() async {
    final values = await Future.wait<dynamic>([
      repo.client.from('colleges').select('id,name,short_name').order('name'),
      repo.profile(),
    ]);
    final rows = List<Map<String, dynamic>>.from(values[0] as List);
    final profile = values[1] as Map<String, dynamic>?;
    collegeId = profile?['college_id'] as String?;
    return rows;
  }

  Future<void> pickImage(bool isLogo) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: isLogo ? 1000 : 1800,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          logo = picked;
          logoPreview = bytes;
        } else {
          banner = picked;
          bannerPreview = bytes;
        }
      });
    }
  }

  Future<String?> upload(XFile? file, String folder) async {
    if (file == null) return null;
    return repo.upload(
      bucket: 'club-media',
      bytes: await file.readAsBytes(),
      extension: file.name.split('.').last.toLowerCase(),
      folder: folder,
    );
  }

  Future<void> create() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      final draftFolder = 'club-drafts/${repo.userId}';
      final media = await Future.wait([
        upload(logo, '$draftFolder/logos'),
        upload(banner, '$draftFolder/banners'),
      ]);
      await repo.client.rpc('create_club', params: {
        'club_name': name.text.trim(),
        'club_category':
            category == 'Other' ? otherCategory.text.trim() : category,
        'club_type_value':
            clubType == 'Other' ? otherType.text.trim() : clubType,
        'club_college_id': collegeId,
        'club_location': location.text.trim(),
        'club_description': description.text.trim(),
        'club_logo_url': media[0],
        'club_banner_url': media[1],
      });
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create the club.')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create club')),
      body: Form(
        key: formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text('Build your club identity',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('You will become the club President.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Row(
              children: [
                InkWell(
                  onTap: () => pickImage(true),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: logoPreview == null
                        ? const Icon(Icons.add_a_photo_outlined)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child:
                                Image.memory(logoPreview!, fit: BoxFit.cover),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pickImage(false),
                    icon: const Icon(Icons.panorama_outlined),
                    label: Text(bannerPreview == null
                        ? 'Add banner image'
                        : 'Banner selected'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              validator: (value) => value == null || value.trim().length < 3
                  ? 'Enter a club name'
                  : null,
              decoration: const InputDecoration(labelText: 'Club name'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => category = value ?? category),
            ),
            if (category == 'Other') ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: otherCategory,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the category'
                    : null,
                decoration: const InputDecoration(labelText: 'Custom category'),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: clubType,
              decoration: const InputDecoration(labelText: 'Club type'),
              items: types
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => clubType = value ?? clubType),
            ),
            if (clubType == 'Other') ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: otherType,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the club type'
                    : null,
                decoration:
                    const InputDecoration(labelText: 'Custom club type'),
              ),
            ],
            const SizedBox(height: 14),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: colleges,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Colleges could not be loaded.');
                }
                return DropdownButtonFormField<String>(
                  initialValue: collegeId,
                  decoration: const InputDecoration(labelText: 'College'),
                  items: (snapshot.data ?? [])
                      .map((row) => DropdownMenuItem(
                            value: '${row['id']}',
                            child: Text('${row['short_name'] ?? row['name']}'),
                          ))
                      .toList(),
                  onChanged: (value) => collegeId = value,
                );
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: location,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'Campus, city or meeting place',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: description,
              minLines: 4,
              maxLines: 8,
              validator: (value) => value == null || value.trim().length < 20
                  ? 'Add at least 20 characters'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: loading ? null : create,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(loading ? 'Creating…' : 'Create club'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    location.dispose();
    otherCategory.dispose();
    otherType.dispose();
    super.dispose();
  }
}
