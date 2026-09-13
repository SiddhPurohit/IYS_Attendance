/// Attendance record for one member in one session.
class Attendance {
  final String? id;
  final String sessionId;
  final String memberId;
  final bool present;
  final String markedBy;
  final DateTime? markedAt;

  const Attendance({
    this.id,
    required this.sessionId,
    required this.memberId,
    required this.present,
    required this.markedBy,
    this.markedAt,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id'] as String?,
      sessionId: json['session_id'] as String,
      memberId: json['member_id'] as String,
      present: json['present'] as bool? ?? false,
      markedBy: json['marked_by'] as String,
      markedAt: json['marked_at'] != null
          ? DateTime.parse(json['marked_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'session_id': sessionId,
      'member_id': memberId,
      'present': present,
      'marked_by': markedBy,
    };
  }
}
