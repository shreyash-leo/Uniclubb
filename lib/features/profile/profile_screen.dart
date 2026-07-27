import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app.dart';
import '../../core/supabase/uniclub_repository.dart';
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
    return Scaffold(
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
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: avatar,
                            child: Stack(
                              children: [
                                NetworkPicture(
                                    url: profile?['avatar_url'] as String?,
                                    width: 92,
                                    height: 92,
                                    borderRadius: 46),
                                const Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: CircleAvatar(
                                      radius: 15,
                                      child: Icon(Icons.edit, size: 15)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${profile?['full_name'] ?? 'User'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                if (profile?['username'] != null)
                                  Text('@${profile?['username']}'),
                                Text(
                                    '${profile?['department'] ?? ''} · ${profile?['academic_year'] ?? ''}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('${profile?['bio'] ?? ''}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: List<String>.from(
                                profile?['skills'] as List? ?? const [])
                            .map((skill) => Chip(label: Text(skill)))
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: profile == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        EditProfileScreen(profile: profile!),
                                  ),
                                );
                                await load();
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                      ),
                      const SizedBox(height: 24),
                      const SectionHeader('Badges and positions'),
                      const SizedBox(height: 10),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: repo.client
                            .from('user_badges')
                            .select('*, badges(*)')
                            .eq('user_id', repo.userId),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return AsyncErrorState(error: snapshot.error);
                          }
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          if (snapshot.data!.isEmpty) {
                            return const Text(
                                'Attend events and contribute to earn badges.');
                          }
                          return Wrap(
                            spacing: 8,
                            children: snapshot.data!
                                .map((row) => Chip(
                                      avatar: const Icon(
                                          Icons.workspace_premium,
                                          size: 18),
                                      label: Text(
                                          '${(row['badges'] as Map)['name']}'),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      const SectionHeader('Club history'),
                      const SizedBox(height: 8),
                      _ClubHistory(repo: repo),
                      const SizedBox(height: 24),
                      const SectionHeader('Event history'),
                      const SizedBox(height: 8),
                      _EventHistory(repo: repo),
                    ],
                  ),
                ),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field(name, 'Full name'),
          _field(username, 'Username'),
          _field(bio, 'Bio', lines: 4),
          _field(department, 'Department'),
          _field(year, 'Academic year'),
          _field(skills, 'Skills (comma separated)'),
          _field(interests, 'Interests (comma separated)'),
          ElevatedButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save profile')),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
          {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
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
