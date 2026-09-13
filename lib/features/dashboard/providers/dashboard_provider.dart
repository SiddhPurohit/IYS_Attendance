import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/location.dart';
import '../../../core/models/member.dart';
import '../../../core/providers/auth_provider.dart';

final _client = Supabase.instance.client;

/// Fetches all 4 locations.
///
/// Every authenticated user can read every location (the `locations_read`
/// policy is deliberately open), so this is NOT a permission check — use
/// [accessibleLocationsProvider] for anything the user is allowed to act on.
final allLocationsProvider = FutureProvider<List<Location>>((ref) async {
  final response =
      await _client.from('locations').select().order('name');
  return (response as List).map((e) => Location.fromJson(e)).toList();
});

/// The locations the signed-in user may actually mark attendance for and
/// add devotees to: everything for a super admin, and whatever
/// `admin_locations` grants for everyone else.
///
/// This is the single source of truth for location scope in the client —
/// it replaced `profile.locationId` when admins gained the ability to hold
/// more than one location.
final accessibleLocationsProvider = FutureProvider<List<Location>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return const [];

  final all = await ref.watch(allLocationsProvider.future);
  if (profile.isSuperAdmin) return all;

  final rows = await _client
      .from('admin_locations')
      .select('location_id')
      .eq('profile_id', profile.id);

  final granted = {
    for (final row in rows as List) row['location_id'] as String,
  };
  return all.where((l) => granted.contains(l.id)).toList();
});

/// Fetches a single location's name by id (for display in headers/subtitles).
final locationNameProvider =
    FutureProvider.family<String, String>((ref, locationId) async {
  final data = await _client
      .from('locations')
      .select('name')
      .eq('id', locationId)
      .maybeSingle();
  return (data?['name'] as String?) ?? 'Unknown Location';
});

/// Fetches data from attendance_summary_by_location view.
final locationSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response =
      await _client.from('attendance_summary_by_location').select();
  return List<Map<String, dynamic>>.from(response);
});

/// Fetches data from attendance_summary_by_member view, optionally filtered.
final memberSummaryProvider = FutureProvider.family<List<Map<String, dynamic>>,
    String?>((ref, locationId) async {
  // The view exposes location_name itself, so no embedded join is needed.
  var query = _client.from('attendance_summary_by_member').select(
        'member_id, full_name, location_id, location_name, '
        'total_sessions, attended_sessions, attendance_percentage',
      );
  if (locationId != null && locationId.isNotEmpty) {
    query = query.eq('location_id', locationId);
  }
  final response = await query.order('full_name');
  return List<Map<String, dynamic>>.from(response);
});

/// Fetches all active members across all locations (for super admin summary).
final allActiveMembersProvider = FutureProvider<List<Member>>((ref) async {
  final response = await _client
      .from('members')
      .select()
      .eq('is_active', true)
      .order('full_name');
  return (response as List).map((e) => Member.fromJson(e)).toList();
});

/// Fetches active member count per location.
final memberCountByLocationProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final members = await ref.watch(allActiveMembersProvider.future);
  final counts = <String, int>{};
  for (final m in members) {
    counts[m.locationId] = (counts[m.locationId] ?? 0) + 1;
  }
  return counts;
});

/// Fetches a single member's full attendance history.
final memberAttendanceHistoryProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, memberId) async {
  final response = await _client
      .from('attendance')
      .select(
        '*, sessions:session_id('
        'session_date, location_id, event_id, events(title))',
      )
      .eq('member_id', memberId)
      .order('marked_at');
  return List<Map<String, dynamic>>.from(response);
});

/// Fetches member details by ID.
final memberDetailProvider =
    FutureProvider.family<Member?, String>((ref, memberId) async {
  final response = await _client
      .from('members')
      .select()
      .eq('id', memberId)
      .maybeSingle();
  if (response == null) return null;
  return Member.fromJson(response);
});
