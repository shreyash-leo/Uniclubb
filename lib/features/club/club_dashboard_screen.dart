import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../event/event_management_screen.dart';
import '../finance/finance_screen.dart';
import '../messaging/club_work_screen.dart';

class ClubDashboardScreen extends StatelessWidget {
  const ClubDashboardScreen(
      {super.key, required this.club, required this.membership});

  final Map<String, dynamic> club;
  final Map<String, dynamic> membership;

  List<String> get permissions {
    final position = membership['club_positions'] as Map<String, dynamic>?;
    return List<String>.from(position?['permissions'] as List? ?? const []);
  }

  bool can(String permission) =>
      permissions.contains('all') || permissions.contains(permission);

  @override
  Widget build(BuildContext context) {
    final position =
        membership['club_positions'] as Map<String, dynamic>? ?? const {};
    final roleName = '${position['name'] ?? ''}';
    final financeRole =
        {'President', 'Supervisor', 'Treasurer'}.contains(roleName);
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${club['name']}'),
          actions: const [NotificationAction()],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Dashboard'),
              Tab(text: 'Announcements'),
              Tab(text: 'Events'),
              Tab(text: 'Members'),
              Tab(text: 'Tasks'),
              Tab(text: 'Finance'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Overview(
              club: club,
              canManageMembers: can('manage_members'),
            ),
            ClubAnnouncementsView(
              club: club,
              canManage: can('manage_announcements'),
            ),
            EventManagementScreen(club: club, canManage: can('manage_events')),
            RoleManagementScreen(
              club: club,
              canManage: can('manage_members'),
            ),
            const ClubTasksView(),
            FinanceScreen(
              club: club,
              canManage: financeRole && can('manage_finance'),
              canApprove: financeRole && can('approve_expenses'),
              canViewDashboard: financeRole,
            ),
            ClubSettingsView(
              club: club,
              canManage: can('all'),
            ),
          ],
        ),
      ),
    );
  }
}

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({
    super.key,
    required this.club,
    required this.canManage,
  });
  final Map<String, dynamic> club;
  final bool canManage;

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  final repo = UniClubRepository();

  Future<List<dynamic>> load() => Future.wait([
        repo.client
            .from('club_memberships')
            .select(
                '*, profiles!club_memberships_user_id_fkey(full_name,email,username,avatar_url,department,academic_year,skills), club_positions(*)')
            .eq('club_id', widget.club['id'])
            .order('joined_at'),
        repo.client
            .from('club_positions')
            .select()
            .eq('club_id', widget.club['id'])
            .order('rank'),
      ]);

  Future<void> assign(String membershipId, String positionId) async {
    await repo.client
        .from('club_memberships')
        .update({'position_id': positionId}).eq('id', membershipId);
    if (mounted) setState(() {});
  }

  Future<void> removeMember(String membershipId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content:
            const Text('This member will lose club access and club tasks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.client.from('club_memberships').update({
      'status': 'left',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', membershipId);
    if (mounted) setState(() {});
  }

  Future<void> decideMembership(
      Map<String, dynamic> membership, String status) async {
    String? positionId = membership['position_id'] as String?;
    if (status == 'active' && positionId == null) {
      final position = await repo.client
          .from('club_positions')
          .select('id')
          .eq('club_id', widget.club['id'])
          .eq('name', 'Member')
          .single();
      positionId = '${position['id']}';
    }
    try {
      await repo.client.from('club_memberships').update({
        'status': status,
        if (positionId != null) 'position_id': positionId,
        if (status == 'active') 'joined_at': DateTime.now().toIso8601String(),
      }).eq('id', membership['id']);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> addMember() async {
    final user = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddClubMemberDialog(repo: repo),
    );
    if (user == null) return;
    try {
      final positions = List<Map<String, dynamic>>.from(await repo.client
          .from('club_positions')
          .select('id,name')
          .eq('club_id', widget.club['id'])
          .order('rank'));
      if (!mounted) return;
      final positionId = await _choosePosition(positions);
      if (positionId == null) return;
      await repo.client.from('club_memberships').upsert({
        'club_id': widget.club['id'],
        'user_id': user['id'],
        'position_id': positionId,
        'status': 'active',
        'joined_at': DateTime.now().toIso8601String(),
        'ended_at': null,
      }, onConflict: 'club_id,user_id');
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user['title']} added to the club')),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<String?> _choosePosition(List<Map<String, dynamic>> positions) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose member position'),
              subtitle: Text('You can define another title if needed.'),
            ),
            ...positions.map((position) => ListTile(
                  title: Text('${position['name']}'),
                  onTap: () => Navigator.pop(context, '${position['id']}'),
                )),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Other'),
              onTap: () => Navigator.pop(context, '__other__'),
            ),
          ],
        ),
      ),
    );
    if (choice != '__other__') return choice;
    if (!mounted) return null;
    final controller = TextEditingController();
    final roleName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New position title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Position',
            helperText: 'This role starts without management permissions.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use position'),
          ),
        ],
      ),
    );
    await disposeTextControllersAfterRoute([controller]);
    if (roleName == null || roleName.isEmpty) return null;
    final existing = positions.where(
      (position) =>
          '${position['name']}'.toLowerCase() == roleName.toLowerCase(),
    );
    if (existing.isNotEmpty) return '${existing.first['id']}';
    final created = await repo.client
        .from('club_positions')
        .insert({
          'club_id': widget.club['id'],
          'name': roleName,
          'rank': 90,
          'permissions': <String>[],
          'is_system': false,
        })
        .select('id')
        .single();
    return '${created['id']}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members and roles'),
        actions: [
          if (widget.canManage)
            IconButton(
                tooltip: 'Add member',
                onPressed: addMember,
                icon: const Icon(Icons.person_add_alt_1_outlined)),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const SkeletonList();
          }
          final memberships =
              List<Map<String, dynamic>>.from(snapshot.data![0] as List);
          final positions =
              List<Map<String, dynamic>>.from(snapshot.data![1] as List);
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: memberships.length,
            itemBuilder: (context, index) {
              final membership = memberships[index];
              final user = Map<String, dynamic>.from(
                  membership['profiles'] as Map? ?? {});
              final isSelf = membership['user_id'] == repo.userId;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          NetworkPicture(
                              url: user['avatar_url'] as String?,
                              width: 54,
                              height: 54,
                              borderRadius: 27),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => _showMemberDetails(user, membership),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${user['full_name'] ?? membership['user_id']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  Text(
                                    '${(membership['club_positions'] as Map?)?['name'] ?? 'Member'} · ${membership['status']}',
                                  ),
                                  Text(
                                    '${user['department'] ?? 'Department not added'}${user['academic_year'] == null ? '' : ' · ${user['academic_year']}'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.canManage && !isSelf) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (membership['status'] == 'active')
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final positionId =
                                        await _choosePosition(positions);
                                    if (positionId != null) {
                                      await assign(
                                          '${membership['id']}', positionId);
                                    }
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit position'),
                                ),
                              )
                            else
                              Expanded(
                                child: PopupMenuButton<String>(
                                  onSelected: (value) =>
                                      decideMembership(membership, value),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'active', child: Text('Accept')),
                                    PopupMenuItem(
                                        value: 'waitlisted',
                                        child: Text('Waitlist')),
                                    PopupMenuItem(
                                        value: 'rejected',
                                        child: Text('Reject')),
                                  ],
                                  child: const OutlinedButton(
                                    onPressed: null,
                                    child: Text('Review request'),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Remove member',
                              onPressed: () =>
                                  removeMember('${membership['id']}'),
                              icon: const Icon(Icons.person_remove_outlined),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showMemberDetails(
      Map<String, dynamic> user, Map<String, dynamic> membership) {
    final skills = List<String>.from(user['skills'] as List? ?? const []);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NetworkPicture(
                url: user['avatar_url'] as String?,
                width: 82,
                height: 82,
                borderRadius: 41,
              ),
              const SizedBox(height: 12),
              Text('${user['full_name'] ?? 'Member'}',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                  '${(membership['club_positions'] as Map?)?['name'] ?? 'Member'}'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: Text('${user['username'] ?? 'No username'}'),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text('${user['email'] ?? 'No email'}'),
              ),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text('${user['department'] ?? 'Department not added'}'),
                subtitle: Text('${user['academic_year'] ?? ''}'),
              ),
              if (skills.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    children: skills
                        .map((value) => Chip(label: Text(value)))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddClubMemberDialog extends StatefulWidget {
  const _AddClubMemberDialog({required this.repo});
  final UniClubRepository repo;

  @override
  State<_AddClubMemberDialog> createState() => _AddClubMemberDialogState();
}

class _AddClubMemberDialogState extends State<_AddClubMemberDialog> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  int requestId = 0;

  Future<void> search(String query) async {
    final current = ++requestId;
    if (query.trim().length < 2) {
      setState(() => results = []);
      return;
    }
    setState(() => loading = true);
    try {
      final rows = await widget.repo.globalSearch(query);
      if (!mounted || current != requestId) return;
      setState(() => results =
          rows.where((row) => row['kind'] == 'user').toList(growable: false));
    } catch (error) {
      if (mounted && current == requestId) showErrorSnackBar(context, error);
    } finally {
      if (mounted && current == requestId) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add club member'),
        content: SizedBox(
          width: 460,
          height: 360,
          child: Column(
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: search,
                decoration: const InputDecoration(
                  hintText: 'Search by name or username',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              if (loading) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Expanded(
                child: results.isEmpty
                    ? const Center(
                        child: Text('Type at least two characters to search'))
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final user = results[index];
                          return ListTile(
                            leading: NetworkPicture(
                              url: user['image_url'] as String?,
                              width: 42,
                              height: 42,
                              borderRadius: 21,
                            ),
                            title: Text('${user['title']}'),
                            subtitle: Text('${user['subtitle'] ?? ''}'),
                            onTap: () => Navigator.pop(context, user),
                          );
                        },
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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _Overview extends StatefulWidget {
  const _Overview({required this.club, required this.canManageMembers});
  final Map<String, dynamic> club;
  final bool canManageMembers;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final repo = UniClubRepository();

  Future<void> showFollowers() async {
    final rows = List<Map<String, dynamic>>.from(await repo.client
        .from('club_follows')
        .select(
            'user_id, profiles!club_follows_user_id_fkey(full_name,username,avatar_url,department)')
        .eq('club_id', widget.club['id'])
        .order('created_at', ascending: false));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        builder: (context, controller) => Column(
          children: [
            const ListTile(title: Text('Club followers')),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No followers yet',
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final profile =
                            rows[index]['profiles'] as Map? ?? const {};
                        return ListTile(
                          leading: NetworkPicture(
                            url: profile['avatar_url'] as String?,
                            width: 46,
                            height: 46,
                            borderRadius: 23,
                          ),
                          title: Text('${profile['full_name'] ?? 'Student'}'),
                          subtitle: Text(
                              '@${profile['username'] ?? 'member'} · ${profile['department'] ?? 'Campus'}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> joinRequests() async => List<
      Map<String,
          dynamic>>.from(await repo
      .client
      .from('club_memberships')
      .select(
          '*, profiles!club_memberships_user_id_fkey(full_name,email,avatar_url)')
      .eq('club_id', widget.club['id'])
      .inFilter('status', ['pending', 'waitlisted']).order('created_at'));

  Future<void> decideMembership(
      Map<String, dynamic> membership, String status) async {
    String? positionId = membership['position_id'] as String?;
    if (status == 'active' && positionId == null) {
      final position = await repo.client
          .from('club_positions')
          .select('id')
          .eq('club_id', widget.club['id'])
          .eq('name', 'Member')
          .single();
      positionId = '${position['id']}';
    }
    await repo.client.from('club_memberships').update({
      'status': status,
      if (positionId != null) 'position_id': positionId,
      if (status == 'active') 'joined_at': DateTime.now().toIso8601String(),
    }).eq('id', membership['id']);
    if (mounted) setState(() {});
  }

  Future<Map<String, int>> stats() async {
    final clubId = widget.club['id'];
    final values = await Future.wait([
      repo.client
          .from('club_memberships')
          .select('id')
          .eq('club_id', clubId)
          .eq('status', 'active'),
      repo.client
          .from('events')
          .select('id')
          .eq('club_id', clubId)
          .eq('status', 'published'),
      repo.client.from('club_follows').select('user_id').eq('club_id', clubId)
    ]);
    return {
      'Members': values[0].length,
      'Events': values[1].length,
      'Followers': values[2].length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            NetworkPicture(
              url: widget.club['banner_url'] as String?,
              width: double.infinity,
              height: 190,
              borderRadius: 0,
            ),
            Positioned(
              left: 18,
              bottom: -44,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: NetworkPicture(
                  url: widget.club['logo_url'] as String?,
                  width: 88,
                  height: 88,
                  borderRadius: 44,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 54),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${widget.club['name']}',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  if (widget.club['verified'] == true)
                    Icon(Icons.verified,
                        color: Theme.of(context).colorScheme.primary),
                ],
              ),
              if ('${widget.club['tagline'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${widget.club['tagline']}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              const SizedBox(height: 14),
              Text('${widget.club['description'] ?? ''}'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FutureBuilder<Map<String, int>>(
          future: stats(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AsyncErrorState(error: snapshot.error);
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 76,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: snapshot.data!.entries
                    .map((entry) => Expanded(
                          child: InkWell(
                            onTap:
                                entry.key == 'Followers' ? showFollowers : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Text('${entry.value}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  Text(entry.key),
                                ],
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Use the tabs above to manage announcements, events, members, tasks, finance and club settings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class ClubAnnouncementsView extends StatefulWidget {
  const ClubAnnouncementsView({
    super.key,
    required this.club,
    required this.canManage,
  });
  final Map<String, dynamic> club;
  final bool canManage;

  @override
  State<ClubAnnouncementsView> createState() => _ClubAnnouncementsViewState();
}

class _ClubAnnouncementsViewState extends State<ClubAnnouncementsView> {
  final repo = UniClubRepository();
  final hiddenIds = <String>{};

  Future<void> compose() async {
    final title = TextEditingController();
    final message = TextEditingController();
    DateTime? scheduledAt;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('New announcement'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: message,
                    minLines: 5,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: Text(scheduledAt == null
                        ? 'Send now'
                        : formatDate(scheduledAt)),
                    subtitle: const Text('Tap to schedule for later'),
                    trailing: scheduledAt == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            onPressed: () =>
                                setModalState(() => scheduledAt = null),
                            icon: const Icon(Icons.close),
                          ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time == null) return;
                      setModalState(() => scheduledAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          ));
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(scheduledAt == null ? 'Send' : 'Schedule'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true &&
        title.text.trim().isNotEmpty &&
        message.text.trim().isNotEmpty) {
      try {
        await repo.client.from('announcements').insert({
          'club_id': widget.club['id'],
          'author_id': repo.userId,
          'title': title.text.trim(),
          'body': message.text.trim(),
          'attachments': const [],
          'poll': null,
          'pinned': false,
          'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
          'published_at': scheduledAt == null
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        });
      } catch (error) {
        if (mounted) showErrorSnackBar(context, error);
      }
    }
    await disposeTextControllersAfterRoute([title, message]);
  }

  Future<void> deleteAnnouncement(String id) async {
    setState(() => hiddenIds.add(id));
    try {
      await repo.client.from('announcements').delete().eq('id', id);
    } catch (error) {
      if (!mounted) return;
      setState(() => hiddenIds.remove(id));
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              heroTag: 'club-announcement-create',
              onPressed: compose,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Announcement'),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.client
            .from('announcements')
            .stream(primaryKey: ['id'])
            .eq('club_id', '${widget.club['id']}')
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) return const SkeletonList();
          final rows = snapshot.data!
              .where((row) => !hiddenIds.contains('${row['id']}'))
              .toList(growable: false);
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements yet',
              message: 'Official club updates will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final row = rows[index];
              final scheduled = row['published_at'] == null;
              return Card(
                child: ListTile(
                  leading: Icon(
                      scheduled ? Icons.schedule : Icons.campaign_outlined),
                  title: Text('${row['title']}'),
                  subtitle: Text(
                    '${row['body']}\n${scheduled ? 'Scheduled' : 'Published'} · '
                    '${formatDate(row['published_at'] ?? row['scheduled_at'] ?? row['created_at'])}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: widget.canManage
                      ? IconButton(
                          tooltip: 'Delete announcement',
                          onPressed: () => deleteAnnouncement('${row['id']}'),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ClubSettingsView extends StatefulWidget {
  const ClubSettingsView({
    super.key,
    required this.club,
    required this.canManage,
  });
  final Map<String, dynamic> club;
  final bool canManage;

  @override
  State<ClubSettingsView> createState() => _ClubSettingsViewState();
}

class _ClubSettingsViewState extends State<ClubSettingsView> {
  final repo = UniClubRepository();
  late final name = TextEditingController(text: '${widget.club['name']}');
  late final description =
      TextEditingController(text: '${widget.club['description'] ?? ''}');
  late final tagline =
      TextEditingController(text: '${widget.club['tagline'] ?? ''}');
  late final location =
      TextEditingController(text: '${widget.club['location'] ?? ''}');
  late String? logoUrl = widget.club['logo_url'] as String?;
  late String? bannerUrl = widget.club['banner_url'] as String?;
  bool saving = false;

  Future<String?> uploadImage(String folder) async {
    final image = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 84);
    if (image == null) return null;
    return repo.upload(
      bucket: 'club-media',
      bytes: await image.readAsBytes(),
      extension: image.name.split('.').last.toLowerCase(),
      folder: '${widget.club['id']}/$folder',
    );
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await repo.client.from('clubs').update({
        'name': name.text.trim(),
        'tagline': tagline.text.trim(),
        'description': description.text.trim(),
        'location': location.text.trim(),
        'logo_url': logoUrl,
        'banner_url': bannerUrl,
      }).eq('id', widget.club['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club settings saved')),
        );
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteClub() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete club?'),
        content: Text(
          '${widget.club['name']} and all of its events, memberships, '
          'tasks and content will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete club'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await repo.client.from('clubs').delete().eq('id', widget.club['id']);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Settings are restricted',
        message: 'Only the club owner can update these settings.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      children: [
        NetworkPicture(
          url: bannerUrl,
          width: double.infinity,
          height: 170,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final value = await uploadImage('banner');
            if (value != null && mounted) setState(() => bannerUrl = value);
          },
          icon: const Icon(Icons.image_outlined),
          label: const Text('Change banner'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            NetworkPicture(
              url: logoUrl,
              width: 72,
              height: 72,
              borderRadius: 22,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final value = await uploadImage('logo');
                if (value != null && mounted) setState(() => logoUrl = value);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Change logo'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Club name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tagline,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Tagline',
            hintText: 'A short line that describes the club',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: description,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: location,
          decoration: const InputDecoration(labelText: 'Location'),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save settings'),
        ),
        const SizedBox(height: 30),
        Text('Danger zone',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: deleteClub,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete club'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    name.dispose();
    tagline.dispose();
    description.dispose();
    location.dispose();
    super.dispose();
  }
}
