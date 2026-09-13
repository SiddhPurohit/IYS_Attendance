/// A single program session (one date at one location).
class Session {
  final String id;
  final String locationId;
  final DateTime sessionDate;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  const Session({
    required this.id,
    required this.locationId,
    required this.sessionDate,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      locationId: json['location_id'] as String,
      sessionDate: DateTime.parse(json['session_date'] as String),
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'location_id': locationId,
      'session_date': sessionDate.toIso8601String().split('T').first,
      if (notes != null) 'notes': notes,
      'created_by': createdBy,
    };
  }
}
