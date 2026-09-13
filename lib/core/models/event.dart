/// A special programme attended across all locations (e.g. Janmashtami).
///
/// Creating one also creates a session per location, so each location admin
/// marks their own boys while the super admin sees the combined picture.
class Event {
  final String id;
  final String title;
  final DateTime eventDate;
  final String? notes;
  final DateTime createdAt;

  const Event({
    required this.id,
    required this.title,
    required this.eventDate,
    this.notes,
    required this.createdAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
