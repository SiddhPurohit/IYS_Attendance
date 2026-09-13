/// User profile from the `profiles` table (1:1 with auth.users).
class Profile {
  final String id;
  final String fullName;
  final String role; // 'admin' | 'super_admin'
  final String? locationId;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.locationId,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      locationId: json['location_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'super_admin';
}
