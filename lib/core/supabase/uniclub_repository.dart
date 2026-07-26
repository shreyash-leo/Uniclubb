import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class UniClubRepository {
  UniClubRepository([SupabaseClient? client])
      : client = client ?? Supabase.instance.client;

  final SupabaseClient client;
  static const _uuid = Uuid();

  User? get user => client.auth.currentUser;
  String get userId {
    final authenticatedUser = user;
    if (authenticatedUser == null) {
      throw StateError('This action requires an authenticated user.');
    }
    return authenticatedUser.id;
  }

  Future<Map<String, dynamic>?> profile([String? id]) async {
    var value = await client
        .from('profiles')
        .select('*, colleges(name, short_name)')
        .eq('id', id ?? userId)
        .maybeSingle();
    if (value == null && id == null) {
      await client.rpc('ensure_user_profile');
      value = await client
          .from('profiles')
          .select('*, colleges(name, short_name)')
          .eq('id', userId)
          .maybeSingle();
    }
    return value;
  }

  Stream<List<Map<String, dynamic>>> upcomingEvents() => _withInitialEmpty(
        client
            .from('events')
            .stream(primaryKey: ['id'])
            .eq('status', 'published')
            .order('starts_at')
            .map((rows) => rows.cast<Map<String, dynamic>>()),
      );

  Stream<List<Map<String, dynamic>>> notifications() => _withInitialEmpty(
        client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .map((rows) => rows.cast<Map<String, dynamic>>()),
      );

  Stream<List<Map<String, dynamic>>> posts() => _withInitialEmpty(
        client
            .from('posts')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false)
            .limit(100)
            .map((rows) => rows.cast<Map<String, dynamic>>()),
      );

  Future<List<Map<String, dynamic>>> homeFeedPosts() async {
    final values = await Future.wait<dynamic>([
      profile(),
      client.from('club_follows').select('club_id').eq('user_id', userId),
      client
          .from('posts')
          .select(
            '*, profiles!posts_author_id_fkey('
            'full_name,username,avatar_url,college_id), '
            'clubs(name,logo_url,college_id), '
            'post_likes(user_id), post_comments(id)',
          )
          .eq('visibility', 'public')
          .order('created_at', ascending: false)
          .limit(100),
    ]);
    final currentProfile =
        values[0] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final collegeId = currentProfile['college_id'];
    final followedClubIds = List<Map<String, dynamic>>.from(values[1] as List)
        .map((row) => '${row['club_id']}')
        .toSet();
    final rows =
        List<Map<String, dynamic>>.from(values[2] as List).where((row) {
      if (collegeId == null) return true;
      final club = row['clubs'] as Map? ?? const {};
      final author = row['profiles'] as Map? ?? const {};
      return club['college_id'] == collegeId ||
          (row['club_id'] == null && author['college_id'] == collegeId);
    }).toList(growable: false);
    for (final row in rows) {
      final likes = (row['post_likes'] as List?)?.length ?? 0;
      final comments = (row['post_comments'] as List?)?.length ?? 0;
      final createdAt = DateTime.tryParse('${row['created_at']}');
      final ageHours = createdAt == null
          ? 720
          : DateTime.now().difference(createdAt).inHours.clamp(0, 720);
      final followed = followedClubIds.contains('${row['club_id']}');
      row['feed_source'] = followed ? 'following' : 'trending';
      row['feed_score'] =
          (followed ? 1000000 : 0) + likes * 100 + comments * 140 - ageHours;
    }
    final following = rows
        .where((row) => row['feed_source'] == 'following')
        .toList(growable: true)
      ..sort(
          (a, b) => (b['feed_score'] as num).compareTo(a['feed_score'] as num));
    final trending = rows
        .where((row) => row['feed_source'] == 'trending')
        .toList(growable: true)
      ..sort(
          (a, b) => (b['feed_score'] as num).compareTo(a['feed_score'] as num));
    final feed = <Map<String, dynamic>>[];
    while (following.isNotEmpty || trending.isNotEmpty) {
      for (var index = 0; index < 3 && following.isNotEmpty; index++) {
        feed.add(following.removeAt(0));
      }
      if (trending.isNotEmpty) feed.add(trending.removeAt(0));
      if (following.isEmpty && trending.isNotEmpty) {
        feed.addAll(trending);
        trending.clear();
      }
    }
    return feed;
  }

  Future<List<Map<String, dynamic>>> recommendedEvents({
    List<String>? types,
    int limit = 50,
  }) async {
    var query = client
        .from('events')
        .select('*, clubs(name,logo_url,college_id)')
        .eq('status', 'published')
        .gte('ends_at', DateTime.now().toUtc().toIso8601String());
    if (types != null && types.isNotEmpty) {
      query = query.inFilter('event_type', types);
    }
    final values = await Future.wait<dynamic>([
      profile(),
      query.order('starts_at').limit(limit),
    ]);
    final currentProfile =
        values[0] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final collegeId = currentProfile['college_id'];
    return List<Map<String, dynamic>>.from(values[1] as List).where((event) {
      if (collegeId == null) return true;
      final club = event['clubs'] as Map? ?? const {};
      return club['college_id'] == collegeId;
    }).toList(growable: false);
  }

  Future<void> setPostLiked(String postId, bool liked) async {
    if (liked) {
      await client.from('post_likes').upsert(
        {'post_id': postId, 'user_id': userId},
        onConflict: 'post_id,user_id',
        ignoreDuplicates: true,
      );
    } else {
      await client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    }
  }

  Stream<List<Map<String, dynamic>>> _withInitialEmpty(
    Stream<List<Map<String, dynamic>>> source,
  ) async* {
    yield const <Map<String, dynamic>>[];
    yield* source;
  }

  Future<List<Map<String, dynamic>>> globalSearch(String query) async {
    if (query.trim().isEmpty) return [];
    final result = await client.rpc('global_search',
        params: {'search_text': query.trim(), 'result_limit': 50});
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<List<Map<String, dynamic>>> clubs() async =>
      List<Map<String, dynamic>>.from(await client
          .from('clubs')
          .select('*, colleges(name, short_name)')
          .order('name'));

  Future<List<Map<String, dynamic>>> discoverClubs() async {
    final values = await Future.wait<dynamic>([
      profile(),
      client.rpc('discover_clubs', params: {'result_limit': 100}),
    ]);
    final currentProfile =
        values[0] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final collegeId = currentProfile['college_id'];
    return List<Map<String, dynamic>>.from(values[1] as List)
        .where((club) => collegeId == null || club['college_id'] == collegeId)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> clubPublicCounts(String clubId) async =>
      Map<String, dynamic>.from(
        await client.rpc('club_public_counts', params: {'target_club': clubId})
                as Map? ??
            const {},
      );

  Future<Map<String, dynamic>> profilePublicCounts(String profileId) async =>
      Map<String, dynamic>.from(
        await client.rpc('profile_public_counts',
                params: {'target_user': profileId}) as Map? ??
            const {},
      );

  Future<Map<String, dynamic>> directConversation(String targetUserId) async =>
      Map<String, dynamic>.from(
        await client.rpc('get_or_create_direct_conversation',
            params: {'target_user': targetUserId}) as Map,
      );

  Future<List<Map<String, dynamic>>> clubPeopleSearch(String query) async {
    final results = (await globalSearch(query))
        .where((row) => row['kind'] == 'user' && '${row['id']}' != userId)
        .toList(growable: false);
    if (results.isEmpty) return const [];

    final allowed = await sharedClubMemberIds();
    return results
        .where((row) => allowed.contains('${row['id']}'))
        .toList(growable: false);
  }

  Future<Set<String>> sharedClubMemberIds() async {
    final memberships = await myMemberships();
    final clubIds =
        memberships.map((row) => '${row['club_id']}').toSet().toList();
    if (clubIds.isEmpty) return <String>{};
    final rows = List<Map<String, dynamic>>.from(await client
        .from('club_memberships')
        .select('user_id')
        .inFilter('club_id', clubIds)
        .eq('status', 'active'));
    return rows.map((row) => '${row['user_id']}').toSet();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String body,
  }) =>
      client.from('messages').insert({
        // A client-generated primary key makes retries and realtime
        // reconciliation deterministic.
        'id': _uuid.v4(),
        'conversation_id': conversationId,
        'sender_id': userId,
        'body': body,
      });

  Future<List<Map<String, dynamic>>> myMemberships() async =>
      List<Map<String, dynamic>>.from(await client
          .from('club_memberships')
          .select('*, clubs(*), club_positions(*)')
          .eq('user_id', userId)
          .eq('status', 'active'));

  Future<List<Map<String, dynamic>>> myRegistrations() async =>
      List<Map<String, dynamic>>.from(await client
          .from('event_registrations')
          .select('*, events(*), event_ticket_types(*)')
          .eq('user_id', userId)
          .order('registered_at', ascending: false));

  Future<String> upload({
    required String bucket,
    required Uint8List bytes,
    required String extension,
    String? folder,
  }) async {
    final path = '${folder ?? userId}/${_uuid.v4()}.$extension';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    if (bucket == 'receipts' || bucket == 'certificates') {
      // Private object paths are durable. Generate a short-lived signed URL
      // only when the authorized user opens the file.
      return path;
    }
    return client.storage.from(bucket).getPublicUrl(path);
  }

  Future<String> privateFileUrl(String bucket, String path) =>
      client.storage.from(bucket).createSignedUrl(path, 900);

  Future<void> markNotificationRead(String id) => client
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);

  Future<void> markAllNotificationsRead() => client
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()})
      .eq('user_id', userId)
      .isFilter('read_at', null);

  Future<void> followClub(String clubId, bool follow) async {
    if (follow) {
      await client
          .from('club_follows')
          .upsert({'club_id': clubId, 'user_id': userId});
    } else {
      await client
          .from('club_follows')
          .delete()
          .eq('club_id', clubId)
          .eq('user_id', userId);
    }
  }

  Future<void> applyToClub(String clubId) async {
    final existing = await client
        .from('club_memberships')
        .select('status')
        .eq('club_id', clubId)
        .eq('user_id', userId)
        .maybeSingle();
    final status = existing?['status'];
    if (status == 'active') {
      throw StateError('You are already a member of this club.');
    }
    if (status == 'pending' || status == 'waitlisted') {
      throw StateError('Your join request is already being reviewed.');
    }
    await client.from('club_memberships').upsert({
      'club_id': clubId,
      'user_id': userId,
      'status': 'pending',
      'ended_at': null,
    }, onConflict: 'club_id,user_id');
  }

  Future<void> invokeDeleteAccount() async {
    final response = await client.functions.invoke('delete-account');
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Account deletion failed.');
    }
    await client.auth.signOut();
  }
}
