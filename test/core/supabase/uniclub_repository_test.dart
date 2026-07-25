import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uniclub/core/supabase/uniclub_repository.dart';

void main() {
  late UniClubRepository repository;

  setUp(() {
    repository = UniClubRepository(
      SupabaseClient('https://example.supabase.co', 'public-anon-key'),
    );
  });

  test('empty event feed is available before the realtime query responds',
      () async {
    await expectLater(
      repository.upcomingEvents().first,
      completion(isEmpty),
    );
  });

  test('empty post feed is available before the realtime query responds',
      () async {
    await expectLater(
      repository.posts().first,
      completion(isEmpty),
    );
  });

  test('userId reports an authentication error instead of null assertion', () {
    expect(
      () => repository.userId,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('authenticated user'),
        ),
      ),
    );
  });
}
