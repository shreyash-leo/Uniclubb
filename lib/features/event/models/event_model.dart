class EventModel {
  final String id;
  final String title;
  final String clubId;
  final String clubName;
  final String clubLogoUrl;
  final String flyerUrl;
  final String description;
  final String venue;
  final DateTime date;
  final String createdBy;
  final bool registrationRequired;
  final String category;
  final String eventType; // "normal" | "hackathon" - 🔥 ADDED

  final Map<String, dynamic>? registrationConfig;

  EventModel({
    required this.id,
    required this.title,
    required this.clubId,
    required this.clubName,
    required this.clubLogoUrl,
    required this.flyerUrl,
    required this.description,
    required this.venue,
    required this.date,
    required this.createdBy,
    required this.registrationRequired,
    required this.category,
    required this.eventType, // 🔥 ADDED
    this.registrationConfig,
  });

  factory EventModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawDate = map['starts_at'] ?? map['date'];
    final date = switch (rawDate) {
      DateTime value => value,
      String value => DateTime.tryParse(value) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    return EventModel(
      id: docId,
      title: map['title'] ?? '',
      clubId: map['club_id'] ?? map['clubId'] ?? '',
      clubName: map['club_name'] ?? map['clubName'] ?? '',
      clubLogoUrl: map['club_logo_url'] ?? map['clubLogoUrl'] ?? '',
      flyerUrl: map['flyer_url'] ?? map['flyerUrl'] ?? '',
      description: map['description'] ?? '',
      venue: map['venue_name'] ?? map['venue'] ?? '',
      date: date,
      createdBy: map['created_by'] ?? map['createdBy'] ?? '',
      registrationRequired: (map['registrationRequired'] as bool?) ??
          map['registration_deadline'] != null,
      category: map['category'] ?? '',
      eventType: map['event_type'] ?? map['eventType'] ?? 'event',
      registrationConfig:
          map['registration_schema'] ?? map['registrationConfig'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'club_id': clubId,
      'club_name': clubName,
      'club_logo_url': clubLogoUrl,
      'flyer_url': flyerUrl,
      'description': description,
      'venue_name': venue,
      'starts_at': date.toUtc().toIso8601String(),
      'created_by': createdBy,
      'registrationRequired': registrationRequired,
      'category': category,
      'event_type': eventType,
      'registration_schema': registrationConfig,
    };
  }
}
