/// A program location (Vasai, Borivali, Mira Road, Malad).
class Location {
  final String id;
  final String name;
  final DateTime createdAt;

  const Location({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
