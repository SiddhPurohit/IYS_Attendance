import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/member.dart';

final _client = Supabase.instance.client;

/// Fetches active members, optionally filtered to one location.
/// Pass null (or empty) [locationId] to fetch active members across all
/// locations (used by super admin's "All Locations" view).
final membersListProvider =
    FutureProvider.family<List<Member>, String?>((ref, locationId) async {
  var query = _client.from('members').select().eq('is_active', true);
  if (locationId != null && locationId.isNotEmpty) {
    query = query.eq('location_id', locationId);
  }
  final response = await query.order('full_name');

  return (response as List).map((e) => Member.fromJson(e)).toList();
});

/// Fetches a single member by ID.
final memberByIdProvider =
    FutureProvider.family<Member?, String>((ref, memberId) async {
  final response = await _client
      .from('members')
      .select()
      .eq('id', memberId)
      .maybeSingle();

  if (response == null) return null;
  return Member.fromJson(response);
});

/// Adds a new member.
Future<void> addMember({
  required String fullName,
  DateTime? dob,
  String? phone,
  String? email,
  required String locationId,
  required DateTime joinedOn,
}) async {
  final userId = _client.auth.currentUser!.id;
  await _client.from('members').insert({
    'full_name': fullName,
    if (dob != null) 'dob': dob.toIso8601String().split('T').first,
    if (phone != null && phone.isNotEmpty) 'phone': phone,
    if (email != null && email.isNotEmpty) 'email': email,
    'location_id': locationId,
    'is_active': true,
    'created_by': userId,
    'joined_on': joinedOn.toIso8601String().split('T').first,
  });
}

/// Updates an existing member.
Future<void> updateMember({
  required String memberId,
  required String fullName,
  DateTime? dob,
  String? phone,
  String? email,
  required DateTime joinedOn,
}) async {
  await _client.from('members').update({
    'full_name': fullName,
    'dob': dob?.toIso8601String().split('T').first,
    'phone': phone,
    'email': email,
    'joined_on': joinedOn.toIso8601String().split('T').first,
  }).eq('id', memberId);
}

/// Soft-deletes a member (sets is_active = false).
Future<void> softDeleteMember(String memberId) async {
  await _client
      .from('members')
      .update({'is_active': false}).eq('id', memberId);
}
