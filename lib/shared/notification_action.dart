import 'package:flutter/material.dart';

import '../core/supabase/uniclub_repository.dart';
import '../features/notifications/notification_center.dart';

class NotificationAction extends StatelessWidget {
  const NotificationAction({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: UniClubRepository().notifications(),
      builder: (context, snapshot) {
        final unread =
            (snapshot.data ?? []).where((row) => row['read_at'] == null).length;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const NotificationCenter()),
          ),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}
