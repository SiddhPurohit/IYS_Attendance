import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/location.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motifs.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/sessions_provider.dart';

class SessionsListScreen extends ConsumerStatefulWidget {
  const SessionsListScreen({super.key});

  @override
  ConsumerState<SessionsListScreen> createState() =>
      _SessionsListScreenState();
}

class _SessionsListScreenState extends ConsumerState<SessionsListScreen> {
  String? _selectedLocationId;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sessions')),
            body: const Center(child: Text('Profile not found.')),
          );
        }
        // A null filter means "everything I'm allowed to see". RLS already
        // narrows that to this admin's locations, so no client-side location
        // guard is needed — a super admin gets all of them, an admin gets
        // whichever they've been granted.
        return _buildScaffold(
          context,
          profile.isSuperAdmin,
          _selectedLocationId,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Sessions')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Sessions')),
        body: const Center(child: Text('Error loading profile.')),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    bool isSuperAdmin,
    String? filterLocationId,
  ) {
    final sessionsAsync = ref.watch(sessionsListProvider(filterLocationId));
    final accessible = ref.watch(accessibleLocationsProvider).value ?? const [];
    // Only worth a filter row when there is actually something to filter
    // between.
    final showLocationFilter = accessible.length > 1;
    // With several locations in play the list can hold two rows for the same
    // day — the same event marked at each location, or two regular sessions
    // marked together — so each row has to name its location.
    final showLocationName = accessible.length > 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(isSuperAdmin ? '/dashboard' : '/admin');
            }
          },
        ),
        title: const Text('Sessions'),
      ),
      body: Column(
        children: [
          if (showLocationFilter) ...[
            const SizedBox(height: 12),
            _buildLocationFilter(accessible),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LotusIcon(size: 60),
                        const SizedBox(height: 12),
                        Text(
                          'No sessions yet',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final date =
                        DateTime.tryParse(session['session_date'] as String) ??
                            DateTime.now();
                    final present = session['present_count'] as int;
                    final total = session['total_marked'] as int;
                    final locationName = session['location_name'] as String;
                    final notes = session['notes'] as String?;
                    final eventTitle = session['event_title'] as String?;
                    final isEvent = eventTitle != null;
                    final isUnmarked = total == 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      // Events stand out from the weekly programmes.
                      color: isEvent ? AppColors.saffronLight : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isEvent
                              ? Colors.white
                              : AppColors.saffron.withValues(alpha: 0.12),
                          child: Icon(
                            isEvent
                                ? Icons.celebration_outlined
                                : Icons.event_note_outlined,
                            color: AppColors.saffronDark,
                          ),
                        ),
                        // The EVENT badge lives on the subtitle line rather
                        // than here, so a long event name always gets the
                        // full width instead of breaking mid-word.
                        title: Text(
                          isEvent
                              ? eventTitle
                              // Abbreviated weekday: the full name pushed the
                              // title onto a second line on narrower phones.
                              : DateFormat('EEE, d MMM yyyy').format(date),
                          style: TextStyle(
                            fontWeight:
                                isEvent ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        isThreeLine: showLocationName,
                        subtitle: _SessionSubtitle(
                          isEvent: isEvent,
                          locationName: showLocationName ? locationName : null,
                          detail: isEvent
                              ? DateFormat('d MMM yyyy').format(date)
                              : (notes != null && notes.isNotEmpty
                                  ? notes
                                  : '$total marked'),
                        ),
                        // No chevron: the whole row is tappable anyway, and
                        // those 28px are worth more to the title.
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isUnmarked
                                ? AppColors.saffronDark
                                : AppColors.presentGreen
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            isUnmarked ? 'Mark now' : '$present/$total',
                            style: TextStyle(
                              color: isUnmarked
                                  ? Colors.white
                                  : AppColors.presentGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        onTap: () {
                          final base = isSuperAdmin ? '/dashboard' : '/admin';
                          // Nothing marked yet means the detail page would be
                          // empty, so go straight to marking instead.
                          context.push(
                            isUnmarked
                                ? '$base/attendance/session/${session['id']}'
                                : '$base/sessions/${session['id']}',
                          );
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error loading sessions.\n$e',
                      textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationFilter(List<Location> locations) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            selected: _selectedLocationId == null,
            label: const Text('All Locations'),
            selectedColor: AppColors.saffron.withValues(alpha: 0.2),
            checkmarkColor: AppColors.saffronDark,
            onSelected: (_) => setState(() => _selectedLocationId = null),
          ),
          const SizedBox(width: 8),
          ...locations.map((loc) {
            final isSelected = _selectedLocationId == loc.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                label: Text(loc.name),
                selectedColor: AppColors.saffron.withValues(alpha: 0.2),
                checkmarkColor: AppColors.saffronDark,
                onSelected: (_) =>
                    setState(() => _selectedLocationId = loc.id),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Subtitle for a session row. When the admin holds more than one location
/// the location is named with a pin — without it, the same event marked at
/// two locations (or two sessions marked on the same date) are
/// indistinguishable in the list except by who is inside them.
class _SessionSubtitle extends StatelessWidget {
  final bool isEvent;
  final String? locationName;
  final String detail;

  const _SessionSubtitle({
    required this.isEvent,
    required this.locationName,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final detailStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.onSurfaceVariant,
        );

    const badge = Padding(
      padding: EdgeInsets.only(right: 6),
      child: _EventBadge(),
    );

    // Nothing to disambiguate — keep it to a single line so rows stay short.
    if (locationName == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEvent) badge,
          Flexible(
            child: Text(detail, style: detailStyle, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEvent) badge,
            const Icon(Icons.location_on,
                size: 13, color: AppColors.saffronDark),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                locationName!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.saffronDark,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(detail, style: detailStyle),
      ],
    );
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.saffronDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'EVENT',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
