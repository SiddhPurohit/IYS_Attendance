import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motifs.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/members_provider.dart';

class ManageMembersScreen extends ConsumerStatefulWidget {
  const ManageMembersScreen({super.key});

  @override
  ConsumerState<ManageMembersScreen> createState() =>
      _ManageMembersScreenState();
}

class _ManageMembersScreenState extends ConsumerState<ManageMembersScreen> {
  /// Only used by super admin — null means "All Locations".
  String? _selectedLocationId;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manage Devotees')),
            body: const Center(child: Text('Profile not found.')),
          );
        }
        final isSuperAdmin = profile.isSuperAdmin;
        // null means "every location" to the provider, so only a super admin
        // may pass it.
        if (!isSuperAdmin &&
            (profile.locationId == null || profile.locationId!.isEmpty)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Manage Devotees')),
            body: const Center(
              child: Text('No location assigned to your account.'),
            ),
          );
        }
        final effectiveLocationId =
            isSuperAdmin ? _selectedLocationId : profile.locationId;

        return _buildScaffold(context, isSuperAdmin, effectiveLocationId);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Manage Devotees')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Manage Devotees')),
        body: const Center(child: Text('Error loading profile.')),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    bool isSuperAdmin,
    String? effectiveLocationId,
  ) {
    final membersAsync = ref.watch(membersListProvider(effectiveLocationId));
    final locationsAsync = ref.watch(allLocationsProvider);
    final showAll = isSuperAdmin &&
        (effectiveLocationId == null || effectiveLocationId.isEmpty);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(isSuperAdmin ? '/dashboard' : '/admin'),
        ),
        title: const Text('Manage Devotees'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final base = isSuperAdmin ? '/dashboard' : '/admin';
          context.push(
            '$base/members/add',
            extra: (isSuperAdmin && !showAll) ? effectiveLocationId : null,
          );
        },
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          if (isSuperAdmin) ...[
            const SizedBox(height: 12),
            locationsAsync.when(
              data: (locations) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      selected: showAll,
                      label: const Text('All Locations'),
                      selectedColor: AppColors.saffron.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.saffronDark,
                      onSelected: (_) =>
                          setState(() => _selectedLocationId = null),
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
                          onSelected: (_) =>
                              setState(() => _selectedLocationId = loc.id),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              loading: () => const SizedBox(
                height: 32,
                child: Center(child: LinearProgressIndicator()),
              ),
              error: (e, _) => Text('Error loading locations: $e'),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: membersAsync.when(
              data: (members) {
                if (members.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LotusIcon(size: 64),
                        const SizedBox(height: 12),
                        Text(
                          'No devotees added yet',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + Add to get started',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                        ),
                      ],
                    ),
                  );
                }

                final locationNames = <String, String>{
                  for (final loc in locationsAsync.value ?? [])
                    loc.id: loc.name,
                };

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final locationLabel =
                        showAll ? locationNames[member.locationId] : null;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.teal.withValues(alpha: 0.1),
                          child: Text(
                            member.fullName.isNotEmpty
                                ? member.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          member.fullName,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          [
                            if (locationLabel != null) locationLabel,
                            if (member.phone != null) member.phone!,
                          ].join(' • '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () {
                                final base =
                                    isSuperAdmin ? '/dashboard' : '/admin';
                                context.push('$base/members/edit/${member.id}');
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: AppColors.error,
                              ),
                              onPressed: () => _confirmDelete(
                                context,
                                ref,
                                member.id,
                                member.fullName,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('Error: $e', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(
                            membersListProvider(effectiveLocationId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String memberId,
    String memberName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Devotee'),
        content: Text(
          'Remove $memberName from the active list? Their attendance history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await softDeleteMember(memberId);
      ref.invalidate(membersListProvider);
      ref.invalidate(activeMembersProvider);
      ref.invalidate(allActiveMembersProvider);
      ref.invalidate(memberCountByLocationProvider);
      ref.invalidate(memberSummaryProvider);
      // Roster changes shift each session's total member count too.
      ref.invalidate(locationSummaryProvider);
    }
  }
}
