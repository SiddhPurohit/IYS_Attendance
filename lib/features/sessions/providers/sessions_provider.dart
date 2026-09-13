import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _client = Supabase.instance.client;

/// Fetches past sessions, optionally filtered to one location.
/// Pass null (or empty) [locationId] to fetch sessions across all locations
/// (used by super admin). Newest first. Each row carries a present/total
/// attendance count computed from the `attendance` table.
final sessionsListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>(
        (ref, locationId) async {
  var query =
      _client.from('sessions').select('*, locations(name), events(title)');
  if (locationId != null && locationId.isNotEmpty) {
    query = query.eq('location_id', locationId);
  }

  final sessionsRes =
      await query.order('session_date', ascending: false);
  final sessions = List<Map<String, dynamic>>.from(sessionsRes);
  if (sessions.isEmpty) return [];

  final sessionIds = sessions.map((s) => s['id'] as String).toList();
  final attendanceRes = await _client
      .from('attendance')
      .select('session_id, present')
      .inFilter('session_id', sessionIds);
  final attendanceRows = List<Map<String, dynamic>>.from(attendanceRes);

  final counts = <String, ({int present, int total})>{};
  for (final row in attendanceRows) {
    final sessionId = row['session_id'] as String;
    final isPresent = row['present'] as bool? ?? false;
    final current = counts[sessionId] ?? (present: 0, total: 0);
    counts[sessionId] = (
      present: current.present + (isPresent ? 1 : 0),
      total: current.total + 1,
    );
  }

  return sessions.map((s) {
    final id = s['id'] as String;
    final loc = s['locations'] as Map<String, dynamic>?;
    final event = s['events'] as Map<String, dynamic>?;
    final c = counts[id] ?? (present: 0, total: 0);
    return {
      'id': id,
      'location_id': s['location_id'] as String,
      'location_name': loc?['name'] as String? ?? '',
      'session_date': s['session_date'] as String,
      'notes': s['notes'] as String?,
      'event_id': s['event_id'] as String?,
      'event_title': event?['title'] as String?,
      'present_count': c.present,
      'total_marked': c.total,
    };
  }).toList();
});

/// Fetches one session's details (date, location, notes) by id.
final sessionDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, sessionId) async {
  final res = await _client
      .from('sessions')
      .select('*, locations(name), events(title)')
      .eq('id', sessionId)
      .maybeSingle();
  if (res == null) return null;

  final loc = res['locations'] as Map<String, dynamic>?;
  final event = res['events'] as Map<String, dynamic>?;
  return {
    'id': res['id'] as String,
    'location_id': res['location_id'] as String,
    'location_name': loc?['name'] as String? ?? '',
    'session_date': res['session_date'] as String,
    'notes': res['notes'] as String?,
    'event_id': res['event_id'] as String?,
    'event_title': event?['title'] as String?,
  };
});

/// Fetches the full attendance list (member name + present/absent) for one
/// session, sorted alphabetically by name.
final sessionAttendanceListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, sessionId) async {
  final res = await _client
      .from('attendance')
      .select('present, marked_at, members(id, full_name)')
      .eq('session_id', sessionId);

  final rows = List<Map<String, dynamic>>.from(res).map((row) {
    final member = row['members'] as Map<String, dynamic>?;
    return {
      'member_id': member?['id'] as String? ?? '',
      'full_name': member?['full_name'] as String? ?? 'Unknown',
      'present': row['present'] as bool? ?? false,
      'marked_at': row['marked_at'] as String?,
    };
  }).toList();

  rows.sort((a, b) =>
      (a['full_name'] as String).compareTo(b['full_name'] as String));
  return rows;
});

/// Permanently deletes a session and every attendance record on it.
///
/// Attendance rows are removed first rather than relying on the foreign
/// key's cascade, so this works regardless of how the constraint is
/// configured. Super admin only — RLS blocks it for location admins.
Future<void> deleteSession(String sessionId) async {
  await _client.from('attendance').delete().eq('session_id', sessionId);
  await _client.from('sessions').delete().eq('id', sessionId);
}
