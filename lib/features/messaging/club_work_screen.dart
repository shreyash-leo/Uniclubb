import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import 'messages_screen.dart';

class ClubWorkScreen extends StatelessWidget {
  const ClubWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Club work'),
          actions: const [NotificationAction()],
          bottom: const TabBar(
            tabs: [
              Tab(height: 40, text: 'Chats'),
              Tab(height: 40, text: 'Tasks'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            MessagesScreen(embedded: true),
            ClubTasksView(),
          ],
        ),
      ),
    );
  }
}

class ClubTasksView extends StatefulWidget {
  const ClubTasksView({super.key});

  @override
  State<ClubTasksView> createState() => _ClubTasksViewState();
}

class _ClubTasksViewState extends State<ClubTasksView> {
  final repo = UniClubRepository();
  late Future<_TaskData> future = load();

  Future<_TaskData> load() async {
    final memberships = await repo.myMemberships();
    if (memberships.isEmpty) {
      return const _TaskData(memberships: [], tasks: []);
    }
    final clubIds =
        memberships.map((row) => '${row['club_id']}').toList(growable: false);
    final tasks = List<Map<String, dynamic>>.from(await repo.client
        .from('club_tasks')
        .select(
            '*, clubs(name), profiles!club_tasks_assigned_to_fkey(full_name)')
        .inFilter('club_id', clubIds)
        .order('due_at'));
    return _TaskData(memberships: memberships, tasks: tasks);
  }

  bool canAssign(Map<String, dynamic> membership) {
    final position = membership['club_positions'] as Map<String, dynamic>?;
    final permissions =
        List<String>.from(position?['permissions'] as List? ?? const []);
    return permissions.contains('all') ||
        permissions.contains('manage_members') ||
        permissions.contains('manage_events');
  }

  Future<void> createTask(List<Map<String, dynamic>> memberships) async {
    final manageable = memberships.where(canAssign).toList(growable: false);
    if (manageable.isEmpty) return;
    final value = await showDialog<_NewTask>(
      context: context,
      builder: (_) => _NewTaskDialog(memberships: manageable),
    );
    if (value == null) return;
    try {
      await repo.client.from('club_tasks').insert({
        'club_id': value.clubId,
        'title': value.title,
        'description': value.description,
        'assigned_to': value.assignedTo,
        'due_at': value.dueAt?.toIso8601String(),
        'created_by': repo.userId,
      });
      refresh();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> updateTask(Map<String, dynamic> task, String status) async {
    try {
      await repo.client.from('club_tasks').update({
        'status': status,
        'completed_at':
            status == 'completed' ? DateTime.now().toIso8601String() : null,
      }).eq('id', task['id']);
      refresh();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void refresh() {
    final next = load();
    setState(() {
      future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TaskData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error, onRetry: refresh);
        }
        if (!snapshot.hasData) {
          return const SkeletonList();
        }
        final data = snapshot.data!;
        if (data.memberships.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'Club members only',
            message: 'Join a club to receive and collaborate on tasks.',
          );
        }
        final canCreate = data.memberships.any(canAssign);
        return Scaffold(
          floatingActionButton: canCreate
              ? FloatingActionButton.extended(
                  heroTag: 'club-task-create',
                  onPressed: () => createTask(data.memberships),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Assign'),
                )
              : null,
          body: data.tasks.isEmpty
              ? const EmptyState(
                  icon: Icons.task_alt,
                  title: 'No tasks assigned',
                  message: 'New work from your clubs will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: () async => refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                    itemCount: data.tasks.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final completed = data.tasks
                            .where((task) => task['status'] == 'completed')
                            .length;
                        final active = data.tasks
                            .where((task) => task['status'] == 'in_progress')
                            .length;
                        final todo = data.tasks.length - completed - active;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('My work',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text(
                              'Track assignments from all your clubs.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _TaskCount(
                                    label: 'To do',
                                    value: todo,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer),
                                const SizedBox(width: 8),
                                _TaskCount(
                                    label: 'Active',
                                    value: active,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer),
                                const SizedBox(width: 8),
                                _TaskCount(
                                    label: 'Done',
                                    value: completed,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const SectionHeader('Assignments'),
                          ],
                        );
                      }
                      final task = data.tasks[index - 1];
                      final club = task['clubs'] as Map<String, dynamic>? ?? {};
                      final assignee =
                          task['profiles'] as Map<String, dynamic>? ?? {};
                      final status = '${task['status'] ?? 'todo'}';
                      final canUpdate = task['assigned_to'] == repo.userId ||
                          data.memberships.any((membership) =>
                              '${membership['club_id']}' ==
                                  '${task['club_id']}' &&
                              canAssign(membership));
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('${task['title']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                  ),
                                  StatusChip(status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('${club['name'] ?? 'Club'}'),
                              if ('${task['description'] ?? ''}'
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('${task['description']}'),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                'Assigned to ${assignee['full_name'] ?? (task['assigned_to'] == null ? 'the club' : 'member')}'
                                '${task['due_at'] == null ? '' : ' · Due ${formatDate(task['due_at'])}'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (canUpdate && status != 'completed') ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (status == 'todo')
                                      OutlinedButton(
                                        onPressed: () =>
                                            updateTask(task, 'in_progress'),
                                        child: const Text('Start'),
                                      ),
                                    FilledButton(
                                      onPressed: () =>
                                          updateTask(task, 'completed'),
                                      child: const Text('Complete'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _TaskCount extends StatelessWidget {
  const _TaskCount({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
              Text(label),
            ],
          ),
        ),
      );
}

class _TaskData {
  const _TaskData({required this.memberships, required this.tasks});
  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> tasks;
}

class _NewTask {
  const _NewTask({
    required this.clubId,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.dueAt,
  });
  final String clubId;
  final String title;
  final String description;
  final String? assignedTo;
  final DateTime? dueAt;
}

class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog({required this.memberships});
  final List<Map<String, dynamic>> memberships;

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final title = TextEditingController();
  final description = TextEditingController();
  late String clubId = '${widget.memberships.first['club_id']}';
  String? assignedTo;
  DateTime? dueAt;
  List<Map<String, dynamic>> members = [];
  bool loadingMembers = true;

  @override
  void initState() {
    super.initState();
    loadMembers();
  }

  Future<void> loadMembers() async {
    final rows = List<Map<String, dynamic>>.from(await Supabase.instance.client
        .from('club_memberships')
        .select(
            'user_id, profiles!club_memberships_user_id_fkey(full_name,email)')
        .eq('club_id', clubId)
        .eq('status', 'active'));
    if (mounted) {
      setState(() {
        members = rows;
        assignedTo = null;
        loadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign a task'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: clubId,
                decoration: const InputDecoration(labelText: 'Club'),
                items: widget.memberships.map((membership) {
                  final club =
                      membership['clubs'] as Map<String, dynamic>? ?? {};
                  return DropdownMenuItem(
                    value: '${membership['club_id']}',
                    child: Text('${club['name'] ?? 'Club'}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    clubId = value;
                    loadingMembers = true;
                  });
                  loadMembers();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Task title'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Details'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: assignedTo,
                decoration: const InputDecoration(labelText: 'Assign to'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Entire club')),
                  ...members.map((membership) {
                    final profile =
                        membership['profiles'] as Map<String, dynamic>? ?? {};
                    return DropdownMenuItem(
                      value: '${membership['user_id']}',
                      child:
                          Text('${profile['full_name'] ?? profile['email']}'),
                    );
                  }),
                ],
                onChanged:
                    loadingMembers ? null : (value) => assignedTo = value,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (selected != null) setState(() => dueAt = selected);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(dueAt == null
                    ? 'Set due date'
                    : 'Due ${formatDate(dueAt, time: false)}'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _NewTask(
                      clubId: clubId,
                      title: title.text.trim(),
                      description: description.text.trim(),
                      assignedTo: assignedTo,
                      dueAt: dueAt,
                    ),
                  ),
          child: const Text('Assign'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }
}
