import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/location.dart';
import '../../../core/models/member.dart';
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

  /// Locations currently being marked. Null until seeded from the admin's
  /// accessible locations on first build; never empty afterwards.
  Set<String>? _selectedLocationIds;

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

  /// The roster this screen is showing changed — different date, or a
  /// different set of locations — so anything already toggled no longer
  /// applies and has to be re-seeded from the database.
  void _resetRoster() {
    _initialized = false;
    _attendanceMap.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Marking one specific session (an event, or editing a past session).
    // The session pins both the location and the date, so nothing is
    // selectable in this mode.
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
            locationIds: [session['location_id'] as String],
            dateString: session['session_date'] as String,
            isSuperAdmin: isSuperAdmin,
            knownSessionId: widget.sessionId,
            eventTitle: session['event_title'] as String?,
          );
        },
        loading: () => _shell(const CircularProgressIndicator()),
        error: (e, _) => _shell(Text('Could not load session.\n$e')),
      );
    }

    final accessibleAsync = ref.watch(accessibleLocationsProvider);
    final isSuperAdmin =
        ref.watch(currentProfileProvider).value?.isSuperAdmin ?? false;

    return accessibleAsync.when(
      data: (locations) {
        if (locations.isEmpty) {
          return _shell(
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No locations are assigned to your account.\n'
                'Ask a super admin to give you access.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // Seeded once: the location the caller asked for (the super admin's
        // picker dialog), otherwise everything this admin can reach.
        final selected = _selectedLocationIds ??= {
          if (widget.locationId != null &&
              locations.any((l) => l.id == widget.locationId))
            widget.locationId!
          else
            ...locations.map((l) => l.id),
        };

        return _buildContent(
          context,
          locationIds: selected.toList(),
          dateString: _dateString,
          isSuperAdmin: isSuperAdmin,
          pickerOptions: locations,
        );
      },
      loading: () => _shell(const CircularProgressIndicator()),
      error: (e, _) => _shell(Text('Could not load your locations.\n$e')),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required List<String> locationIds,
    required String dateString,
    required bool isSuperAdmin,
    List<Location> pickerOptions = const [],
    String? knownSessionId,
    String? eventTitle,
  }) {
    final key = locationKey(locationIds);
    final membersAsync =
        ref.watch(activeMembersProvider((locationIds: key, date: dateString)));

    // A known session is read directly; otherwise merge whatever has already
    // been marked across the selected locations on this date.
    final existingAsync = knownSessionId != null
        ? ref.watch(existingAttendanceProvider(knownSessionId))
        : ref.watch(existingAttendanceForDateProvider(
            (locationIds: key, date: dateString),
          ));

    final showPicker = knownSessionId == null && pickerOptions.length > 1;
    final locationNames = {for (final l in pickerOptions) l.id: l.name};
    // In the fixed-session flow there is no picker to make the location
    // obvious, so anyone who holds several locations needs it spelled out —
    // otherwise an event marked at two locations looks identical either way.
    final holdsSeveralLocations =
        (ref.watch(accessibleLocationsProvider).value?.length ?? 0) > 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(isSuperAdmin),
        ),
        title: Text(eventTitle ?? 'Mark Attendance'),
        // With a picker on screen the location is already obvious; this
        // subtitle only earns its place when the location is fixed.
        bottom: (knownSessionId != null && holdsSeveralLocations)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: _LocationSubtitle(locationId: locationIds.first),
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
                  _resetRoster();
                });
              },
            ),

          if (showPicker)
            _LocationPickerBar(
              locations: pickerOptions,
              selected: _selectedLocationIds ?? const {},
              onToggle: (id) {
                setState(() {
                  final set = _selectedLocationIds ??= {};
                  if (set.contains(id)) {
                    // Never allow an empty selection — there would be
                    // nothing left to mark.
                    if (set.length > 1) set.remove(id);
                  } else {
                    set.add(id);
                  }
                  _resetRoster();
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
              data: (members) => existingAsync.when(
                data: (existing) => _buildAttendanceList(
                  context,
                  members,
                  existing,
                  showLocationBadges: locationIds.length > 1,
                  locationNames: locationNames,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load existing attendance.\n$e',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load devotees.\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),

          // Save button
          _buildSaveButton(
            context,
            members: membersAsync.value ?? const [],
            dateString: dateString,
            knownSessionId: knownSessionId,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(
    BuildContext context,
    List<Member> members,
    Map<String, bool> existing, {
    required bool showLocationBadges,
    required Map<String, String> locationNames,
  }) {
    // Seed once per roster: whatever was marked before, everyone else
    // present by default. Guarded on _initialized so re-builds never clobber
    // toggles the admin has already made.
    if (!_initialized) {
      for (final member in members) {
        _attendanceMap[member.id] = existing[member.id] ?? true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _initialized = true);
      });
    }

    return _membersList(
      context,
      members,
      showLocationBadges: showLocationBadges,
      locationNames: locationNames,
    );
  }

  Widget _membersList(
    BuildContext context,
    List<Member> members, {
    required bool showLocationBadges,
    required Map<String, String> locationNames,
  }) {
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
                // Only when several locations are mixed into one list does
                // the devotee's own location need spelling out.
                locationName: showLocationBadges
                    ? locationNames[member.locationId]
                    : null,
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
    BuildContext context, {
    required List<Member> members,
    required String dateString,
    required String? knownSessionId,
  }) {
    final membersLoaded = members.isNotEmpty;
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
                : () => _save(members, dateString, knownSessionId),
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
    List<Member> members,
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
        // Fans out to one session per location represented in the roster.
        await saveAttendanceAcrossLocations(
          date: dateString,
          members: members,
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

/// Location chips for an admin who holds more than one location. Selecting
/// several merges their devotees into a single list to mark in one pass;
/// on save each devotee still lands on their own location's session.
class _LocationPickerBar extends StatelessWidget {
  final List<Location> locations;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _LocationPickerBar({
    required this.locations,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MARKING FOR',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: locations.map((loc) {
              final isSelected = selected.contains(loc.id);
              return FilterChip(
                selected: isSelected,
                label: Text(loc.name),
                onSelected: (_) => onToggle(loc.id),
                selectedColor: AppColors.saffron.withValues(alpha: 0.2),
                checkmarkColor: AppColors.saffronDark,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
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

  /// Set only when the list mixes several locations, so it's clear which
  /// devotee belongs where.
  final String? locationName;

  const _AttendanceRow({
    required this.name,
    required this.isPresent,
    required this.onToggle,
    this.locationName,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
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
                    if (locationName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        locationName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.saffronDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                      ),
                    ],
                  ],
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
