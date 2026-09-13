import 'package:flutter_test/flutter_test.dart';
import 'package:iys_attendance/core/models/location.dart';
import 'package:iys_attendance/core/models/member.dart';
import 'package:iys_attendance/core/models/session.dart';

void main() {
  group('Model Serialization Tests', () {
    test('Location.fromJson creates valid Location', () {
      final json = {
        'id': 'loc-1',
        'name': 'Vasai',
        'created_at': '2025-01-01T00:00:00.000Z',
      };
      final location = Location.fromJson(json);
      expect(location.id, 'loc-1');
      expect(location.name, 'Vasai');
    });

    test('Member.fromJson creates valid Member', () {
      final json = {
        'id': 'mem-1',
        'full_name': 'Rohit Sharma',
        'dob': '2005-04-30T00:00:00.000Z',
        'phone': '9876543210',
        'email': 'rohit@example.com',
        'location_id': 'loc-1',
        'is_active': true,
        'created_by': 'user-1',
        'created_at': '2025-01-01T00:00:00.000Z',
        'joined_on': '2025-01-01',
      };
      final member = Member.fromJson(json);
      expect(member.id, 'mem-1');
      expect(member.fullName, 'Rohit Sharma');
      expect(member.isActive, true);
    });

    test('Session.fromJson creates valid Session', () {
      final json = {
        'id': 'sess-1',
        'location_id': 'loc-1',
        'session_date': '2025-01-05',
        'created_by': 'user-1',
        'created_at': '2025-01-01T00:00:00.000Z',
      };
      final session = Session.fromJson(json);
      expect(session.id, 'sess-1');
      expect(session.sessionDate, DateTime.parse('2025-01-05'));
    });
  });
}
