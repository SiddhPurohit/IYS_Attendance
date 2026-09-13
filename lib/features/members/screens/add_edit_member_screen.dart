import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../providers/members_provider.dart';

class AddEditMemberScreen extends ConsumerStatefulWidget {
  final String? memberId;

  /// Pre-selects a location in the dropdown when adding a new member as
  /// super admin (e.g. arriving from a location-filtered members list).
  final String? initialLocationId;

  const AddEditMemberScreen({super.key, this.memberId, this.initialLocationId});

  bool get isEditing => memberId != null;

  @override
  ConsumerState<AddEditMemberScreen> createState() =>
      _AddEditMemberScreenState();
}

class _AddEditMemberScreenState extends ConsumerState<AddEditMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _dob;
  // Defaults to today for a new devotee; overwritten with the stored
  // value when editing an existing one.
  DateTime _joinedOn = DateTime.now();
  bool _saving = false;
  bool _loaded = false;
  late String? _selectedLocationId = widget.initialLocationId;
  // The member's actual location when editing — the location dropdown is
  // hidden in edit mode, so this is what we use for cache invalidation and
  // for knowing which location's list to refresh.
  String? _memberLocationId;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Devotee' : 'Add Devotee';

    // If editing, load existing data
    if (widget.isEditing && !_loaded) {
      final memberAsync = ref.watch(memberByIdProvider(widget.memberId!));
      return memberAsync.when(
        data: (member) {
          if (member != null && !_loaded) {
            _nameController.text = member.fullName;
            _phoneController.text = member.phone ?? '';
            _emailController.text = member.email ?? '';
            _dob = member.dob;
            _joinedOn = member.joinedOn;
            _memberLocationId = member.locationId;
            _loaded = true;
          }
          return _buildForm(context, title);
        },
        loading: () => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(child: Text('Error: $e')),
        ),
      );
    }

    return _buildForm(context, title);
  }

  /// Returns to whichever screen opened the editor (Manage Devotees, the
  /// dashboard, or a devotee's detail page). Falls back to the list when
  /// there is nothing to pop — e.g. the edit URL was opened directly.
  void _leave(bool isSuperAdmin) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(isSuperAdmin ? '/dashboard/members' : '/admin/members');
    }
  }

  Widget _buildForm(BuildContext context, String title) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.asData?.value;
    final isSuperAdmin = profile?.isSuperAdmin ?? false;
    final locationsAsync = ref.watch(allLocationsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leave(isSuperAdmin),
        ),
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full name (required)
                Text(
                  'Full Name *',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Enter full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (!widget.isEditing && isSuperAdmin) ...[
                  Text(
                    'Location *',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  locationsAsync.when(
                    data: (locations) => DropdownButtonFormField<String>(
                      initialValue: _selectedLocationId,
                      decoration: const InputDecoration(
                        hintText: 'Select location',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: locations
                          .map(
                            (loc) => DropdownMenuItem<String>(
                              value: loc.id,
                              child: Text(loc.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedLocationId = value);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Location is required';
                        }
                        return null;
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error loading locations: $e'),
                  ),
                  const SizedBox(height: 24),
                ],

                // Date of birth (required)
                Text(
                  'Date of Birth *',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(2005),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme:
                                Theme.of(context).colorScheme.copyWith(
                                      primary: AppColors.saffron,
                                    ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _dob = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.cake_outlined),
                      hintText: 'Select date of birth',
                    ),
                    child: Text(
                      _dob != null
                          ? DateFormat('d MMMM yyyy').format(_dob!)
                          : 'Not set',
                      style: _dob != null
                          ? Theme.of(context).textTheme.bodyLarge
                          : Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Joining date (required, defaults to today)
                Text(
                  'Joining Date *',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sessions before this date are not counted in his attendance.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joinedOn,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme:
                                Theme.of(context).colorScheme.copyWith(
                                      primary: AppColors.saffron,
                                    ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _joinedOn = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.event_available_outlined),
                    ),
                    child: Text(
                      DateFormat('d MMMM yyyy').format(_joinedOn),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Phone (required)
                Text(
                  'Phone *',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Phone number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Phone is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Email (optional)
                Text(
                  'Email',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && !v.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 40),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.isEditing ? 'Update' : 'Add Devotee'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Date of birth is required'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final profile = await ref.read(currentProfileProvider.future);
      // When editing, the location dropdown is hidden — use the member's
      // actual location, not the (empty) dropdown selection.
      final locationId = widget.isEditing
          ? (_memberLocationId ?? '')
          : ((profile?.isSuperAdmin ?? false)
              ? (_selectedLocationId ?? '')
              : (profile?.locationId ?? ''));

      if (widget.isEditing) {
        await updateMember(
          memberId: widget.memberId!,
          fullName: _nameController.text.trim(),
          dob: _dob,
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          joinedOn: _joinedOn,
        );
      } else {
        await addMember(
          fullName: _nameController.text.trim(),
          dob: _dob,
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          locationId: locationId,
          joinedOn: _joinedOn,
        );
      }

      if (!mounted) return;

      // Invalidate every member/attendance/dashboard list that could be
      // showing this member, across all locations and filters, so the
      // change is reflected immediately everywhere (Manage Boys, Mark
      // Attendance, and the super admin dashboard).
      ref.invalidate(membersListProvider);
      ref.invalidate(activeMembersProvider);
      ref.invalidate(allActiveMembersProvider);
      ref.invalidate(memberCountByLocationProvider);
      ref.invalidate(memberSummaryProvider);
      // The boy's own detail page and this form's loader.
      ref.invalidate(memberDetailProvider);
      ref.invalidate(memberByIdProvider);
      // Roster changes shift each session's total member count too.
      ref.invalidate(locationSummaryProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Devotee updated successfully!'
                : 'Devotee added successfully!',
          ),
          backgroundColor: AppColors.presentGreen,
        ),
      );

      _leave(profile?.isSuperAdmin == true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
