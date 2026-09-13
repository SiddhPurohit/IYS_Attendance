import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../core/models/member.dart';
import '../../../core/models/session.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../sessions/providers/sessions_provider.dart';

final _client = Supabase.instance.client;

/// Fetches the active members eligible for a given session date — i.e. those
/// whose joining date is on or before that date — sorted by name.
///
/// Members who joined later are excluded so that a session predating them is
/// never marked against them, which would otherwise skew their percentage.
final activeMembersProvider =
    FutureProvider.family<List<Member>, ({String locationId, String date})>(
        (ref, params) async {
  final response = await _client
      .from('members')
      .select()
      .eq('location_id', params.locationId)
      .eq('is_active', true)
      .lte('joined_on', params.date)
      .order('full_name');

  return (response as List).map((e) => Member.fromJson(e)).toList();
});

/// Looks up an existing session for the given location + date, if any.
/// Does NOT create one — creation only happens when attendance is saved,
/// so simply browsing a date never pollutes the sessions table.
final existingSessionProvider =
    FutureProvider.family<Session?, ({String locationId, String date})>(
        (ref, params) async {
  final existing = await _client
      .from('sessions')
      .select()
      .eq('location_id', params.locationId)
      .eq('session_date', params.date)
      .isFilter('event_id', null)
      .maybeSingle();

  if (existing == null) return null;
  return Session.fromJson(existing);
});

/// Fetches existing attendance records for a session.
/// Returns a Map of memberId → present.
final existingAttendanceProvider =
    FutureProvider.family<Map<String, bool>, String>(
        (ref, sessionId) async {
  final response = await _client
      .from('attendance')
      .select()
      .eq('session_id', sessionId);

  final map = <String, bool>{};
  for (final row in response) {
    map[row['member_id'] as String] = row['present'] as bool? ?? false;
  }
  return map;
});

/// Finds the session for [locationId] + [date], creating it if it doesn't
/// exist yet. Only called at save time — never while just viewing a date.
Future<Session> _getOrCreateSession({
  required String locationId,
  required String date,
}) async {
  final existing = await _client
      .from('sessions')
      .select()
      .eq('location_id', locationId)
      .eq('session_date', date)
      // Never pick up an event session held on the same day.
      .isFilter('event_id', null)
      .maybeSingle();

  if (existing != null) return Session.fromJson(existing);

  final userId = _client.auth.currentUser!.id;
  final inserted = await _client
      .from('sessions')
      .insert({
        'location_id': locationId,
        'session_date': date,
        'created_by': userId,
      })
      .select()
      .single();

  return Session.fromJson(inserted);
}

/// Saves attendance against an existing session — used when marking or
/// editing a specific session, including event sessions.
/// [attendanceMap] is memberId → present.
Future<void> saveAttendanceForSession({
  required String sessionId,
  required Map<String, bool> attendanceMap,
}) async {
  final userId = _client.auth.currentUser!.id;

  final rows = attendanceMap.entries.map((e) => {
        'session_id': sessionId,
        'member_id': e.key,
        'present': e.value,
        'marked_by': userId,
      }).toList();

  await _client.from('attendance').upsert(
    rows,
    onConflict: 'session_id,member_id',
  );
}

/// Saves attendance for the regular session on [date] at [locationId],
/// creating that session on-demand if this is the first save for the day.
Future<void> saveAttendance({
  required String locationId,
  required String date,
  required Map<String, bool> attendanceMap,
}) async {
  final session = await _getOrCreateSession(locationId: locationId, date: date);
  await saveAttendanceForSession(
    sessionId: session.id,
    attendanceMap: attendanceMap,
  );
}

/// Drops every cached list that is derived from attendance rows.
///
/// These are plain (non-autoDispose) providers, so without this a saved
/// change stays invisible — on the session list, the session detail page and
/// the super admin dashboard — until the app is restarted.
void invalidateAttendanceCaches(WidgetRef ref) {
  // Attendance marking itself
  ref.invalidate(existingSessionProvider);
  ref.invalidate(existingAttendanceProvider);
  // Sessions list + detail
  ref.invalidate(sessionsListProvider);
  ref.invalidate(sessionDetailProvider);
  ref.invalidate(sessionAttendanceListProvider);
  // Super admin dashboard + member history
  ref.invalidate(locationSummaryProvider);
  ref.invalidate(memberSummaryProvider);
  ref.invalidate(memberAttendanceHistoryProvider);
  // Event roll-ups
  ref.invalidate(eventsListProvider);
  ref.invalidate(eventSummaryProvider);
}
