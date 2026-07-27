import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/supabase/uniclub_repository.dart';
import '../../shared/event_post_card.dart';
import '../../shared/notification_action.dart';
import '../../shared/widgets.dart';
import '../club/clubs_hub_screen.dart';
import '../event/event_detail_screen.dart';
import '../profile/public_profile_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({
    super.key,
    this.embedded = false,
    this.clubsOnly = false,
  });
  final bool embedded;
  final bool clubsOnly;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _DiscoverData {
  const _DiscoverData({required this.clubs, required this.events});
  final List<Map<String, dynamic>> clubs;
  final List<Map<String, dynamic>> events;
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const categories = [
    'All',
    'Tech',
    'Cultural',
    'Sports',
    'Academic',
    'Social',
    'Entrepreneurship',
  ];

  final repo = UniClubRepository();
  final controller = TextEditingController();
  Timer? debounce;
  late Future<_DiscoverData> discover = loadDiscover();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  Object? searchError;
  String kind = 'all';
  String category = 'All';
  String clubType = 'All';
  bool recruitingOnly = false;
  bool verifiedOnly = false;
  String sort = 'trending';

  @override
  void initState() {
    super.initState();
    if (widget.clubsOnly) kind = 'club';
  }

  Future<_DiscoverData> loadDiscover() async {
    final values = await Future.wait([
      repo.discoverClubs(),
      repo.client
          .from('events')
          .select()
          .eq('status', 'published')
          .gte('ends_at', DateTime.now().toIso8601String())
          .order('starts_at')
          .limit(12),
    ]);
    return _DiscoverData(
      clubs: List<Map<String, dynamic>>.from(values[0] as List),
      events: List<Map<String, dynamic>>.from(values[1] as List),
    );
  }

  Future<void> search() async {
    final query = controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        results = [];
        searchError = null;
      });
      return;
    }
    setState(() {
      loading = true;
      searchError = null;
    });
    try {
      var rows = await repo.globalSearch(query);
      rows = rows.where((row) {
        if (kind != 'all' && row['kind'] != kind) return false;
        if (category != 'All' &&
            !'${row['subtitle'] ?? ''}'
                .toLowerCase()
                .contains(category.toLowerCase())) {
          return false;
        }
        return true;
      }).toList(growable: false);
      if (mounted) setState(() => results = rows);
    } catch (error) {
      if (mounted) setState(() => searchError = error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changed(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 320), search);
    setState(() {});
  }

  Future<void> showFilters() async {
    var nextKind = kind;
    var nextCategory = category;
    var nextClubType = clubType;
    var nextRecruitingOnly = recruitingOnly;
    var nextVerifiedOnly = verifiedOnly;
    var nextSort = sort;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .92,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Filter discovery',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setModalState(() {
                          nextKind = widget.clubsOnly ? 'club' : 'all';
                          nextCategory = 'All';
                          nextClubType = 'All';
                          nextRecruitingOnly = false;
                          nextVerifiedOnly = false;
                          nextSort = 'trending';
                        }),
                        child: const Text('Clear'),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Show', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: (widget.clubsOnly
                            ? const {'club': 'Clubs'}
                            : const {
                                'all': 'Everything',
                                'club': 'Clubs',
                                'event': 'Events',
                                'user': 'People',
                              })
                        .entries
                        .map((entry) => ChoiceChip(
                              selected: nextKind == entry.key,
                              label: Text(entry.value),
                              onSelected: (_) =>
                                  setModalState(() => nextKind = entry.key),
                            ))
                        .toList(),
                  ),
                  if (widget.clubsOnly || nextKind == 'club') ...[
                    const SizedBox(height: 18),
                    Text('Club type',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['All', 'official', 'student', 'department']
                          .map((value) => ChoiceChip(
                                selected: nextClubType == value,
                                label: Text(value == 'All'
                                    ? 'All types'
                                    : value[0].toUpperCase() +
                                        value.substring(1)),
                                onSelected: (_) =>
                                    setModalState(() => nextClubType = value),
                              ))
                          .toList(),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: nextRecruitingOnly,
                      onChanged: (value) =>
                          setModalState(() => nextRecruitingOnly = value),
                      title: const Text('Recruiting now'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: nextVerifiedOnly,
                      onChanged: (value) =>
                          setModalState(() => nextVerifiedOnly = value),
                      title: const Text('Verified clubs only'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('Category',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: categories
                        .map((value) => FilterChip(
                              selected: nextCategory == value,
                              label: Text(value),
                              onSelected: (_) =>
                                  setModalState(() => nextCategory = value),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: nextSort,
                    decoration: const InputDecoration(labelText: 'Sort by'),
                    items: const [
                      DropdownMenuItem(
                          value: 'trending', child: Text('Trending')),
                      DropdownMenuItem(
                          value: 'newest', child: Text('Newest first')),
                      DropdownMenuItem(value: 'name', child: Text('Name A–Z')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => nextSort = value);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply filters'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      kind = nextKind;
      category = nextCategory;
      clubType = nextClubType;
      recruitingOnly = nextRecruitingOnly;
      verifiedOnly = nextVerifiedOnly;
      sort = nextSort;
    });
    if (controller.text.trim().isNotEmpty) await search();
  }

  Future<void> refreshDiscover() async {
    final next = loadDiscover();
    setState(() {
      discover = next;
    });
    await next;
  }

  Future<void> openResult(Map<String, dynamic> row) async {
    if (row['kind'] == 'event') {
      final event = await repo.client
          .from('events')
          .select()
          .eq('id', row['id'])
          .single();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => EventDetailScreen(event: event)),
        );
      }
    } else if (row['kind'] == 'club') {
      final club = await repo.client
          .from('clubs')
          .select('*, colleges(name, short_name)')
          .eq('id', row['id'])
          .single();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => ClubDiscoverDetailScreen(club: club)),
        );
      }
    } else if (row['kind'] == 'user') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PublicProfileScreen(userId: '${row['id']}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discover'),
                  Text('Clubs, events and people',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
                ],
              ),
              actions: const [NotificationAction()],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: changed,
                    onSubmitted: (_) => search(),
                    decoration: InputDecoration(
                      hintText: 'Search clubs, events or people',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                controller.clear();
                                changed('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: kind != (widget.clubsOnly ? 'club' : 'all') ||
                      category != 'All' ||
                      clubType != 'All' ||
                      recruitingOnly ||
                      verifiedOnly ||
                      sort != 'trending',
                  child: IconButton.filledTonal(
                    tooltip: 'Filter and sort',
                    onPressed: showFilters,
                    icon: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${kind == 'all' ? 'Everything' : '${kind[0].toUpperCase()}${kind.substring(1)}s'}'
                ' · $category'
                '${clubType == 'All' ? '' : ' · $clubType'}'
                '${recruitingOnly ? ' · Recruiting' : ''}'
                '${verifiedOnly ? ' · Verified' : ''}'
                ' · ${sort == 'trending' ? 'Trending' : sort == 'newest' ? 'Newest' : 'Name'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: searching
                ? _SearchResults(
                    results: results,
                    error: searchError,
                    onTap: openResult,
                  )
                : FutureBuilder<_DiscoverData>(
                    future: discover,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return AsyncErrorState(
                          error: snapshot.error,
                          onRetry: () {
                            final next = loadDiscover();
                            setState(() {
                              discover = next;
                            });
                          },
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _DiscoverLanding(
                        data: snapshot.data!,
                        category: category,
                        clubType: clubType,
                        recruitingOnly: recruitingOnly,
                        verifiedOnly: verifiedOnly,
                        kind: kind,
                        sort: sort,
                        onRefresh: refreshDiscover,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults(
      {required this.results, required this.error, required this.onTap});
  final List<Map<String, dynamic>> results;
  final Object? error;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    if (error != null) return AsyncErrorState(error: error);
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.manage_search,
        title: 'No matching results',
        message: 'Try a different name, type or category.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = results[index];
        return Card(
          child: ListTile(
            leading: NetworkPicture(
              url: row['image_url'] as String?,
              width: 52,
              height: 52,
              borderRadius: 14,
            ),
            title: Text('${row['title']}'),
            subtitle: Text('${row['kind']} · ${row['subtitle'] ?? ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onTap(row),
          ),
        );
      },
    );
  }
}

class _DiscoverLanding extends StatelessWidget {
  const _DiscoverLanding(
      {required this.data,
      required this.category,
      required this.clubType,
      required this.recruitingOnly,
      required this.verifiedOnly,
      required this.kind,
      required this.sort,
      required this.onRefresh});
  final _DiscoverData data;
  final String category;
  final String clubType;
  final bool recruitingOnly;
  final bool verifiedOnly;
  final String kind;
  final String sort;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (kind == 'user') {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'Find people from your campus',
        message: 'Enter a name or username in the search field.',
      );
    }
    final clubs = List<Map<String, dynamic>>.from(category == 'All'
        ? data.clubs
        : data.clubs
            .where((club) => '${club['category']}' == category)
            .toList());
    clubs.removeWhere((club) =>
        (clubType != 'All' && '${club['club_type']}' != clubType) ||
        (recruitingOnly && club['recruitment_open'] != true) ||
        (verifiedOnly && club['verified'] != true));
    final events = List<Map<String, dynamic>>.from(category == 'All'
        ? data.events
        : data.events
            .where((event) => '${event['category']}' == category)
            .toList());
    if (sort == 'name') {
      clubs.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      events.sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
    } else if (sort == 'newest') {
      clubs
          .sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
      events
          .sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
        children: [
          if (kind != 'event') ...[
            SectionHeader('${clubs.length} clubs'),
            const SizedBox(height: 10),
            if (clubs.isEmpty)
              const EmptyState(
                icon: Icons.search_off,
                title: 'No clubs match these filters',
                message: 'Clear or adjust the filters to see more clubs.',
              )
            else
              ...clubs.map((club) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ClubDiscoverDetailScreen(club: club),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NetworkPicture(
                              url: club['banner_url'] as String?,
                              width: double.infinity,
                              height: 170,
                              borderRadius: 0,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  NetworkPicture(
                                    url: club['logo_url'] as String?,
                                    width: 58,
                                    height: 58,
                                    borderRadius: 16,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text('${club['name']}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                            ),
                                            if (club['verified'] == true)
                                              Icon(Icons.verified,
                                                  size: 19,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${club['category']} · ${club['club_type'] ?? 'Student club'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        if ('${club['description'] ?? ''}'
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text('${club['description']}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                        if (club['recruitment_open'] ==
                                            true) ...[
                                          const SizedBox(height: 8),
                                          const StatusChip('Recruiting'),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
          ],
          if (kind != 'club') ...[
            const SectionHeader('Upcoming events'),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const Text('No upcoming events in this category.')
            else
              ...events.map((event) => EventPostCard(
                    event: event,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => EventDetailScreen(event: event)),
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}
