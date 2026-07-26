import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/notification_action.dart';
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
            isScrollable: true,
            tabs: [
              Tab(text: 'Upcoming events'),
              Tab(text: 'Hackathons'),
              Tab(text: 'Joined events'),
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
              final club = event['clubs'] as Map<String, dynamic>? ?? const {};
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => EventDetailScreen(event: event),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NetworkPicture(
                        url: event['flyer_url'] as String?,
                        width: double.infinity,
                        height: 176,
                        borderRadius: 0,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${event['title']}',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 5),
                            Text(
                                '${club['name'] ?? 'Campus'} · ${formatDate(event['starts_at'])}'),
                            const SizedBox(height: 4),
                            Text(
                              '${event['venue_name'] ?? 'Venue to be announced'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
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
          ),
        );
      },
    );
  }
}
