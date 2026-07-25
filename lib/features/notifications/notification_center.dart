import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/widgets.dart';

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key});

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  final repo = UniClubRepository();
  bool markingAll = false;

  Future<void> markAll() async {
    setState(() => markingAll = true);
    try {
      await repo.markAllNotificationsRead();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  Future<void> markOne(String id) async {
    try {
      await repo.markNotificationRead(id);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  IconData icon(String type) => switch (type) {
        'new_message' => Icons.chat_bubble_outline,
        'event_reminder' => Icons.alarm,
        'registration_update' => Icons.how_to_reg,
        'club_announcement' => Icons.campaign_outlined,
        'join_request' => Icons.group_add_outlined,
        'expense_update' => Icons.receipt_long_outlined,
        'mention' => Icons.alternate_email,
        'invitation' => Icons.mail_outline,
        'new_follower' => Icons.person_add_alt_1_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Preferences',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const NotificationPreferencesScreen())),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Mark all read',
            onPressed: markingAll ? null : markAll,
            icon: markingAll
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.notifications(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorState(error: snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
                icon: Icons.notifications_none, title: 'You are all caught up');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final row = snapshot.data![index];
              final unread = row['read_at'] == null;
              return Card(
                color: unread
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  leading: Icon(icon('${row['type']}')),
                  title: Text('${row['title']}',
                      style: TextStyle(
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w500)),
                  subtitle:
                      Text('${row['body']}\n${formatDate(row['created_at'])}'),
                  isThreeLine: true,
                  onTap: () async {
                    await markOne('${row['id']}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final repo = UniClubRepository();
  Map<String, dynamic>? values;
  Object? loadError;

  static const settings = <String, String>{
    'push_enabled': 'Push notifications',
    'email_enabled': 'Email notifications',
    'registration_updates': 'Registration approved, rejected or waitlisted',
    'club_announcements': 'Club announcements',
    'new_messages': 'New messages',
    'new_events': 'New events',
    'join_requests': 'Join requests',
    'expense_updates': 'Expense approvals',
    'mentions': 'Mentions',
    'invitations': 'Invitations',
  };

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final row = await repo.client
          .from('notification_preferences')
          .select()
          .eq('user_id', repo.userId)
          .maybeSingle();
      final resolved = row ??
          await repo.client
              .from('notification_preferences')
              .upsert({'user_id': repo.userId})
              .select()
              .single();
      if (mounted) {
        setState(() {
          values = resolved;
          loadError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  Future<void> update(String key, bool value) async {
    final previous = values![key] as bool? ?? true;
    setState(() => values![key] = value);
    try {
      await repo.client
          .from('notification_preferences')
          .update({key: value}).eq('user_id', repo.userId);
    } catch (error) {
      if (!mounted) return;
      setState(() => values![key] = previous);
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: loadError != null
          ? AsyncErrorState(
              error: loadError,
              onRetry: () {
                setState(() => loadError = null);
                load();
              },
            )
          : values == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: settings.entries
                      .map((entry) => SwitchListTile(
                            title: Text(entry.value),
                            value: values![entry.key] as bool? ?? true,
                            onChanged: (value) => update(entry.key, value),
                          ))
                      .toList(),
                ),
    );
  }
}
