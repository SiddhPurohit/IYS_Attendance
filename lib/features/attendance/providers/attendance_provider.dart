import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../core/models/member.dart';
import '../../../core/models/session.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../sessions/providers/sessions_provider.dart';

final _client = Supabase.instance.client;

/// Joins location ids into a stable family key.
///
/// Riverpod compares family arguments by value, and two equal `List`s are
/// never `==` — so passing a List straight through would miss the cache on
/// every rebuild and refetch endlessly. Sorting makes the key order-
/// independent, so selecting Borivali then Malad hits the same cache entry
/// as Malad then Borivali.
String locationKey(Iterable<String> locationIds) {
  final ids = locationIds.where((id) => id.isNotEmpty).toSet().toList()..sort();
  return ids.join(',');
}

List<String> _splitKey(String key) =>
    key.split(',').where((s) => s.isNotEmpty).toList();

/// Fetches the active members eligible for a given session date across one
/// or more locations — i.e. those whose joining date is on or before that
/// date — sorted by name.
///
/// Members who joined later are excluded so that a session predating them is
/// never marked against them, which would otherwise skew their percentage.
///
/// [params.locationIds] must come from [locationKey].
final activeMembersProvider =
    FutureProvider.family<List<Member>, ({String locationIds, String date})>(
        (ref, params) async {
  final ids = _splitKey(params.locationIds);
  if (ids.isEmpty) return const [];

  final response = await _client
      .from('members')
      .select()
      .inFilter('location_id', ids)
      .eq('is_active', true)
      .lte('joined_on', params.date)
      .order('full_name');

  return (response as List).map((e) => Member.fromJson(e)).toList();
});

/// Attendance already marked for the regular sessions at these locations on
/// this date, merged into one memberId → present map.
///
/// An empty map means nothing has been marked yet anywhere in the
/// selection, which is what the UI uses to decide between "default everyone
/// to present" and "load what was saved before".
///
/// [params.locationIds] must come from [locationKey].
final existingAttendanceForDateProvider = FutureProvider.family<Map<String, bool>,
    ({String locationIds, String date})>((ref, params) async {
  final ids = _splitKey(params.locationIds);
  if (ids.isEmpty) return const {};

  final sessions = await _client
      .from('sessions')
      .select('id')
      .inFilter('location_id', ids)
      .eq('session_date', params.date)
      // Regular sessions only — an event on the same day is marked separately.
      .isFilter('event_id', null);

  final sessionIds =
      (sessions as List).map((s) => s['id'] as String).toList();
  if (sessionIds.isEmpty) return const {};

  final rows = await _client
      .from('attendance')
      .select('member_id, present')
      .inFilter('session_id', sessionIds);

  return {
    for (final row in rows as List)
      row['member_id'] as String: row['present'] as bool? ?? false,
  };
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

/// Saves a combined roster that may span several locations.
///
/// Each member's attendance is written to the session for *their own*
/// location, creating those sessions on demand. So an admin marking
/// Borivali and Malad together in one screen produces one session row per
/// location — which is what keeps `attendance_summary_by_location`, the
/// dashboard trend and the location bar chart exact.
///
/// Routing is driven by `member.locationId` rather than by the selected
/// locations, so a member can never land on another location's session.
/// A selected location with no eligible members gets no session at all,
/// consistent with sessions only existing once something is marked.
Future<void> saveAttendanceAcrossLocations({
  required String date,
  required List<Member> members,
  required Map<String, bool> attendanceMap,
}) async {
  final byLocation = <String, List<Member>>{};
  for (final member in members) {
    (byLocation[member.locationId] ??= []).add(member);
  }

  for (final entry in byLocation.entries) {
    final session =
        await _getOrCreateSession(locationId: entry.key, date: date);
    await saveAttendanceForSession(
      sessionId: session.id,
      attendanceMap: {
        for (final member in entry.value)
          member.id: attendanceMap[member.id] ?? false,
      },
    );
  }
}

/// Drops every cached list that is derived from attendance rows.
///
/// These are plain (non-autoDispose) providers, so without this a saved
/// change stays invisible — on the session list, the session detail page and
/// the super admin dashboard — until the app is restarted.
void invalidateAttendanceCaches(WidgetRef ref) {
  // Attendance marking itself
  ref.invalidate(existingAttendanceProvider);
  ref.invalidate(existingAttendanceForDateProvider);
  ref.invalidate(activeMembersProvider);
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
