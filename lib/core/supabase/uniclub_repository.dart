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

  Future<List<Map<String, dynamic>>> discoverClubs() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('discover_clubs', params: {'result_limit': 36})
            as List,
      );

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
