import 'package:flutter_test/flutter_test.dart';
import 'package:uniclub/data/models/club_model.dart';
import 'package:uniclub/features/event/models/event_model.dart';

void main() {
  test('Club ignores invalid member values', () {
    final club = Club.fromFirestore({
      'name': 'Coding Club',
      'members': ['user-1', 42, null, 'user-2'],
    }, 'club-1');

    expect(club.id, 'club-1');
    expect(club.members, ['user-1', 'user-2']);
  });

  test('EventModel parses DateTime values', () {
    final expectedDate = DateTime(2026, 7, 23, 10, 30);
    final event = EventModel.fromMap({
      'title': 'Build Day',
      'date': expectedDate,
    }, 'event-1');

    expect(event.id, 'event-1');
    expect(event.date, expectedDate);
    expect(event.eventType, 'event');
  });

  test('EventModel tolerates an ISO date string', () {
    final event = EventModel.fromMap({
      'date': '2026-08-01T09:00:00.000',
    }, 'event-2');

    expect(event.date, DateTime(2026, 8, 1, 9));
  });
}
