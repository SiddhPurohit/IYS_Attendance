import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
        final isSuperAdmin = profile.isSuperAdmin;
        // null means "every location" to the provider, so only a super admin
        // may pass it. A location admin without a location sees nothing
        // rather than everything.
        if (!isSuperAdmin &&
            (profile.locationId == null || profile.locationId!.isEmpty)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sessions')),
            body: const Center(
              child: Text('No location assigned to your account.'),
            ),
          );
        }
        final filterLocationId =
            isSuperAdmin ? _selectedLocationId : profile.locationId;

        return _buildScaffold(context, isSuperAdmin, filterLocationId);
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
          if (isSuperAdmin) ...[
            const SizedBox(height: 12),
            _buildLocationFilter(),
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
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                isEvent
                                    ? eventTitle
                                    : DateFormat('EEEE, d MMM yyyy')
                                        .format(date),
                                style: TextStyle(
                                  fontWeight:
                                      isEvent ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isEvent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.saffronDark,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'EVENT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          isEvent
                              ? [
                                  DateFormat('d MMM yyyy').format(date),
                                  if (isSuperAdmin) locationName,
                                ].join(' • ')
                              : isSuperAdmin
                                  ? [
                                      locationName,
                                      if (notes != null && notes.isNotEmpty)
                                        notes,
                                    ].join(' • ')
                                  : (notes != null && notes.isNotEmpty
                                      ? notes
                                      : '$total marked'),
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
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right,
                                color: Colors.grey, size: 20),
                          ],
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

  Widget _buildLocationFilter() {
    final locationsAsync = ref.watch(allLocationsProvider);
    return locationsAsync.when(
      data: (locations) => SingleChildScrollView(
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
      ),
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: LinearProgressIndicator()),
      ),
      error: (e, _) => Text('Error loading locations: $e'),
    );
  }
}
