import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_home_screen.dart';
import '../../features/attendance/screens/mark_attendance_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashboard/screens/member_detail_screen.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/events/screens/events_list_screen.dart';
import '../../features/members/screens/add_edit_member_screen.dart';
import '../../features/members/screens/manage_members_screen.dart';
import '../../features/sessions/screens/session_detail_screen.dart';
import '../../features/sessions/screens/sessions_list_screen.dart';
import '../providers/auth_provider.dart';
import '../supabase/supabase_client.dart';

final authChangeNotifier = AuthChangeNotifier();

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: authChangeNotifier,
  redirect: (context, state) async {
    final session = supabase.auth.currentSession;
    final isLoggedIn = session != null;
    final isOnLogin = state.matchedLocation == '/login';

    // Not logged in → go to login
    if (!isLoggedIn) {
      return isOnLogin ? null : '/login';
    }

    // Logged in but on login page → redirect based on role
    if (isOnLogin) {
      final profile = await _fetchProfile();
      if (profile == null) return '/login';
      if (profile['role'] == 'super_admin') return '/dashboard';
      return '/admin';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminHomeScreen(),
      routes: [
        GoRoute(
          path: 'attendance',
          builder: (context, state) => const MarkAttendanceScreen(),
        ),
        GoRoute(
          path: 'attendance/edit/:locationId/:date',
          builder: (context, state) {
            final locationId = state.pathParameters['locationId']!;
            final date = DateTime.tryParse(state.pathParameters['date']!);
            return MarkAttendanceScreen(locationId: locationId, initialDate: date);
          },
        ),
        GoRoute(
          path: 'members',
          builder: (context, state) => const ManageMembersScreen(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) =>
                  AddEditMemberScreen(initialLocationId: state.extra as String?),
            ),
            GoRoute(
              path: 'edit/:id',
              builder: (context, state) {
                final memberId = state.pathParameters['id']!;
                return AddEditMemberScreen(memberId: memberId);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'attendance/session/:sessionId',
          builder: (context, state) => MarkAttendanceScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
        GoRoute(
          path: 'sessions',
          builder: (context, state) => const SessionsListScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final sessionId = state.pathParameters['id']!;
                return SessionDetailScreen(sessionId: sessionId);
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
      routes: [
        GoRoute(
          path: 'attendance',
          builder: (context, state) => const MarkAttendanceScreen(),
        ),
        GoRoute(
          path: 'attendance/edit/:locationId/:date',
          builder: (context, state) {
            final locationId = state.pathParameters['locationId']!;
            final date = DateTime.tryParse(state.pathParameters['date']!);
            return MarkAttendanceScreen(locationId: locationId, initialDate: date);
          },
        ),
        GoRoute(
          path: 'members',
          builder: (context, state) => const ManageMembersScreen(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) =>
                  AddEditMemberScreen(initialLocationId: state.extra as String?),
            ),
            GoRoute(
              path: 'edit/:id',
              builder: (context, state) {
                final memberId = state.pathParameters['id']!;
                return AddEditMemberScreen(memberId: memberId);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'member/:id',
          builder: (context, state) {
            final memberId = state.pathParameters['id']!;
            return MemberDetailScreen(memberId: memberId);
          },
        ),
        GoRoute(
          path: 'events',
          builder: (context, state) => const EventsListScreen(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const CreateEventScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  EventDetailScreen(eventId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: 'attendance/session/:sessionId',
          builder: (context, state) => MarkAttendanceScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
        GoRoute(
          path: 'sessions',
          builder: (context, state) => const SessionsListScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final sessionId = state.pathParameters['id']!;
                return SessionDetailScreen(sessionId: sessionId);
              },
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Page not found: ${state.uri}'),
    ),
  ),
);

/// Helper to fetch profile during redirect (before providers are available).
Future<Map<String, dynamic>?> _fetchProfile() async {
  final user = supabase.auth.currentUser;
  if (user == null) return null;
  return await supabase
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();
}
