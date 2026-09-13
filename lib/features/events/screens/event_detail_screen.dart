import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../dashboard/widgets/location_bar_chart.dart';
import '../../dashboard/widgets/summary_card.dart';
import '../providers/events_provider.dart';

/// Super admin's bird's-eye view of one event: who turned up, from where.
class EventDetailScreen extends ConsumerWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard/events');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          'Delete "$title"?\n\nIts session at every location and all '
          'attendance marked for it will be permanently removed. This '
          'cannot be undone.',
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
      await deleteEvent(eventId);
      if (!context.mounted) return;

      ref.invalidate(eventsListProvider);
      invalidateAttendanceCaches(ref);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$title" deleted.'),
          backgroundColor: AppColors.presentGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _leave(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete event: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    final summaryAsync = ref.watch(eventSummaryProvider(eventId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leave(context),
        ),
        title: const Text('Event Overview'),
        actions: [
          eventAsync.when(
            data: (event) => event == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete Event',
                    onPressed: () => _confirmDelete(context, ref, event.title),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: eventAsync.when(
        data: (event) {
          if (event == null) {
            return const Center(child: Text('Event not found.'));
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: AppColors.saffronLight,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.celebration_outlined,
                                  color: AppColors.saffronDark, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  event.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEEE, d MMMM yyyy')
                                .format(event.eventDate),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          if (event.notes != null &&
                              event.notes!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(event.notes!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  summaryAsync.when(
                    data: (rows) => _buildBreakdown(context, rows),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Text('Error loading attendance: $e'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading event: $e')),
      ),
    );
  }

  Widget _buildBreakdown(
    BuildContext context,
    List<Map<String, dynamic>> rows,
  ) {
    final totalPresent = rows.fold<int>(
        0, (sum, r) => sum + ((r['present_count'] as num?)?.toInt() ?? 0));
    final totalMarked = rows.fold<int>(
        0, (sum, r) => sum + ((r['total_marked'] as num?)?.toInt() ?? 0));
    final locationsMarked =
        rows.where((r) => ((r['total_marked'] as num?)?.toInt() ?? 0) > 0)
            .length;

    final barData = rows.map((r) {
      final present = (r['present_count'] as num?)?.toInt() ?? 0;
      final marked = (r['total_marked'] as num?)?.toInt() ?? 0;
      return {
        'locationName': r['location_name'] as String? ?? '',
        'percentage': marked == 0 ? 0.0 : (present / marked) * 100,
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                title: 'Total Attended',
                value: '$totalPresent',
                icon: Icons.groups_outlined,
                accentColor: AppColors.presentGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                title: 'Locations Marked',
                value: '$locationsMarked/${rows.length}',
                icon: Icons.location_on_outlined,
                accentColor: AppColors.saffron,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (totalMarked > 0) ...[
          LocationBarChart(data: barData),
          const SizedBox(height: 24),
        ],
        Text(
          'Who Attended',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...rows.map((row) => _LocationAttendees(row: row)),
      ],
    );
  }
}

/// One location's attendance for the event, names and all. Opens expanded
/// when there is something to show.
class _LocationAttendees extends StatelessWidget {
  final Map<String, dynamic> row;

  const _LocationAttendees({required this.row});

  @override
  Widget build(BuildContext context) {
    final present = List<String>.from(row['present_names'] as List? ?? []);
    final absent = List<String>.from(row['absent_names'] as List? ?? []);
    final marked = present.length + absent.length;
    final notMarked = marked == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: !notMarked,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: CircleAvatar(
          backgroundColor:
              (notMarked ? AppColors.onSurfaceVariant : AppColors.presentGreen)
                  .withValues(alpha: 0.12),
          child: Icon(
            notMarked ? Icons.hourglass_empty : Icons.check_circle,
            color: notMarked
                ? AppColors.onSurfaceVariant
                : AppColors.presentGreen,
            size: 20,
          ),
        ),
        title: Text(
          row['location_name'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          notMarked
              ? 'Not marked yet'
              : '${present.length} of $marked attended',
          style: const TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        trailing: notMarked
            ? null
            : Text(
                '${((present.length / marked) * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.presentGreen,
                  fontSize: 15,
                ),
              ),
        children: notMarked
            ? const []
            : [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (present.isNotEmpty) ...[
                        _NameGroup(
                          label: 'Attended (${present.length})',
                          names: present,
                          color: AppColors.presentGreen,
                          icon: Icons.check,
                        ),
                      ],
                      if (absent.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _NameGroup(
                          label: 'Absent (${absent.length})',
                          names: absent,
                          color: AppColors.absentRed,
                          icon: Icons.close,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
      ),
    );
  }
}

class _NameGroup extends StatelessWidget {
  final String label;
  final List<String> names;
  final Color color;
  final IconData icon;

  const _NameGroup({
    required this.label,
    required this.names,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: names
              .map(
                (name) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 5),
                      Text(
                        name,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
