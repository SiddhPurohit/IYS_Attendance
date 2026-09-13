import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/location.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motifs.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/attendance_line_chart.dart';
import '../widgets/location_bar_chart.dart';
import '../widgets/summary_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _selectedLocationId; // null = all locations
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final locationSummariesAsync = ref.watch(locationSummaryProvider);
    final memberSummariesAsync =
        ref.watch(memberSummaryProvider(_selectedLocationId));
    final memberCountsAsync = ref.watch(memberCountByLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Add Devotee',
            onPressed: () => context.push('/dashboard/members/add'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                ref.invalidate(locationSummaryProvider);
                ref.invalidate(allLocationsProvider);
                ref.invalidate(memberSummaryProvider(null));
                ref.invalidate(allActiveMembersProvider);
                ref.invalidate(memberCountByLocationProvider);
                await signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // Header greeting
                SacredHeader(
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(child: LotusIcon.light(size: 32)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hare Krishna',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Overview & Attendance Analytics',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.9),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Quick actions
                _buildQuickActions(context),
                const SizedBox(height: 24),

                // Location selector chips
                locationsAsync.when(
                  data: (locations) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          selected: _selectedLocationId == null,
                          label: const Text('All Locations'),
                          selectedColor: AppColors.saffron.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.saffronDark,
                          onSelected: (_) {
                            setState(() => _selectedLocationId = null);
                          },
                        ),
                        const SizedBox(width: 8),
                        ...locations.map((loc) {
                          final isSelected = _selectedLocationId == loc.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: isSelected,
                              label: Text(loc.name),
                              selectedColor:
                                  AppColors.saffron.withValues(alpha: 0.2),
                              checkmarkColor: AppColors.saffronDark,
                              onSelected: (_) {
                                setState(() => _selectedLocationId = loc.id);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 40,
                    child: Center(child: LinearProgressIndicator()),
                  ),
                  error: (e, _) => Text('Error loading locations: $e'),
                ),
                const SizedBox(height: 20),

                // Summary cards row
                _buildSummaryCards(
                  locationSummariesAsync,
                  memberSummariesAsync,
                  memberCountsAsync,
                ),
                const SizedBox(height: 24),

                // Location comparison bar chart (shown when "All Locations" is selected)
                if (_selectedLocationId == null) ...[
                  _buildLocationComparisonChart(
                    locationsAsync,
                    locationSummariesAsync,
                  ),
                  const SizedBox(height: 24),
                ],

                // Line chart of weekly attendance
                _buildLineChart(locationSummariesAsync),
                const SizedBox(height: 28),

                // Members drill-down section header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Devotee Attendance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    memberSummariesAsync.when(
                      data: (members) => Text(
                        '${members.length} devotees',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search field
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search devotee by name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Member list
                memberSummariesAsync.when(
                  data: (members) {
                    final filtered = members.where((m) {
                      if (_searchQuery.isEmpty) return true;
                      final name = (m['full_name'] as String? ?? '').toLowerCase();
                      return name.contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'No devotees found.'
                                : 'No devotees matching "$_searchQuery"',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final member = filtered[idx];
                        final memberId = member['member_id'] as String? ??
                            member['id'] as String? ??
                            '';
                        final name =
                            member['full_name'] as String? ?? 'Unnamed';
                        final locationName =
                            member['location_name'] as String? ?? '';
                        final totalSessions =
                            member['total_sessions'] as int? ?? 0;
                        final attendedSessions =
                            member['attended_sessions'] as int? ?? 0;
                        final percentage = (member['attendance_percentage']
                                    as num?)
                                ?.toDouble() ??
                            (totalSessions > 0
                                ? (attendedSessions / totalSessions) * 100
                                : 0.0);

                        final badgeColor = percentage >= 75
                            ? AppColors.presentGreen
                            : percentage >= 50
                                ? AppColors.saffron
                                : AppColors.absentRed;

                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 1,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              _selectedLocationId == null &&
                                      locationName.isNotEmpty
                                  ? '$locationName • $attendedSessions/$totalSessions sessions'
                                  : '$attendedSessions/$totalSessions sessions',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: badgeColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    '${percentage.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                              ],
                            ),
                            onTap: () {
                              if (memberId.isNotEmpty) {
                                context.go('/dashboard/member/$memberId');
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error: $e'),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final buttons = [
      _QuickActionButton(
        label: 'Mark Attendance',
        icon: Icons.check_circle_outline,
        color: AppColors.saffron,
        onTap: () => _pickLocationAndMarkAttendance(context),
      ),
      _QuickActionButton(
        label: 'Manage Devotees',
        icon: Icons.people_outline,
        color: AppColors.teal,
        onTap: () => context.go('/dashboard/members'),
      ),
      _QuickActionButton(
        label: 'Sessions',
        icon: Icons.event_note_outlined,
        color: AppColors.tealDark,
        onTap: () => context.go('/dashboard/sessions'),
      ),
      _QuickActionButton(
        label: 'Events',
        icon: Icons.celebration_outlined,
        color: AppColors.saffronDark,
        onTap: () => context.go('/dashboard/events'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Four across only when there is room; otherwise 2x2 so the labels
        // stay readable on a phone.
        final perRow = constraints.maxWidth > 560 ? 4 : 2;

        return Column(
          children: [
            for (var i = 0; i < buttons.length; i += perRow)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (var j = i; j < i + perRow && j < buttons.length; j++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: buttons[j],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickLocationAndMarkAttendance(BuildContext context) async {
    final locations = await ref.read(allLocationsProvider.future);
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Location>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Mark Attendance For',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...locations.map(
                (loc) => ListTile(
                  leading: const Icon(Icons.location_on_outlined,
                      color: AppColors.saffron),
                  title: Text(loc.name),
                  onTap: () => Navigator.pop(context, loc),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/dashboard/attendance/edit/${selected.id}/$today');
  }

  Widget _buildSummaryCards(
    AsyncValue<List<Map<String, dynamic>>> locationSummariesAsync,
    AsyncValue<List<Map<String, dynamic>>> memberSummariesAsync,
    AsyncValue<Map<String, int>> memberCountsAsync,
  ) {
    return memberSummariesAsync.when(
      data: (members) {
        final totalMembers = members.length;
        double avgPct = 0;
        if (members.isNotEmpty) {
          final sum = members.fold<double>(0.0, (prev, m) {
            final pct = (m['attendance_percentage'] as num?)?.toDouble() ?? 0.0;
            return prev + pct;
          });
          avgPct = sum / members.length;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            final children = [
              SummaryCard(
                title: 'Active Devotees',
                value: '$totalMembers',
                icon: Icons.people_alt_outlined,
                accentColor: AppColors.saffron,
              ),
              SummaryCard(
                title: 'Avg Attendance',
                value: '${avgPct.toStringAsFixed(0)}%',
                icon: Icons.trending_up,
                accentColor: avgPct >= 75
                    ? AppColors.presentGreen
                    : avgPct >= 50
                        ? AppColors.saffron
                        : AppColors.absentRed,
              ),
            ];

            if (isWide) {
              return Row(
                children: children
                    .map((w) => Expanded(child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: w,
                        )))
                    .toList(),
              );
            } else {
              return Column(
                children: children
                    .map((w) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: w,
                        ))
                    .toList(),
              );
            }
          },
        );
      },
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLineChart(
    AsyncValue<List<Map<String, dynamic>>> locationSummariesAsync,
  ) {
    return locationSummariesAsync.when(
      data: (summaries) {
        // The view returns one row per location per date. Keep only the
        // selected location, then collapse each date into a single point so
        // the line has exactly one value per session day — otherwise every
        // location contributes its own point to the same date and the line
        // zig-zags between them.
        final rows = _selectedLocationId == null
            ? summaries
            : summaries.where((s) => s['location_id'] == _selectedLocationId);

        final byDate = <String, ({int present, int total})>{};
        for (final s in rows) {
          final dateStr = s['session_date'] as String?;
          if (dateStr == null) continue;
          final current = byDate[dateStr] ?? (present: 0, total: 0);
          byDate[dateStr] = (
            present:
                current.present + ((s['present_count'] as num?)?.toInt() ?? 0),
            total: current.total + ((s['total_members'] as num?)?.toInt() ?? 0),
          );
        }

        final lineData = byDate.entries.map((entry) {
          final counts = entry.value;
          return {
            'date': DateTime.tryParse(entry.key) ?? DateTime.now(),
            'percentage': counts.total == 0
                ? 0.0
                : (counts.present / counts.total) * 100,
          };
        }).toList();

        return AttendanceLineChart(
          data: lineData,
          title: _selectedLocationId == null
              ? 'Overall Attendance Trend'
              : 'Attendance Trend',
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLocationComparisonChart(
    AsyncValue<List<dynamic>> locationsAsync,
    AsyncValue<List<Map<String, dynamic>>> locationSummariesAsync,
  ) {
    return locationsAsync.when(
      data: (locations) => locationSummariesAsync.when(
        data: (summaries) {
          // Weighted across all sessions (total present / total expected),
          // matching how the trend line is computed.
          final totalsByLocation = <String, ({String name, int present, int total})>{};

          for (final loc in locations) {
            totalsByLocation[loc.id as String] = (
              name: loc.name as String,
              present: 0,
              total: 0,
            );
          }

          for (final s in summaries) {
            final locationId = s['location_id'] as String?;
            if (locationId == null || !totalsByLocation.containsKey(locationId)) {
              continue;
            }
            final current = totalsByLocation[locationId]!;
            totalsByLocation[locationId] = (
              name: current.name,
              present: current.present +
                  ((s['present_count'] as num?)?.toInt() ?? 0),
              total:
                  current.total + ((s['total_members'] as num?)?.toInt() ?? 0),
            );
          }

          final barData = locations.map((loc) {
            final stats = totalsByLocation[loc.id]!;
            final pct = stats.total == 0
                ? 0.0
                : (stats.present / stats.total) * 100;
            return {
              'locationName': stats.name,
              'percentage': pct,
            };
          }).toList();

          return LocationBarChart(data: barData);
        },
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => const SizedBox.shrink(),
      ),
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
