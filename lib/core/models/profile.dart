/// User profile from the `profiles` table (1:1 with auth.users).
///
/// Deliberately has no location field. An admin's locations live in the
/// `admin_locations` table (an admin may have several) — read them with
/// `accessibleLocationsProvider`, never from here. The `profiles.location_id`
/// column still exists but is legacy and is consulted by nothing.
class Profile {
  final String id;
  final String fullName;
  final String role; // 'admin' | 'super_admin'
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'super_admin';
}
