import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/adventure_activity.dart';
import '../../trips/domain/trip.dart';
import '../../trips/domain/trip_organizer.dart';
import '../../trips/presentation/trip_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, required this.authService});

  final User user;
  final AuthService authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TripRepository _repository = TripRepository();
  final _searchController = TextEditingController();
  final Set<String> _busyTripIds = <String>{};
  List<Trip> _latestTrips = const [];
  int _selectedIndex = 0;
  TripOwnershipFilter _ownershipFilter = TripOwnershipFilter.all;
  TripSortOrder _sortOrder = TripSortOrder.recentlyUpdated;
  bool _isSigningOut = false;
  bool _isCreatingTrip = false;
  bool _isSendingVerification = false;
  bool _isRefreshingVerification = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _createOrRefreshProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearOrganizationControls() {
    _searchController.clear();
    setState(() {
      _ownershipFilter = TripOwnershipFilter.all;
      _sortOrder = TripSortOrder.recentlyUpdated;
    });
  }

  Future<void> _createOrRefreshProfile() async {
    try {
      await _repository.ensureUserProfile(widget.user);
    } catch (_) {
      if (mounted) {
        _showMessage('Your profile could not be synced. Please try again.');
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await widget.authService.signOut();
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  Future<void> _openAccountSettings() async {
    final action = await showDialog<_AccountAction>(
      context: context,
      builder: (_) => _AccountDialog(user: widget.user),
    );
    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _AccountAction.resetPassword:
        await _sendPasswordReset();
        return;
      case _AccountAction.deleteAccount:
        await _confirmAndDeleteAccount();
        return;
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = widget.user.email;
    if (email == null || email.isEmpty) {
      _showMessage('No email address is available for this account.');
      return;
    }
    try {
      await widget.authService.sendPasswordResetEmail(email);
      if (mounted) {
        _showMessage('Password reset email sent.');
      }
    } on FirebaseAuthException {
      if (mounted) {
        _showMessage('The password reset email could not be sent.');
      }
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeletingAccount = true);
    try {
      await widget.authService.deleteAccount();
    } on AccountServiceException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Your account could not be deleted. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  Future<void> _createTrip() async {
    final draft = await showDialog<_TripDraft>(
      context: context,
      builder: (_) => const _TripDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _isCreatingTrip = true);
    try {
      await _repository.createTrip(
        ownerId: widget.user.uid,
        name: draft.name,
        description: draft.description,
        location: draft.location,
        startDate: draft.startDate,
        endDate: draft.endDate,
      );
      if (mounted) {
        _showMessage('Trip created.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('The trip could not be created. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingTrip = false);
      }
    }
  }

  Future<void> _sendVerification() async {
    setState(() => _isSendingVerification = true);
    try {
      await widget.authService.sendEmailVerification();
      if (mounted) {
        _showMessage('Verification email sent. Check your inbox.');
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          error.code == 'too-many-requests'
              ? 'Please wait before requesting another verification email.'
              : 'The verification email could not be sent.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingVerification = false);
      }
    }
  }

  Future<void> _refreshVerification() async {
    setState(() => _isRefreshingVerification = true);
    try {
      final verified = await widget.authService.refreshEmailVerification();
      if (mounted) {
        _showMessage(
          verified
              ? 'Email verified. You can now receive shared adventures.'
              : 'Email is not verified yet. Open the link in your inbox first.',
        );
      }
    } on FirebaseAuthException catch (_) {
      if (mounted) {
        _showMessage('Verification status could not be refreshed.');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingVerification = false);
      }
    }
  }

  Future<void> _openTrip(Trip trip, {bool startWithNewEntry = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(
          trip: trip,
          userId: widget.user.uid,
          repository: _repository,
          startWithNewEntry: startWithNewEntry,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showCreateMenu() async {
    final action = await showModalBottomSheet<_CreateAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.landscape_outlined),
                ),
                title: const Text('New adventure'),
                subtitle: const Text('Plan a trip and invite trusted people.'),
                onTap: () => Navigator.of(context).pop(_CreateAction.adventure),
              ),
              ListTile(
                enabled: _latestTrips.any(
                  (trip) =>
                      trip.accessRole == 'owner' || trip.accessRole == 'editor',
                ),
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_note_outlined),
                ),
                title: const Text('New journal entry'),
                subtitle: Text(
                  _latestTrips.isEmpty
                      ? 'Create an adventure first.'
                      : 'Add a memory to one of your adventures.',
                ),
                onTap: () => Navigator.of(context).pop(_CreateAction.entry),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _CreateAction.adventure:
        await _createTrip();
      case _CreateAction.entry:
        await _chooseAdventureForEntry();
    }
  }

  Future<void> _chooseAdventureForEntry() async {
    final editableTrips = _latestTrips
        .where(
          (trip) => trip.accessRole == 'owner' || trip.accessRole == 'editor',
        )
        .toList(growable: false);
    if (editableTrips.isEmpty) {
      _showMessage('Create an adventure before adding a journal entry.');
      return;
    }

    final trip = await showModalBottomSheet<Trip>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose an adventure',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: editableTrips.length,
                  itemBuilder: (context, index) {
                    final candidate = editableTrips[index];
                    return ListTile(
                      leading: const Icon(Icons.hiking),
                      title: Text(candidate.name),
                      subtitle: candidate.location.isEmpty
                          ? null
                          : Text(candidate.location),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(candidate),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (trip != null && mounted) {
      await _openTrip(trip, startWithNewEntry: true);
    }
  }

  Future<void> _editTrip(Trip trip) async {
    final draft = await showDialog<_TripDraft>(
      context: context,
      builder: (_) => _TripDialog(trip: trip),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _busyTripIds.add(trip.id));
    try {
      await _repository.updateTrip(
        tripId: trip.id,
        name: draft.name,
        description: draft.description,
        location: draft.location,
        startDate: draft.startDate,
        endDate: draft.endDate,
      );
      if (mounted) {
        _showMessage('Adventure updated.');
      }
    } on FirebaseException catch (error) {
      debugPrint('Trip update failed (${error.code}): ${error.message}');
      if (mounted) {
        _showMessage('The adventure could not be updated.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyTripIds.remove(trip.id));
      }
    }
  }

  Future<void> _deleteTrip(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this adventure?'),
        content: Text(
          '“${trip.name}” and all of its journal entries, photos, and shared access will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete adventure'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busyTripIds.add(trip.id));
    try {
      await _repository.deleteTrip(trip.id);
      if (mounted) {
        _showMessage('Adventure deleted.');
      }
    } on TripServiceException catch (error) {
      debugPrint('Trip delete failed: ${error.message}');
      if (mounted) {
        _showMessage('The adventure could not be deleted safely.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyTripIds.remove(trip.id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildAdventuresPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your adventures'),
        actions: [
          IconButton(
            onPressed: _isDeletingAccount ? null : _openAccountSettings,
            tooltip: 'Account settings',
            icon: _isDeletingAccount
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            onPressed: _isSigningOut ? null : _signOut,
            tooltip: 'Sign out',
            icon: _isSigningOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreatingTrip ? null : _createTrip,
        icon: _isCreatingTrip
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('New trip'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.user.emailVerified)
              MaterialBanner(
                content: const Text(
                  'Verify your email so other people can safely share adventures with you.',
                ),
                leading: const Icon(Icons.mark_email_unread_outlined),
                actions: [
                  TextButton(
                    onPressed: _isRefreshingVerification
                        ? null
                        : _refreshVerification,
                    child: Text(
                      _isRefreshingVerification ? 'Checking…' : 'Check status',
                    ),
                  ),
                  TextButton(
                    onPressed: _isSendingVerification
                        ? null
                        : _sendVerification,
                    child: Text(
                      _isSendingVerification ? 'Sending…' : 'Send email',
                    ),
                  ),
                ],
              ),
            Expanded(
              child: StreamBuilder<List<Trip>>(
                stream: _repository.watchAccessibleTrips(widget.user.uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Trips are unavailable',
                      message: 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: () => setState(() {}),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final trips = snapshot.data ?? const <Trip>[];
                  if (trips.isEmpty) {
                    return _MessageState(
                      icon: Icons.landscape_outlined,
                      title: 'Start your first adventure',
                      message: 'Create a private trip, then capture the moments you want to remember.',
                      actionLabel: 'Create a trip',
                      onAction: _isCreatingTrip ? null : _createTrip,
                    );
                  }

                  final visibleTrips = organizeTrips(
                    trips,
                    query: _searchController.text,
                    filter: _ownershipFilter,
                    sortOrder: _sortOrder,
                  );
                  return Column(
                    children: [
                      AdventureOrganizer(
                        searchController: _searchController,
                        filter: _ownershipFilter,
                        sortOrder: _sortOrder,
                        visibleCount: visibleTrips.length,
                        totalCount: trips.length,
                        onSearchChanged: (_) => setState(() {}),
                        onSearchClear: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        onFilterChanged: (filter) {
                          setState(() => _ownershipFilter = filter);
                        },
                        onSortChanged: (sortOrder) {
                          setState(() => _sortOrder = sortOrder);
                        },
                        onClear: _clearOrganizationControls,
                      ),
                      Expanded(
                        child: visibleTrips.isEmpty
                            ? _MessageState(
                                icon: Icons.search_off_outlined,
                                title: 'No matching adventures',
                                message: 'Try a different search or clear the current filters.',
                                actionLabel: 'Clear search and filters',
                                onAction: _clearOrganizationControls,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  104,
                                ),
                                itemCount: visibleTrips.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final trip = visibleTrips[index];
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Semantics(
                                      container: true,
                                      button: true,
                                      label: 'Open ${trip.name}',
                                      child: InkWell(
                                        onTap: _busyTripIds.contains(trip.id)
                                            ? null
                                            : () => _openTrip(trip),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Row(
                                            children: [
                                              const CircleAvatar(
                                                radius: 24,
                                                child: Icon(Icons.hiking),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      trip.name,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleLarge,
                                                    ),
                                                    if (trip
                                                            .location
                                                            .isNotEmpty ||
                                                        trip.startDate !=
                                                            null ||
                                                        trip.endDate !=
                                                            null) ...[
                                                      const SizedBox(height: 7),
                                                      Wrap(
                                                        spacing: 14,
                                                        runSpacing: 6,
                                                        children: [
                                                          if (trip
                                                              .location
                                                              .isNotEmpty)
                                                            _TripFact(
                                                              icon: Icons
                                                                  .place_outlined,
                                                              label:
                                                                  trip.location,
                                                            ),
                                                          if (trip.startDate !=
                                                                  null ||
                                                              trip.endDate !=
                                                                  null)
                                                            _TripFact(
                                                              icon: Icons
                                                                  .calendar_today_outlined,
                                                              label:
                                                                  _formatTripDates(
                                                                    context,
                                                                    trip,
                                                                  ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                    if (trip
                                                        .description
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        trip.description,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              if (trip.accessRole !=
                                                  'owner') ...[
                                                const SizedBox(width: 12),
                                                Chip(
                                                  avatar: Icon(
                                                    trip.accessRole == 'editor'
                                                        ? Icons.edit_outlined
                                                        : Icons
                                                              .visibility_outlined,
                                                    size: 16,
                                                  ),
                                                  label: Text(
                                                    trip.accessRole == 'editor'
                                                        ? 'Editor'
                                                        : 'Shared',
                                                  ),
                                                ),
                                              ],
                                              if (_busyTripIds.contains(
                                                trip.id,
                                              ))
                                                const Padding(
                                                  padding: EdgeInsets.all(12),
                                                  child: SizedBox.square(
                                                    dimension: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                )
                                              else if (trip.accessRole ==
                                                  'owner')
                                                PopupMenuButton<_TripAction>(
                                                  tooltip: 'Adventure options',
                                                  onSelected: (action) {
                                                    switch (action) {
                                                      case _TripAction.edit:
                                                        _editTrip(trip);
                                                      case _TripAction.delete:
                                                        _deleteTrip(trip);
                                                    }
                                                  },
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                      value: _TripAction.edit,
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons.edit_outlined,
                                                        ),
                                                        title: Text(
                                                          'Edit adventure',
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: _TripAction.delete,
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons.delete_outline,
                                                        ),
                                                        title: Text(
                                                          'Delete adventure',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Trip>>(
        stream: _repository.watchAccessibleTrips(widget.user.uid),
        builder: (context, snapshot) {
          final trips = snapshot.data ?? _latestTrips;
          _latestTrips = trips;

          return switch (_selectedIndex) {
            0 => _FeedPage(
              repository: _repository,
              trips: trips,
              isLoading:
                  snapshot.connectionState == ConnectionState.waiting &&
                  trips.isEmpty,
              error: snapshot.error,
              onOpenTrip: _openTrip,
              onCreate: _showCreateMenu,
            ),
            1 => _buildAdventuresPage(context),
            3 => _CirclePage(
              onOpenAdventures: () => setState(() => _selectedIndex = 1),
            ),
            4 => _ProfilePage(
              user: widget.user,
              isSigningOut: _isSigningOut,
              isDeletingAccount: _isDeletingAccount,
              onOpenSettings: _openAccountSettings,
              onSignOut: _signOut,
              onSendVerification: _sendVerification,
              onRefreshVerification: _refreshVerification,
              isSendingVerification: _isSendingVerification,
              isRefreshingVerification: _isRefreshingVerification,
            ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
      bottomNavigationBar: TrekItNavigationBar(
        selectedIndex: _selectedIndex,
        onSelected: (index) {
          if (index == 2) {
            _showCreateMenu();
            return;
          }
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class TrekItNavigationBar extends StatelessWidget {
  const TrekItNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dynamic_feed_outlined),
          selectedIcon: Icon(Icons.dynamic_feed),
          label: 'Feed',
        ),
        const NavigationDestination(
          icon: Icon(Icons.landscape_outlined),
          selectedIcon: Icon(Icons.landscape),
          label: 'Adventures',
        ),
        NavigationDestination(
          icon: Icon(
            Icons.add_circle,
            color: Theme.of(context).colorScheme.secondary,
            size: 30,
          ),
          label: 'Create',
        ),
        const NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Circle',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}

enum _CreateAction { adventure, entry }

class _FeedPage extends StatelessWidget {
  const _FeedPage({
    required this.repository,
    required this.trips,
    required this.isLoading,
    required this.error,
    required this.onOpenTrip,
    required this.onCreate,
  });

  final TripRepository repository;
  final List<Trip> trips;
  final bool isLoading;
  final Object? error;
  final ValueChanged<Trip> onOpenTrip;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('trekit-t.png', width: 38, height: 38),
            ),
            const SizedBox(width: 10),
            const Text('TrekIt'),
          ],
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null && trips.isEmpty
            ? _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Feed is unavailable',
                message: 'Check your connection and try again.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(
                    'Feed',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Private activity from adventures you are authorized to view.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  if (trips.isEmpty)
                    _FeedEmptyState(onCreate: onCreate)
                  else
                    StreamBuilder<List<AdventureActivity>>(
                      stream: repository.watchActivityFeed(trips),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const _InlineMessage(
                            icon: Icons.cloud_off_outlined,
                            title: 'Activity is unavailable',
                            message: 'Check your connection and try again.',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final activity = snapshot.data!;
                        if (activity.isEmpty) {
                          return _FeedEmptyState(onCreate: onCreate);
                        }
                        return Column(
                          children: [
                            for (final item in activity.take(100)) ...[
                              _ActivityCard(
                                activity: item,
                                onTap: () => onOpenTrip(item.trip),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.onTap});

  final AdventureActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = activity.entry;
    final isEntry = activity.type == AdventureActivityType.journalEntry;
    final localizations = MaterialLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Icon(
                  isEntry ? Icons.auto_stories_outlined : Icons.flag_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEntry ? entry!.title : 'Adventure started',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEntry
                          ? 'A memory was added to ${activity.trip.name}.'
                          : '${activity.trip.name} was created.',
                    ),
                    if (entry != null && entry.body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        entry.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          localizations.formatMediumDate(activity.occurredAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (entry?.imagePath != null) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.photo_outlined, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Photo',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _InlineMessage(
      icon: Icons.dynamic_feed_outlined,
      title: 'Your private feed starts here',
      message: 'Create an adventure or add a journal entry to begin your activity timeline.',
      actionLabel: 'Create',
      onAction: onCreate,
    );
  }
}

class _CirclePage extends StatelessWidget {
  const _CirclePage({required this.onOpenAdventures});

  final VoidCallback onOpenAdventures;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circle')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Your trusted people',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Circle invitations and TrekIt IDs are the next collaboration layer. For now, you can securely share access from each adventure.',
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.group_outlined, size: 54),
                    const SizedBox(height: 16),
                    const Text(
                      'Share an adventure',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Open one of your adventures and use its sharing controls to invite an existing TrekIt account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onOpenAdventures,
                      child: const Text('Open Adventures'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.user,
    required this.isSigningOut,
    required this.isDeletingAccount,
    required this.onOpenSettings,
    required this.onSignOut,
    required this.onSendVerification,
    required this.onRefreshVerification,
    required this.isSendingVerification,
    required this.isRefreshingVerification,
  });

  final User user;
  final bool isSigningOut;
  final bool isDeletingAccount;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;
  final VoidCallback onSendVerification;
  final VoidCallback onRefreshVerification;
  final bool isSendingVerification;
  final bool isRefreshingVerification;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      child: Icon(Icons.person_outline, size: 38),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.displayName?.trim().isNotEmpty == true
                          ? user.displayName!.trim()
                          : 'TrekIt Explorer',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.email ?? 'TrekIt account',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                        user.emailVerified
                            ? Icons.verified_outlined
                            : Icons.mark_email_unread_outlined,
                      ),
                      label: Text(
                        user.emailVerified
                            ? 'Email verified'
                            : 'Email not verified',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!user.emailVerified) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isSendingVerification ? null : onSendVerification,
                icon: const Icon(Icons.outgoing_mail),
                label: Text(
                  isSendingVerification
                      ? 'Sending…'
                      : 'Send verification email',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isRefreshingVerification
                    ? null
                    : onRefreshVerification,
                icon: const Icon(Icons.refresh),
                label: Text(
                  isRefreshingVerification ? 'Checking…' : 'Check verification',
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isDeletingAccount ? null : onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Account settings'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isSigningOut ? null : onSignOut,
              icon: const Icon(Icons.logout),
              label: Text(isSigningOut ? 'Signing out…' : 'Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class AdventureOrganizer extends StatelessWidget {
  const AdventureOrganizer({
    super.key,
    required this.searchController,
    required this.filter,
    required this.sortOrder,
    required this.visibleCount,
    required this.totalCount,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final TripOwnershipFilter filter;
  final TripSortOrder sortOrder;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final ValueChanged<TripOwnershipFilter> onFilterChanged;
  final ValueChanged<TripSortOrder> onSortChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasActiveControls =
        searchController.text.trim().isNotEmpty ||
        filter != TripOwnershipFilter.all ||
        sortOrder != TripSortOrder.recentlyUpdated;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search adventures, locations, or memories',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onSearchClear,
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: filter == TripOwnershipFilter.all,
                      onSelected: () =>
                          onFilterChanged(TripOwnershipFilter.all),
                    ),
                    _FilterChip(
                      label: 'Mine',
                      selected: filter == TripOwnershipFilter.owned,
                      onSelected: () =>
                          onFilterChanged(TripOwnershipFilter.owned),
                    ),
                    _FilterChip(
                      label: 'Shared',
                      selected: filter == TripOwnershipFilter.shared,
                      onSelected: () =>
                          onFilterChanged(TripOwnershipFilter.shared),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<TripSortOrder>(
                tooltip: 'Sort adventures',
                initialValue: sortOrder,
                onSelected: onSortChanged,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: TripSortOrder.recentlyUpdated,
                    child: Text('Recently updated'),
                  ),
                  PopupMenuItem(
                    value: TripSortOrder.newestTripDate,
                    child: Text('Newest trip date'),
                  ),
                  PopupMenuItem(
                    value: TripSortOrder.name,
                    child: Text('Name A–Z'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 20),
                      const SizedBox(width: 6),
                      Text(_sortLabel(sortOrder)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  visibleCount == totalCount
                      ? '$totalCount ${totalCount == 1 ? 'adventure' : 'adventures'}'
                      : '$visibleCount of $totalCount adventures',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (hasActiveControls)
                TextButton(onPressed: onClear, child: const Text('Reset')),
            ],
          ),
        ],
      ),
    );
  }

  String _sortLabel(TripSortOrder value) {
    return switch (value) {
      TripSortOrder.recentlyUpdated => 'Recent',
      TripSortOrder.newestTripDate => 'Trip date',
      TripSortOrder.name => 'A–Z',
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

enum _AccountAction { resetPassword, deleteAccount }

class _AccountDialog extends StatelessWidget {
  const _AccountDialog({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Account settings'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: SelectableText(user.email ?? 'TrekIt account'),
              subtitle: Text(
                user.emailVerified ? 'Email verified' : 'Email not verified',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_AccountAction.resetPassword),
              icon: const Icon(Icons.password_outlined),
              label: const Text('Send password reset email'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_AccountAction.deleteAccount),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Delete account and private data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmationController = TextEditingController();

  bool get _isConfirmed =>
      _confirmationController.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Permanently delete your account?'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your account, adventures you own, journal entries you wrote, uploaded photos, and access to shared adventures. This cannot be undone.',
            ),
            const SizedBox(height: 18),
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmationController,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Confirmation'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              'For security, you may be asked to sign out and sign back in first.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isConfirmed
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _TripDraft {
  const _TripDraft({
    required this.name,
    required this.description,
    required this.location,
    this.startDate,
    this.endDate,
  });

  final String name;
  final String description;
  final String location;
  final DateTime? startDate;
  final DateTime? endDate;
}

enum _TripAction { edit, delete }

class _TripDialog extends StatefulWidget {
  const _TripDialog({this.trip});

  final Trip? trip;

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.trip?.name);
  late final _descriptionController = TextEditingController(
    text: widget.trip?.description,
  );
  late final _locationController = TextEditingController(
    text: widget.trip?.location,
  );
  late DateTime? _startDate = widget.trip?.startDate;
  late DateTime? _endDate = widget.trip?.endDate;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Choose a start date',
    );
    if (selected != null && mounted) {
      setState(() {
        _startDate = selected;
        if (_endDate != null && _endDate!.isBefore(selected)) {
          _endDate = selected;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Choose an end date',
    );
    if (selected != null && mounted) {
      setState(() => _endDate = selected);
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _TripDraft(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.trip == null ? 'Create a trip' : 'Edit adventure'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Trip name'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter a trip name.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  maxLength: 160,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickStartDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          _startDate == null
                              ? 'Start date'
                              : MaterialLocalizations.of(context)
                                    .formatMediumDate(_startDate!),
                        ),
                      ),
                    ),
                    if (_startDate != null)
                      IconButton(
                        onPressed: () => setState(() => _startDate = null),
                        tooltip: 'Clear start date',
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickEndDate,
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          _endDate == null
                              ? 'End date'
                              : MaterialLocalizations.of(context)
                                    .formatMediumDate(_endDate!),
                        ),
                      ),
                    ),
                    if (_endDate != null)
                      IconButton(
                        onPressed: () => setState(() => _endDate = null),
                        tooltip: 'Clear end date',
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.trip == null ? 'Create' : 'Save changes'),
        ),
      ],
    );
  }
}

class _TripFact extends StatelessWidget {
  const _TripFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

String _formatTripDates(BuildContext context, Trip trip) {
  final localizations = MaterialLocalizations.of(context);
  final start = trip.startDate;
  final end = trip.endDate;
  if (start != null && end != null) {
    return '${localizations.formatMediumDate(start)} – ${localizations.formatMediumDate(end)}';
  }
  return localizations.formatMediumDate(start ?? end!);
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
