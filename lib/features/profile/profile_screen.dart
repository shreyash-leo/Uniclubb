import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../core/supabase/uniclub_repository.dart';
import '../../core/utils/validators.dart';
import '../../shared/event_post_card.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../auth/account_security_screen.dart';
import '../event/event_detail_screen.dart';
import '../notifications/notification_center.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final repo = UniClubRepository();
  Map<String, dynamic>? profile;
  bool loading = true;
  Object? loadError;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final loadedProfile = await repo.profile();
      if (mounted) {
        setState(() {
          profile = loadedProfile;
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

  Future<void> avatar() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 75, maxWidth: 1200);
    if (picked == null) return;
    try {
      final extension = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final url = await repo.upload(
        bucket: 'avatars',
        bytes: await picked.readAsBytes(),
        extension: extension,
        folder: repo.userId,
      );
      await repo.client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', repo.userId);
      await load();
    } on StorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            const NotificationAction(),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: loadError != null
            ? AsyncErrorState(
                error: loadError,
                onRetry: () {
                  setState(() => loading = true);
                  load();
                },
              )
            : loading
                ? const Center(child: CircularProgressIndicator())
                : NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: _ProfileHeader(
                          profile: profile!,
                          repo: repo,
                          onAvatarTap: avatar,
                          onEdit: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    EditProfileScreen(profile: profile!),
                              ),
                            );
                            await load();
                          },
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _ProfileTabsDelegate(
                          color: Theme.of(context).colorScheme.surface,
                          child: const TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              Tab(height: 40, text: 'Posts'),
                              Tab(height: 40, text: 'Events'),
                              Tab(height: 40, text: 'About'),
                              Tab(height: 40, text: 'Clubs'),
                              Tab(height: 40, text: 'Badges'),
                            ],
                          ),
                        ),
                      ),
                    ],
                    body: TabBarView(
                      children: [
                        _ProfilePosts(repo: repo),
                        _ProfileTabList(
                          children: [
                            const SectionHeader('Event history'),
                            const SizedBox(height: 8),
                            _EventHistory(repo: repo),
                            const SizedBox(height: 24),
                            const SectionHeader('Events organized'),
                            const SizedBox(height: 8),
                            _OrganizedEvents(repo: repo),
                          ],
                        ),
                        _ProfileAbout(profile: profile!),
                        _ProfileTabList(
                          children: [
                            const SectionHeader('Club memberships'),
                            const SizedBox(height: 8),
                            _ClubHistory(repo: repo),
                          ],
                        ),
                        _ProfileBadges(repo: repo),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.repo,
    required this.onAvatarTap,
    required this.onEdit,
  });

  final Map<String, dynamic> profile;
  final UniClubRepository repo;
  final VoidCallback onAvatarTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 152,
          width: double.infinity,
          child: '${profile['cover_url'] ?? ''}'.isEmpty
              ? ColoredBox(
                  color: theme.colorScheme.primaryContainer,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Icon(
                        Icons.hub_outlined,
                        size: 46,
                        color: theme.colorScheme.primary.withValues(alpha: .3),
                      ),
                    ),
                  ),
                )
              : NetworkPicture(
                  url: profile['cover_url'] as String?,
                  width: double.infinity,
                  height: 152,
                  borderRadius: 0,
                ),
        ),
        Transform.translate(
          offset: const Offset(0, -34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -42),
                      child: GestureDetector(
                        onTap: onAvatarTap,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: NetworkPicture(
                                url: profile['avatar_url'] as String?,
                                width: 96,
                                height: 96,
                                borderRadius: 48,
                              ),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primary,
                                child: const Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Column(
                        children: [
                          Text(
                            '${profile['full_name'] ?? 'User'}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (profile['username'] != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '@${profile['username']}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '${profile['department'] ?? 'Department not set'} · ${profile['academic_year'] ?? 'Year not set'}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 18),
                          FutureBuilder<Map<String, dynamic>>(
                            future: repo.profilePublicCounts(repo.userId),
                            builder: (context, snapshot) {
                              final values =
                                  snapshot.data ?? const <String, dynamic>{};
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ProfileMetric(
                                    value:
                                        (values['followers'] as num?)?.toInt(),
                                    label: 'Followers',
                                  ),
                                  Container(
                                    width: 1,
                                    height: 34,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  _ProfileMetric(
                                    value:
                                        (values['following'] as num?)?.toInt(),
                                    label: 'Following',
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value == null ? '—' : '$value',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsDelegate({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      ColoredBox(
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      );

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) =>
      color != oldDelegate.color || child != oldDelegate.child;
}

class _ProfileTabList extends StatelessWidget {
  const _ProfileTabList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
        children: children,
      );
}

class _ProfileAbout extends StatelessWidget {
  const _ProfileAbout({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final skills = List<String>.from(profile['skills'] as List? ?? const []);
    final interests =
        List<String>.from(profile['interests'] as List? ?? const []);
    return _ProfileTabList(
      children: [
        const SectionHeader('About'),
        const SizedBox(height: 8),
        Text(
          '${profile['bio'] ?? 'Add a bio to tell your campus about you.'}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text('${profile['department'] ?? 'Department not set'}'),
            subtitle: Text('${profile['academic_year'] ?? 'Year not set'}'),
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader('Skills'),
        const SizedBox(height: 8),
        if (skills.isEmpty)
          const Text('No skills added yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills.map((value) => Chip(label: Text(value))).toList(),
          ),
        const SizedBox(height: 24),
        const SectionHeader('Interests'),
        const SizedBox(height: 8),
        if (interests.isEmpty)
          const Text('No interests added yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                interests.map((value) => Chip(label: Text(value))).toList(),
          ),
      ],
    );
  }
}

class _ProfileBadges extends StatelessWidget {
  const _ProfileBadges({required this.repo});

  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.client
            .from('user_badges')
            .select('*, badges(*)')
            .eq('user_id', repo.userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ProfileTabState(
              child: AsyncErrorState(error: snapshot.error),
            );
          }
          if (!snapshot.hasData) return const SkeletonList(count: 3);
          return _ProfileTabList(
            children: [
              const SectionHeader('Achievements and badges'),
              const SizedBox(height: 12),
              if (snapshot.data!.isEmpty)
                const EmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: 'No badges yet',
                  message:
                      'Attend events and contribute to clubs to earn badges.',
                )
              else
                ...snapshot.data!.map((row) {
                  final badge = row['badges'] as Map? ?? const {};
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text('${badge['name'] ?? 'Achievement'}'),
                      subtitle: Text('${badge['description'] ?? ''}'),
                    ),
                  );
                }),
            ],
          );
        },
      );
}

class _ProfilePosts extends StatelessWidget {
  const _ProfilePosts({required this.repo});

  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.client
            .from('posts')
            .select('id,body,created_at,media')
            .eq('author_id', repo.userId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ProfileTabState(
              child: AsyncErrorState(error: snapshot.error),
            );
          }
          if (!snapshot.hasData) return const SkeletonList();
          if (snapshot.data!.isEmpty) {
            return const _ProfileTabState(
              child: EmptyState(
                icon: Icons.grid_on_outlined,
                title: 'No posts yet',
                message: 'Posts you publish will appear here.',
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final post = snapshot.data![index];
              final media = post['media'] as List? ?? const [];
              final first = media.isEmpty
                  ? const <String, dynamic>{}
                  : Map<String, dynamic>.from(media.first as Map? ?? const {});
              final url =
                  first['url'] as String? ?? first['media_url'] as String?;
              return NetworkPicture(
                url: url,
                width: double.infinity,
                height: double.infinity,
                borderRadius: 8,
              );
            },
          );
        },
      );
}

class _ProfileTabState extends StatelessWidget {
  const _ProfileTabState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
        children: [child],
      );
}

class _OrganizedEvents extends StatelessWidget {
  const _OrganizedEvents({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.client
          .from('events')
          .select('*, clubs(name,logo_url,college_id)')
          .eq('created_by', repo.userId)
          .order('starts_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) return AsyncErrorState(error: snapshot.error);
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.isEmpty) {
          return const Text('Events you organize will appear here.');
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 4 / 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final event = snapshot.data![index];
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
        );
      },
    );
  }
}

class _ClubHistory extends StatelessWidget {
  const _ClubHistory({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.client
          .from('club_memberships')
          .select('*, clubs(name), club_positions(name)')
          .eq('user_id', repo.userId)
          .order('created_at', ascending: false),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Column(
          children: snapshot.data!
              .map((row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text('${(row['clubs'] as Map?)?['name'] ?? 'Club'}'),
                    subtitle: Text(
                        '${(row['club_positions'] as Map?)?['name'] ?? 'Member'} · ${row['status']}'),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _EventHistory extends StatelessWidget {
  const _EventHistory({required this.repo});
  final UniClubRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.myRegistrations(),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Column(
          children: snapshot.data!.map((row) {
            final event = row['events'] as Map<String, dynamic>? ?? {};
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: Text('${event['title'] ?? 'Event'}'),
              subtitle:
                  Text('${formatDate(event['starts_at'])} · ${row['status']}'),
            );
          }).toList(),
        );
      },
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final repo = UniClubRepository();
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController username;
  late final TextEditingController bio;
  late final TextEditingController department;
  late final TextEditingController year;
  late final TextEditingController skills;
  late final TextEditingController interests;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.profile['full_name'] ?? ''}');
    username =
        TextEditingController(text: '${widget.profile['username'] ?? ''}');
    bio = TextEditingController(text: '${widget.profile['bio'] ?? ''}');
    department =
        TextEditingController(text: '${widget.profile['department'] ?? ''}');
    year =
        TextEditingController(text: '${widget.profile['academic_year'] ?? ''}');
    skills = TextEditingController(
        text: List<String>.from(widget.profile['skills'] as List? ?? const [])
            .join(', '));
    interests = TextEditingController(
        text:
            List<String>.from(widget.profile['interests'] as List? ?? const [])
                .join(', '));
  }

  List<String> list(TextEditingController value) => value.text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      await repo.client.from('profiles').update({
        'full_name': name.text.trim(),
        'username': username.text.trim().isEmpty
            ? null
            : username.text.trim().toLowerCase(),
        'bio': bio.text.trim(),
        'department': department.text.trim(),
        'academic_year': year.text.trim(),
        'skills': list(skills),
        'interests': list(interests),
        'onboarding_complete': true,
      }).eq('id', repo.userId);
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {'full_name': name.text.trim()}));
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field(
              name,
              'Full name',
              validator: (value) =>
                  Validators.requiredField(value, label: 'Full name'),
            ),
            _field(username, 'Username', validator: Validators.username),
            _field(bio, 'Bio', lines: 4),
            _field(department, 'Department'),
            _field(year, 'Academic year'),
            _field(skills, 'Skills (comma separated)'),
            _field(interests, 'Interests (comma separated)'),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save profile')),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
          {int lines = 1, String? Function(String?)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          validator: validator,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  void dispose() {
    for (final value in [
      name,
      username,
      bio,
      department,
      year,
      skills,
      interests,
    ]) {
      value.dispose();
    }
    super.dispose();
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = Supabase.instance.client.auth;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Label('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: ref.watch(themeModeProvider),
            onChanged: (value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).state = value;
              }
            },
            child: const Column(
              children: [
                RadioListTile(value: ThemeMode.system, title: Text('System')),
                RadioListTile(value: ThemeMode.light, title: Text('Light')),
                RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
              ],
            ),
          ),
          const _Label('Account and privacy'),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Edit profile'),
            subtitle: const Text('Identity, bio, skills and interests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final profile = await UniClubRepository().profile();
              if (!context.mounted || profile == null) return;
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditProfileScreen(profile: profile),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Saved events'),
            subtitle: const Text('Events you bookmarked for later'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SavedEventsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const ChangePasswordScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification preferences'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const NotificationPreferencesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked users'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const BlockedUsersScreen())),
          ),
          const _Label('Application'),
          const ListTile(
            leading: Icon(Icons.system_update_outlined),
            title: Text('App updates'),
            subtitle: Text('Version 2.0.0 · automatic update checks enabled'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever,
                color: Theme.of(context).colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const DeleteAccountScreen())),
          ),
        ],
      ),
    );
  }
}

class SavedEventsScreen extends StatefulWidget {
  const SavedEventsScreen({super.key});

  @override
  State<SavedEventsScreen> createState() => _SavedEventsScreenState();
}

class _SavedEventsScreenState extends State<SavedEventsScreen> {
  final repo = UniClubRepository();
  late Future<List<Map<String, dynamic>>> future = repo.savedEvents();

  Future<void> refresh() async {
    final next = repo.savedEvents();
    setState(() => future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved events')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error, onRetry: refresh);
          }
          if (!snapshot.hasData) return const SkeletonList();
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_outline,
              title: 'No saved events',
              message:
                  'Tap the bookmark on an event, workshop, competition or hackathon.',
            );
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: snapshot.data!
                  .map((event) => EventPostCard(
                        event: event,
                        onSaveChanged: refresh,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => EventDetailScreen(event: event),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(value,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );
}

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = UniClubRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.client
            .from('user_blocks')
            .stream(primaryKey: ['blocker_id', 'blocked_id']).eq(
                'blocker_id', repo.userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
                icon: Icons.block, title: 'No blocked users');
          }
          return ListView(
            children: snapshot.data!
                .map((row) => ListTile(
                      leading:
                          const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text('${row['blocked_id']}'),
                      trailing: TextButton(
                        onPressed: () => repo.client
                            .from('user_blocks')
                            .delete()
                            .eq('blocker_id', repo.userId)
                            .eq('blocked_id', row['blocked_id']),
                        child: const Text('Unblock'),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
