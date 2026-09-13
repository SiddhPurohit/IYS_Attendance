import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/event.dart';

final _client = Supabase.instance.client;

/// All events, newest first.
final eventsListProvider = FutureProvider<List<Event>>((ref) async {
  final response =
      await _client.from('events').select().order('event_date', ascending: false);
  return (response as List).map((e) => Event.fromJson(e)).toList();
});

/// A single event.
final eventByIdProvider =
    FutureProvider.family<Event?, String>((ref, eventId) async {
  final response =
      await _client.from('events').select().eq('id', eventId).maybeSingle();
  if (response == null) return null;
  return Event.fromJson(response);
});

/// Per-location attendance breakdown for one event — the bird's-eye view.
///
/// Each row carries location_id, location_name, session_id, present_count,
/// total_marked and the devotee names themselves (present_names /
/// absent_names), sorted by location. Counts are derived from the same rows
/// as the names, so the two can never disagree.
final eventSummaryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, eventId) async {
  final sessionsRes = await _client
      .from('sessions')
      .select('id, location_id, locations(name)')
      .eq('event_id', eventId);
  final sessions = List<Map<String, dynamic>>.from(sessionsRes);
  if (sessions.isEmpty) return [];

  final sessionIds = sessions.map((s) => s['id'] as String).toList();
  final attendanceRes = await _client
      .from('attendance')
      .select('session_id, present, members(full_name)')
      .inFilter('session_id', sessionIds);

  final presentBySession = <String, List<String>>{};
  final absentBySession = <String, List<String>>{};
  for (final row in List<Map<String, dynamic>>.from(attendanceRes)) {
    final sessionId = row['session_id'] as String;
    final member = row['members'] as Map<String, dynamic>?;
    final name = member?['full_name'] as String? ?? 'Unknown';
    if (row['present'] == true) {
      (presentBySession[sessionId] ??= []).add(name);
    } else {
      (absentBySession[sessionId] ??= []).add(name);
    }
  }

  final rows = sessions.map((s) {
    final sessionId = s['id'] as String;
    final loc = s['locations'] as Map<String, dynamic>?;
    final present = (presentBySession[sessionId] ?? <String>[])..sort();
    final absent = (absentBySession[sessionId] ?? <String>[])..sort();
    return {
      'session_id': sessionId,
      'location_id': s['location_id'] as String,
      'location_name': loc?['name'] as String? ?? '',
      'present_names': present,
      'absent_names': absent,
      'present_count': present.length,
      'total_marked': present.length + absent.length,
    };
  }).toList();

  rows.sort((a, b) => (a['location_name'] as String)
      .compareTo(b['location_name'] as String));
  return rows;
});

/// Creates an event plus one session per location, so every location can
/// mark attendance for it. Super admin only — RLS rejects anyone else.
Future<void> createEvent({
  required String title,
  required DateTime date,
  String? notes,
}) async {
  final userId = _client.auth.currentUser!.id;
  final dateStr = date.toIso8601String().split('T').first;

  final event = await _client
      .from('events')
      .insert({
        'title': title,
        'event_date': dateStr,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'created_by': userId,
      })
      .select()
      .single();

  final locations = await _client.from('locations').select('id');

  await _client.from('sessions').insert(
        (locations as List)
            .map((loc) => {
                  'location_id': loc['id'],
                  'session_date': dateStr,
                  'notes': title,
                  'created_by': userId,
                  'event_id': event['id'],
                })
            .toList(),
      );
}

/// Deletes an event, the per-location sessions it created and all of their
/// attendance. Attendance is cleared explicitly rather than relying on the
/// foreign key cascade, so it works regardless of how it is configured.
Future<void> deleteEvent(String eventId) async {
  final sessions =
      await _client.from('sessions').select('id').eq('event_id', eventId);
  final sessionIds =
      (sessions as List).map((s) => s['id'] as String).toList();

  if (sessionIds.isNotEmpty) {
    await _client.from('attendance').delete().inFilter('session_id', sessionIds);
    await _client.from('sessions').delete().eq('event_id', eventId);
  }
  await _client.from('events').delete().eq('id', eventId);
}
