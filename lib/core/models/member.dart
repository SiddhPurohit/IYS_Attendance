/// A devotee enrolled at a location.
class Member {
  final String id;
  final String fullName;
  final DateTime? dob;
  final String? phone;
  final String? email;
  final String locationId;
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;

  /// The day this devotee started attending. Sessions before it do not
  /// count towards attendance. Defaults to today for new devotees.
  final DateTime joinedOn;

  const Member({
    required this.id,
    required this.fullName,
    this.dob,
    this.phone,
    this.email,
    required this.locationId,
    required this.isActive,
    required this.createdBy,
    required this.createdAt,
    required this.joinedOn,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      dob: json['dob'] != null ? DateTime.parse(json['dob'] as String) : null,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      locationId: json['location_id'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      joinedOn: DateTime.parse(json['joined_on'] as String),
    );
  }

  /// Returns the fields to insert/update (excludes id, created_at).
  Map<String, dynamic> toInsertJson() {
    return {
      'full_name': fullName,
      if (dob != null) 'dob': dob!.toIso8601String().split('T').first,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      'location_id': locationId,
      'is_active': isActive,
      'created_by': createdBy,
      'joined_on': joinedOn.toIso8601String().split('T').first,
    };
  }
}
