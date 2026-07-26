import 'package:flutter_test/flutter_test.dart';
import 'package:uniclub/features/messaging/messages_screen.dart';

void main() {
  test('realtime message rows are deduplicated by primary key', () {
    final result = uniqueMessagesById([
      {
        'id': 'message-1',
        'body': 'Hello',
        'created_at': '2026-07-25T10:00:00Z',
      },
      {
        'id': 'message-1',
        'body': 'Hello',
        'created_at': '2026-07-25T10:00:00Z',
      },
      {
        'id': 'message-2',
        'body': 'World',
        'created_at': '2026-07-25T10:01:00Z',
      },
    ]);

    expect(result, hasLength(2));
    expect(result.map((row) => row['id']), ['message-1', 'message-2']);
  });
}
