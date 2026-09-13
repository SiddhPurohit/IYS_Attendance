import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../providers/sessions_provider.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> session,
  ) async {
    final date = DateTime.tryParse(session['session_date'] as String);
    final label = date != null
        ? DateFormat('d MMM yyyy').format(date)
        : session['session_date'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text(
          'Delete the $label session at ${session['location_name']}?\n\n'
          'Every attendance record for this session will be permanently '
          'removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await deleteSession(sessionId);
      if (!context.mounted) return;

      invalidateAttendanceCaches(ref);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session of $label deleted.'),
          backgroundColor: AppColors.presentGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/dashboard/sessions');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete session: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionDetailProvider(sessionId));
    final attendanceAsync = ref.watch(sessionAttendanceListProvider(sessionId));
    final profileAsync = ref.watch(currentProfileProvider);
    final isSuperAdmin = profileAsync.value?.isSuperAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(isSuperAdmin ? '/dashboard/sessions' : '/admin/sessions');
            }
          },
        ),
        title: const Text('Session Details'),
        actions: [
          sessionAsync.when(
            data: (session) {
              if (session == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Attendance',
                onPressed: () {
                  final base = isSuperAdmin ? '/dashboard' : '/admin';
                  // By session id, not location + date — an event can share
                  // a date with that location's regular programme.
                  context.push('$base/attendance/session/$sessionId');
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          if (isSuperAdmin)
            sessionAsync.when(
              data: (session) {
                if (session == null) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete Session',
                  onPressed: () => _confirmDelete(context, ref, session),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
        ],
      ),
      body: sessionAsync.when(
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found.'));
          }

          final date = DateTime.tryParse(session['session_date'] as String) ??
              DateTime.now();
          final locationName = session['location_name'] as String;
          final notes = session['notes'] as String?;
          final eventTitle = session['event_title'] as String?;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: eventTitle != null ? AppColors.saffronLight : null,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eventTitle != null) ...[
                            Row(
                              children: [
                                const Icon(Icons.celebration_outlined,
                                    size: 22, color: AppColors.saffronDark),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    eventTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            DateFormat('EEEE, d MMMM yyyy').format(date),
                            style: eventTitle != null
                                ? Theme.of(context).textTheme.bodyLarge
                                : Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 18, color: AppColors.saffron),
                              const SizedBox(width: 6),
                              Text(
                                locationName,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                          if (notes != null && notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.notes_outlined,
                                    size: 18,
                                    color: AppColors.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(child: Text(notes)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  attendanceAsync.when(
                    data: (rows) {
                      final present =
                          rows.where((r) => r['present'] == true).length;
                      final total = rows.length;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Attendance',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.presentGreen
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$present/$total present',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: AppColors.presentGreen),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('No attendance recorded.'),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final isPresent = row['present'] == true;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  elevation: 0.5,
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 2,
                                    ),
                                    leading: Icon(
                                      isPresent
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: isPresent
                                          ? AppColors.presentGreen
                                          : AppColors.absentRed,
                                    ),
                                    title: Text(row['full_name'] as String),
                                    trailing: Text(
                                      isPresent ? 'Present' : 'Absent',
                                      style: TextStyle(
                                        color: isPresent
                                            ? AppColors.presentGreen
                                            : AppColors.absentRed,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Text('Error loading attendance: $e'),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading session: $e')),
      ),
    );
  }
}
