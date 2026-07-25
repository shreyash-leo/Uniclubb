class AppUser {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;

  final String? college;
  final String? department;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
    this.college,
    this.department,
  });

  factory AppUser.fromFirestore(Map<String, dynamic> data, String id) {
    return AppUser(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      profileImageUrl: data['profileImageUrl'],
      college: data['college'],
      department: data['department'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'college': college,
      'department': department,
    };
  }
}
