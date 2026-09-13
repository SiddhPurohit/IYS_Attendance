import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/member.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motifs.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../sessions/providers/sessions_provider.dart';
import '../providers/attendance_provider.dart';

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  /// Explicit location to mark attendance for. When null, falls back to the
  /// current user's own location (the normal admin flow). Super admins pass
  /// this explicitly since they have no location of their own.
  final String? locationId;

  /// Date to open on. Defaults to today.
  final DateTime? initialDate;

  /// Marks one specific existing session. Required for event sessions, which
  /// can share a date with that location's regular programme and so cannot be
  /// identified by location + date alone. The date is fixed in this mode.
  final String? sessionId;

  const MarkAttendanceScreen({
    super.key,
    this.locationId,
    this.initialDate,
    this.sessionId,
  });

  @override
  ConsumerState<MarkAttendanceScreen> createState() =>
      _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> {
  late DateTime _selectedDate = widget.initialDate ?? DateTime.now();
  String _searchQuery = '';
  bool _saving = false;
  bool _initialized = false;

  /// memberId → present (true = present, false = absent)
  final Map<String, bool> _attendanceMap = {};

  String get _dateString =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  void _goBack(bool isSuperAdmin) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(isSuperAdmin ? '/dashboard' : '/admin');
    }
  }

  Widget _shell(Widget body, {String title = 'Mark Attendance'}) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: body),
      );

  @override
  Widget build(BuildContext context) {
    // Marking one specific session (an event, or editing a past session).
    if (widget.sessionId != null) {
      final sessionAsync = ref.watch(sessionDetailProvider(widget.sessionId!));
      final isSuperAdmin =
          ref.watch(currentProfileProvider).value?.isSuperAdmin ?? false;

      return sessionAsync.when(
        data: (session) {
          if (session == null) {
            return _shell(const Text('Session not found.'));
          }
          return _buildContent(
            context,
            session['location_id'] as String,
            session['session_date'] as String,
            isSuperAdmin: isSuperAdmin,
            knownSessionId: widget.sessionId,
            eventTitle: session['event_title'] as String?,
          );
        },
        loading: () => _shell(const CircularProgressIndicator()),
        error: (e, _) => _shell(Text('Could not load session.\n$e')),
      );
    }

    if (widget.locationId != null) {
      // Location explicitly given (super admin flow) — no profile lookup needed.
      return _buildContent(context, widget.locationId!, _dateString,
          isSuperAdmin: true);
    }

    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return _shell(const Text('Profile not found.'));
        }
        return _buildContent(
          context,
          profile.locationId ?? '',
          _dateString,
          isSuperAdmin: profile.isSuperAdmin,
        );
      },
      loading: () => _shell(const CircularProgressIndicator()),
      error: (_, __) => _shell(const Text('Error loading profile.')),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String locationId,
    String dateString, {
    required bool isSuperAdmin,
    String? knownSessionId,
    String? eventTitle,
  }) {
    final sessionParams = (locationId: locationId, date: dateString);
    final membersAsync = ref.watch(activeMembersProvider(sessionParams));
    // When the session is already known there is nothing to look up, and a
    // (location, date) lookup would find the regular session, not this one.
    final existingSessionAsync = knownSessionId != null
        ? AsyncValue<Session?>.data(null)
        : ref.watch(existingSessionProvider(sessionParams));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(isSuperAdmin),
        ),
        title: Text(eventTitle ?? 'Mark Attendance'),
        bottom: isSuperAdmin
            ? PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: _LocationSubtitle(locationId: locationId),
              )
            : null,
      ),
      body: Column(
        children: [
          // A known session has a fixed date; only the free-form flow lets
          // you move between days.
          if (knownSessionId != null)
            _FixedSessionBar(
              eventTitle: eventTitle,
              date: DateTime.tryParse(dateString) ?? DateTime.now(),
            )
          else
            _DatePickerBar(
              selectedDate: _selectedDate,
              onDateChanged: (date) {
                setState(() {
                  _selectedDate = date;
                  _initialized = false;
                  _attendanceMap.clear();
                });
              },
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search, size: 22),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
            ),
          ),

          // Members list
          Expanded(
            child: membersAsync.when(
              data: (members) {
                return existingSessionAsync.when(
                  data: (session) {
                    return _buildAttendanceList(
                      context,
                      members,
                      knownSessionId ?? session?.id,
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load session.\n$e',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load members.\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),

          // Save button
          _buildSaveButton(
            context,
            locationId,
            dateString,
            knownSessionId,
            membersAsync.value != null,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(
    BuildContext context,
    List<Member> members,
    String? sessionId,
  ) {
    // Load existing attendance if not initialized
    if (!_initialized) {
      if (sessionId == null) {
        // No session exists for this date yet — default everyone to present.
        for (final member in members) {
          _attendanceMap[member.id] = true;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initialized = true);
        });
        return _membersList(context, members);
      }

      final existingAsync = ref.watch(existingAttendanceProvider(sessionId));
      return existingAsync.when(
        data: (existing) {
          for (final member in members) {
            if (existing.containsKey(member.id)) {
              _attendanceMap[member.id] = existing[member.id]!;
            } else {
              _attendanceMap[member.id] = true; // Default: Present
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _initialized = true);
          });
          return _membersList(context, members);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          for (final member in members) {
            _attendanceMap[member.id] = true;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _initialized = true);
          });
          return _membersList(context, members);
        },
      );
    }

    return _membersList(context, members);
  }

  Widget _membersList(BuildContext context, List<Member> members) {
    final filtered = _searchQuery.isEmpty
        ? members
        : members
            .where((m) =>
                m.fullName.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LotusIcon(size: 56),
            const SizedBox(height: 12),
            Text(
              members.isEmpty
                  ? 'No devotees added yet'
                  : 'No matches for "$_searchQuery"',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    final presentCount =
        _attendanceMap.values.where((v) => v).length;

    return Column(
      children: [
        // Summary bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.presentGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$presentCount/${members.length} present',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.presentGreen,
                      ),
                ),
              ),
              const Spacer(),
              // Mark all / Unmark all
              TextButton(
                onPressed: () {
                  setState(() {
                    final allPresent =
                        _attendanceMap.values.every((v) => v);
                    for (final key in _attendanceMap.keys) {
                      _attendanceMap[key] = !allPresent;
                    }
                  });
                },
                child: Text(
                  _attendanceMap.values.every((v) => v)
                      ? 'Mark All Absent'
                      : 'Mark All Present',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.teal,
                      ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final member = filtered[index];
              final isPresent = _attendanceMap[member.id] ?? true;

              return _AttendanceRow(
                name: member.fullName,
                isPresent: isPresent,
                onToggle: () {
                  setState(() {
                    _attendanceMap[member.id] = !isPresent;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(
    BuildContext context,
    String locationId,
    String dateString,
    String? knownSessionId,
    bool membersLoaded,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: (_saving || !_initialized || !membersLoaded)
                ? null
                : () => _save(locationId, dateString, knownSessionId),
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 24),
            label: Text(
              _saving ? 'Saving...' : 'Save Attendance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.teal.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(
    String locationId,
    String dateString,
    String? knownSessionId,
  ) async {
    setState(() => _saving = true);

    try {
      if (knownSessionId != null) {
        await saveAttendanceForSession(
          sessionId: knownSessionId,
          attendanceMap: _attendanceMap,
        );
      } else {
        await saveAttendance(
          locationId: locationId,
          date: dateString,
          attendanceMap: _attendanceMap,
        );
      }

      if (!mounted) return;

      // Refresh every attendance-derived list so the sessions list, session
      // detail and dashboard reflect this save without an app restart.
      invalidateAttendanceCaches(ref);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Attendance saved! 🙏',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: AppColors.presentGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving attendance: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────

class _LocationSubtitle extends ConsumerWidget {
  final String locationId;

  const _LocationSubtitle({required this.locationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(locationNameProvider(locationId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        nameAsync.value ?? '...',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Header for a session that is already pinned down — an event, or a past
/// session opened for editing. Shows the date without letting it change.
class _FixedSessionBar extends StatelessWidget {
  final String? eventTitle;
  final DateTime date;

  const _FixedSessionBar({required this.eventTitle, required this.date});

  @override
  Widget build(BuildContext context) {
    final isEvent = eventTitle != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isEvent ? AppColors.saffronLight : Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEvent ? Icons.celebration_outlined : Icons.calendar_today,
            size: 20,
            color: AppColors.saffronDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isEvent)
                  Text(
                    eventTitle!,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                Text(
                  DateFormat('EEEE, d MMMM yyyy').format(date),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerBar extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  const _DatePickerBar({
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 20, color: AppColors.saffron),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(selectedDate),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (isToday)
                Text(
                  'Today',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.presentGreen,
                        fontWeight: FontWeight.w500,
                      ),
                ),
            ],
          ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: AppColors.saffron,
                          ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                onDateChanged(picked);
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final String name;
  final bool isPresent;
  final VoidCallback onToggle;

  const _AttendanceRow({
    required this.name,
    required this.isPresent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: isPresent
                    ? AppColors.presentGreen.withValues(alpha: 0.1)
                    : AppColors.absentRed.withValues(alpha: 0.1),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: isPresent
                        ? AppColors.presentGreen
                        : AppColors.absentRed,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: isPresent
                            ? null
                            : TextDecoration.lineThrough,
                        color: isPresent
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                ),
              ),

              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isPresent
                      ? AppColors.presentGreen.withValues(alpha: 0.12)
                      : AppColors.absentRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPresent
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 18,
                      color: isPresent
                          ? AppColors.presentGreen
                          : AppColors.absentRed,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPresent ? 'Present' : 'Absent',
                      style: TextStyle(
                        color: isPresent
                            ? AppColors.presentGreen
                            : AppColors.absentRed,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
