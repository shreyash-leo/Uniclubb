import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
import '../../shared/event_post_card.dart';
import '../../shared/widgets.dart';
import 'event_detail_screen.dart';

class EventsHubScreen extends StatelessWidget {
  const EventsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Events'),
          actions: const [NotificationAction()],
          bottom: const TabBar(
            tabs: [
              Tab(height: 40, text: 'Upcoming'),
              Tab(height: 40, text: 'Hackathons'),
              Tab(height: 40, text: 'Joined'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PublishedEventsView(types: ['event', 'workshop', 'meetup']),
            PublishedEventsView(types: ['hackathon', 'competition']),
            _JoinedEvents(),
          ],
        ),
      ),
    );
  }
}

class PublishedEventsView extends StatefulWidget {
  const PublishedEventsView({super.key, required this.types});
  final List<String> types;

  @override
  State<PublishedEventsView> createState() => _PublishedEventsState();
}

class _PublishedEventsState extends State<PublishedEventsView> {
  final repo = UniClubRepository();
  late Future<List<Map<String, dynamic>>> future = load();

  Future<List<Map<String, dynamic>>> load() =>
      repo.recommendedEvents(types: widget.types);

  Future<void> refresh() async {
    final next = load();
    setState(() {
      future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error, onRetry: refresh);
        }
        if (!snapshot.hasData) return const SkeletonList();
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No upcoming events',
            message: 'Published campus events will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final event = snapshot.data![index];
              return EventPostCard(
                event: event,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailScreen(event: event),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _JoinedEvents extends StatefulWidget {
  const _JoinedEvents();

  @override
  State<_JoinedEvents> createState() => _JoinedEventsState();
}

class _JoinedEventsState extends State<_JoinedEvents> {
  final repo = UniClubRepository();
  late Future<List<Map<String, dynamic>>> future = repo.myRegistrations();

  Future<void> refresh() async {
    final next = repo.myRegistrations();
    setState(() {
      future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorState(error: snapshot.error, onRetry: refresh);
        }
        if (!snapshot.hasData) return const SkeletonList();
        if (snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No joined events',
            message: 'Events you register for will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final registration = snapshot.data![index];
              final event =
                  registration['events'] as Map<String, dynamic>? ?? const {};
              return EventPostCard(
                event: event,
                status: '${registration['status']}',
                onTap: event.isEmpty
                    ? () {}
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => EventDetailScreen(event: event),
                          ),
                        ),
              );
            },
          ),
        );
      },
    );
  }
}
