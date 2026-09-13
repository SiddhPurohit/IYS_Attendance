import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/attendance_line_chart.dart';
import '../widgets/summary_card.dart';

class MemberDetailScreen extends ConsumerWidget {
  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberDetailProvider(memberId));
    final historyAsync = ref.watch(memberAttendanceHistoryProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devotee Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            // push, not go — so closing the editor returns here rather than
            // rebuilding the stack under the Manage Boys list.
            onPressed: () => context.push('/dashboard/members/edit/$memberId'),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: memberAsync.when(
              data: (member) {
                if (member == null) {
                  return const Center(child: Text('Devotee not found.'));
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  children: [
                    // Member Profile Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      AppColors.saffron.withValues(alpha: 0.15),
                                  child: Text(
                                    member.fullName.isNotEmpty
                                        ? member.fullName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: AppColors.saffronDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.fullName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: member.isActive
                                              ? AppColors.presentGreen
                                                  .withValues(alpha: 0.12)
                                              : Colors.grey
                                                  .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          member.isActive
                                              ? 'Active'
                                              : 'Inactive',
                                          style: TextStyle(
                                            color: member.isActive
                                                ? AppColors.presentGreen
                                                : Colors.grey,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 28),
                            if (member.phone != null &&
                                member.phone!.isNotEmpty) ...[
                              _buildInfoRow(
                                Icons.phone_outlined,
                                'Phone',
                                member.phone!,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (member.email != null &&
                                member.email!.isNotEmpty) ...[
                              _buildInfoRow(
                                Icons.email_outlined,
                                'Email',
                                member.email!,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (member.dob != null) ...[
                              _buildInfoRow(
                                Icons.cake_outlined,
                                'Birthday',
                                DateFormat.yMMMMd().format(member.dob!),
                              ),
                              const SizedBox(height: 10),
                            ],
                            _buildInfoRow(
                              Icons.event_available_outlined,
                              'Joined',
                              DateFormat.yMMMd().format(member.joinedOn),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // History and Attendance Stats
                    historyAsync.when(
                      data: (fullHistory) {
                        // Special events are reported separately, so they
                        // don't distort the regular programme percentage —
                        // matching how the dashboard counts them.
                        final history = fullHistory
                            .where((h) =>
                                (h['sessions'] as Map?)?['event_id'] == null)
                            .toList();
                        final eventHistory = fullHistory
                            .where((h) =>
                                (h['sessions'] as Map?)?['event_id'] != null)
                            .toList();

                        final total = history.length;
                        final attended = history
                            .where((h) => h['present'] == true)
                            .length;
                        final pct = total > 0 ? (attended / total) * 100 : 0.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Summary Cards
                            Row(
                              children: [
                                Expanded(
                                  child: SummaryCard(
                                    title: 'Attended',
                                    value: '$attended / $total',
                                    icon: Icons.check_circle_outline,
                                    accentColor: AppColors.presentGreen,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SummaryCard(
                                    title: 'Percentage',
                                    value: '${pct.toStringAsFixed(0)}%',
                                    icon: Icons.percent,
                                    accentColor: pct >= 75
                                        ? AppColors.presentGreen
                                        : pct >= 50
                                            ? AppColors.saffron
                                            : AppColors.absentRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Special events — counted separately
                            _buildEventsSection(context, eventHistory),

                            // Trend Line Chart
                            if (history.isNotEmpty) ...[
                              _buildMemberTrendChart(history),
                              const SizedBox(height: 24),
                            ],

                            // Session History List
                            Text(
                              'Attendance History',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12),

                            if (history.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text('No attendance records yet.'),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: history.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  // Reverse chronological
                                  final record =
                                      history[history.length - 1 - idx];
                                  final isPresent =
                                      record['present'] == true;
                                  final sessionInfo =
                                      record['sessions'] as Map<String, dynamic>?;
                                  final dateStr =
                                      sessionInfo?['session_date'] as String? ??
                                          record['marked_at'] as String?;
                                  final date = dateStr != null
                                      ? DateTime.tryParse(dateStr) ??
                                          DateTime.now()
                                      : DateTime.now();

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
                                        size: 24,
                                      ),
                                      title: Text(
                                        DateFormat.yMMMEd().format(date),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (isPresent
                                                  ? AppColors.presentGreen
                                                  : AppColors.absentRed)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
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
                      error: (e, _) => Text('Error loading history: $e'),
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Center(
                child: Text('Error loading details: $e'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  /// Special events this devotee was marked for — how many they turned up
  /// to, and which ones.
  Widget _buildEventsSection(
    BuildContext context,
    List<Map<String, dynamic>> eventHistory,
  ) {
    if (eventHistory.isEmpty) return const SizedBox.shrink();

    final attended =
        eventHistory.where((h) => h['present'] == true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Special Events',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.saffronDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${attended.length} of ${eventHistory.length} attended',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...eventHistory.reversed.map((record) {
          final isPresent = record['present'] == true;
          final session = record['sessions'] as Map<String, dynamic>?;
          final event = session?['events'] as Map<String, dynamic>?;
          final title = event?['title'] as String? ?? 'Event';
          final dateStr = session?['session_date'] as String?;
          final date =
              dateStr != null ? DateTime.tryParse(dateStr) : null;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: AppColors.saffronLight,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Icon(
                isPresent ? Icons.celebration : Icons.cancel_outlined,
                color: isPresent
                    ? AppColors.saffronDark
                    : AppColors.absentRed,
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: date != null
                  ? Text(DateFormat.yMMMEd().format(date))
                  : null,
              trailing: Text(
                isPresent ? 'Attended' : 'Missed',
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
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMemberTrendChart(List<Map<String, dynamic>> history) {
    // Build running attendance percentage
    final chartData = <Map<String, dynamic>>[];
    int runningAttended = 0;

    for (var i = 0; i < history.length; i++) {
      final record = history[i];
      if (record['present'] == true) runningAttended++;
      final totalSoFar = i + 1;
      final pct = (runningAttended / totalSoFar) * 100;

      final sessionInfo = record['sessions'] as Map<String, dynamic>?;
      final dateStr = sessionInfo?['session_date'] as String? ??
          record['marked_at'] as String?;
      final date = dateStr != null
          ? DateTime.tryParse(dateStr) ?? DateTime.now()
          : DateTime.now();

      chartData.add({
        'date': date,
        'percentage': pct,
      });
    }

    return AttendanceLineChart(
      data: chartData,
      title: 'Cumulative Attendance %',
    );
  }
}
