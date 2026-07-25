class Club {
  final String id;
  final String name;
  final String category;
  final String logoUrl;
  final String bannerUrl;
  final String description;
  final String createdBy;

  final String presidentId;
  final String supervisorId;
  final List<String> members; // ✅ FIXED

  Club({
    required this.id,
    required this.name,
    required this.category,
    required this.logoUrl,
    required this.bannerUrl,
    required this.description,
    required this.createdBy,
    required this.presidentId,
    required this.supervisorId,
    required this.members,
  });

  factory Club.fromFirestore(Map<String, dynamic> data, String docId) {
    return Club(
      id: docId,
      name: data['name'] ?? '',
      category: data['category'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      bannerUrl: data['bannerUrl'] ?? '',
      description: data['description'] ?? '',
      createdBy: data['createdBy'] ?? '',
      presidentId: data['presidentId'] ?? '',
      supervisorId: data['supervisorId'] ?? '',
      members: (data['members'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'logoUrl': logoUrl,
      'bannerUrl': bannerUrl,
      'description': description,
      'createdBy': createdBy,
      'presidentId': presidentId,
      'supervisorId': supervisorId,
      'members': members, // ✅ already correct
    };
  }
}
