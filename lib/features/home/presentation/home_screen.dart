import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/drafts/local_draft_store.dart';
import '../../../core/time/friendly_time.dart';
import '../../auth/data/auth_service.dart';
import '../../circle/data/circle_repository.dart';
import '../../circle/domain/circle_state.dart';
import '../../../core/download/download_file.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/data/push_notification_service.dart';
import '../../notifications/domain/app_notification.dart';
import '../../notifications/domain/notification_destination.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile_state.dart';
import '../../trips/data/quick_snippet_queue.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/adventure_activity.dart';
import '../../trips/domain/quick_snippet.dart';
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
  late final CircleRepository _circleRepository = CircleRepository();
  late final ProfileRepository _profileRepository = ProfileRepository();
  late final NotificationRepository _notificationRepository =
      NotificationRepository();
  late final PushNotificationService _pushNotificationService =
      PushNotificationService();
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  NotificationDestination? _pendingNotificationDestination =
      NotificationDestination.fromUri(Uri.base);
  bool _isOpeningNotificationDestination = false;
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
  int _feedRevision = 0;

  @override
  void initState() {
    super.initState();
    _createOrRefreshProfile();
    _initializePushNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_foregroundMessageSubscription?.cancel());
    unawaited(_pushNotificationService.dispose());
    super.dispose();
  }

  Future<void> _initializePushNotifications() async {
    try {
      await _pushNotificationService.initializeSilently();
      _foregroundMessageSubscription ??= _pushNotificationService
          .foregroundMessages
          .listen((message) {
            if (!mounted) return;
            final title = message.notification?.title ?? 'TrekIt update';
            final body = message.notification?.body;
            final destination = NotificationDestination.fromMessageData(
              message.data,
            );
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(body == null ? title : '$title — $body'),
                  action: destination.isActionable
                      ? SnackBarAction(
                          label: 'Open',
                          onPressed: () => unawaited(
                            _openNotificationDestination(destination),
                          ),
                        )
                      : null,
                ),
              );
          });
    } catch (_) {
      // Push is optional; the private in-app inbox remains available.
    }
  }

  Future<void> _openNotificationDestination(
    NotificationDestination destination,
  ) async {
    if (!mounted) return;
    if (destination.kind == NotificationDestinationKind.circle) {
      setState(() => _selectedIndex = 3);
      return;
    }
    final trip = _latestTrips
        .where((item) => item.id == destination.tripId)
        .firstOrNull;
    if (trip == null) {
      _showMessage('That adventure is no longer available to this account.');
      return;
    }
    await _openTrip(trip);
  }

  void _schedulePendingNotificationDestination({
    required List<Trip> trips,
    required bool tripsLoaded,
  }) {
    final destination = _pendingNotificationDestination;
    if (destination == null ||
        !destination.isActionable ||
        _isOpeningNotificationDestination) {
      return;
    }
    if (destination.kind == NotificationDestinationKind.adventure &&
        !tripsLoaded &&
        !trips.any((trip) => trip.id == destination.tripId)) {
      return;
    }
    _pendingNotificationDestination = null;
    _isOpeningNotificationDestination = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _openNotificationDestination(destination);
      _isOpeningNotificationDestination = false;
    });
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
      builder: (_) =>
          _TripDialog(repository: _repository, userId: widget.user.uid),
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
        status: draft.status,
        startDate: draft.startDate,
        endDate: draft.endDate,
        coverImageBytes: draft.coverImageBytes,
        coverContentType: draft.coverContentType,
      );
      await LocalDraftStore().clearAdventure(widget.user.uid);
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

  Future<void> _openTrip(
    Trip trip, {
    bool startWithNewEntry = false,
    bool startEntryWithPhoto = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(
          trip: trip,
          userId: widget.user.uid,
          repository: _repository,
          startWithNewEntry: startWithNewEntry,
          startEntryWithPhoto: startEntryWithPhoto,
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
      builder: (context) => CreateMenuSheet(
        canAddContent: _editableTrips.isNotEmpty,
        onCreateAdventure: () =>
            Navigator.of(context).pop(_CreateAction.adventure),
        onCreateEntry: () => Navigator.of(context).pop(_CreateAction.entry),
        onAddPhoto: () => Navigator.of(context).pop(_CreateAction.photo),
        onCreateSnippet: () => Navigator.of(context).pop(_CreateAction.snippet),
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
      case _CreateAction.photo:
        await _chooseAdventureForEntry(startWithPhoto: true);
      case _CreateAction.snippet:
        await _createQuickSnippet();
    }
  }

  List<Trip> get _editableTrips => _latestTrips
      .where(
        (trip) => trip.accessRole == 'owner' || trip.accessRole == 'editor',
      )
      .toList(growable: false);

  Future<void> _chooseAdventureForEntry({bool startWithPhoto = false}) async {
    final editableTrips = _editableTrips;
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
      await _openTrip(
        trip,
        startWithNewEntry: true,
        startEntryWithPhoto: startWithPhoto,
      );
    }
  }

  Future<void> _createQuickSnippet() async {
    final editableTrips = _editableTrips;
    if (editableTrips.isEmpty) {
      _showMessage('Create an adventure before adding a Quick Snippet.');
      return;
    }
    final draft = await showDialog<_QuickSnippetDraft>(
      context: context,
      builder: (_) => _QuickSnippetDialog(trips: editableTrips),
    );
    if (draft == null || !mounted) return;

    final snippet = QueuedSnippet.create(
      tripId: draft.trip.id,
      tripName: draft.trip.name,
      text: draft.text,
      location: draft.location,
    );
    final queue = QuickSnippetQueue();
    var message = 'Quick Snippet posted.';
    if (draft.saveLocally) {
      await queue.enqueue(widget.user.uid, snippet);
      message = 'Saved locally. It is waiting to be posted.';
    } else {
      try {
        await _repository
            .createSnippet(
              tripId: snippet.tripId,
              snippetId: snippet.id,
              authorId: widget.user.uid,
              text: snippet.text,
              location: snippet.location,
              capturedAt: snippet.capturedAt,
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        await queue.enqueue(widget.user.uid, snippet);
        message = 'Could not post now, so it was saved locally for retry.';
      }
    }
    if (mounted) {
      setState(() {
        _selectedIndex = 0;
        _feedRevision++;
      });
      _showMessage(message);
    }
  }

  Future<void> _editTrip(Trip trip) async {
    final draft = await showDialog<_TripDraft>(
      context: context,
      builder: (_) => _TripDialog(
        repository: _repository,
        userId: widget.user.uid,
        trip: trip,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _busyTripIds.add(trip.id));
    try {
      await _repository.updateTrip(
        tripId: trip.id,
        ownerId: trip.ownerId,
        name: draft.name,
        description: draft.description,
        location: draft.location,
        status: draft.status,
        startDate: draft.startDate,
        endDate: draft.endDate,
        coverImageBytes: draft.coverImageBytes,
        coverContentType: draft.coverContentType,
        removeCover: draft.removeCover,
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

  Widget _buildAdventureCard(Trip trip) {
    final isBusy = _busyTripIds.contains(trip.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        label: 'Open ${trip.name}',
        child: InkWell(
          onTap: isBusy ? null : () => _openTrip(trip),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: trip.coverImagePath == null
                    ? Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.landscape_outlined,
                          size: 72,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : _TripCover(repository: _repository, trip: trip),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.status.label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _statusColor(context, trip.status),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            trip.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (isBusy)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (trip.accessRole == 'owner')
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
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Edit adventure'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _TripAction.delete,
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete adventure'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (trip.location.isNotEmpty ||
                        trip.startDate != null ||
                        trip.endDate != null ||
                        trip.accessRole != 'owner') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (trip.location.isNotEmpty)
                            _TripFact(
                              icon: Icons.place_outlined,
                              label: trip.location,
                            ),
                          if (trip.startDate != null || trip.endDate != null)
                            _TripFact(
                              icon: Icons.calendar_today_outlined,
                              label: _formatTripDates(context, trip),
                            ),
                          if (trip.accessRole != 'owner')
                            _TripFact(
                              icon: trip.accessRole == 'editor'
                                  ? Icons.edit_outlined
                                  : Icons.visibility_outlined,
                              label: trip.accessRole == 'editor'
                                  ? 'Editor access'
                                  : 'Shared with you',
                            ),
                        ],
                      ),
                    ],
                    if (trip.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        trip.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  final groupedTrips = <Trip>[
                    for (final status in TripStatus.values)
                      ...visibleTrips.where((trip) => trip.status == status),
                  ];
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
                                itemCount: groupedTrips.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final trip = groupedTrips[index];
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (index == 0 ||
                                          groupedTrips[index - 1].status !=
                                              trip.status)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            2,
                                            12,
                                            2,
                                            12,
                                          ),
                                          child: Text(
                                            trip.status.label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall,
                                          ),
                                        ),
                                      _buildAdventureCard(trip),
                                    ],
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
          _schedulePendingNotificationDestination(
            trips: trips,
            tripsLoaded: snapshot.connectionState != ConnectionState.waiting,
          );

          return switch (_selectedIndex) {
            0 => _FeedPage(
              key: ValueKey('feed-$_feedRevision'),
              repository: _repository,
              notificationRepository: _notificationRepository,
              userId: widget.user.uid,
              trips: trips,
              isLoading:
                  snapshot.connectionState == ConnectionState.waiting &&
                  trips.isEmpty,
              error: snapshot.error,
              onOpenTrip: _openTrip,
              onOpenCircle: () => setState(() => _selectedIndex = 3),
              onCreate: _showCreateMenu,
            ),
            1 => _buildAdventuresPage(context),
            3 => _CirclePage(repository: _circleRepository),
            4 => _ProfilePage(
              repository: _profileRepository,
              pushNotificationService: _pushNotificationService,
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

enum _CreateAction { adventure, entry, photo, snippet }

class CreateMenuSheet extends StatelessWidget {
  const CreateMenuSheet({
    super.key,
    required this.canAddContent,
    required this.onCreateAdventure,
    required this.onCreateEntry,
    required this.onAddPhoto,
    required this.onCreateSnippet,
  });

  final bool canAddContent;
  final VoidCallback onCreateAdventure;
  final VoidCallback onCreateEntry;
  final VoidCallback onAddPhoto;
  final VoidCallback onCreateSnippet;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Create', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.landscape_outlined),
              ),
              title: const Text('New adventure'),
              subtitle: const Text('Plan a trip and invite trusted people.'),
              onTap: onCreateAdventure,
            ),
            ListTile(
              enabled: canAddContent,
              leading: const CircleAvatar(
                child: Icon(Icons.edit_note_outlined),
              ),
              title: const Text('New journal entry'),
              subtitle: Text(
                canAddContent
                    ? 'Add a memory to one of your adventures.'
                    : 'Create an adventure first.',
              ),
              onTap: onCreateEntry,
            ),
            ListTile(
              enabled: canAddContent,
              leading: const CircleAvatar(
                child: Icon(Icons.add_photo_alternate_outlined),
              ),
              title: const Text('Add a photo'),
              subtitle: const Text('Start a photo memory in an adventure.'),
              onTap: onAddPhoto,
            ),
            ListTile(
              enabled: canAddContent,
              leading: const CircleAvatar(child: Icon(Icons.bolt_outlined)),
              title: const Text('Quick Snippet'),
              subtitle: const Text(
                'Capture a short moment now or save it locally.',
              ),
              onTap: onCreateSnippet,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSnippetDraft {
  const _QuickSnippetDraft({
    required this.trip,
    required this.text,
    required this.location,
    required this.saveLocally,
  });

  final Trip trip;
  final String text;
  final String location;
  final bool saveLocally;
}

class _QuickSnippetDialog extends StatefulWidget {
  const _QuickSnippetDialog({required this.trips});

  final List<Trip> trips;

  @override
  State<_QuickSnippetDialog> createState() => _QuickSnippetDialogState();
}

class _QuickSnippetDialogState extends State<_QuickSnippetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  final _locationController = TextEditingController();
  late String _tripId = widget.trips.first.id;

  @override
  void dispose() {
    _textController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _submit({required bool saveLocally}) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final trip = widget.trips.firstWhere((item) => item.id == _tripId);
    Navigator.of(context).pop(
      _QuickSnippetDraft(
        trip: trip,
        text: _textController.text.trim(),
        location: _locationController.text.trim(),
        saveLocally: saveLocally,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Snippet'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _textController,
                  autofocus: true,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'What happened?',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Add a quick note first.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _locationController,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _tripId,
                  decoration: const InputDecoration(labelText: 'Adventure'),
                  items: [
                    for (final trip in widget.trips)
                      DropdownMenuItem(value: trip.id, child: Text(trip.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _tripId = value);
                  },
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
        OutlinedButton(
          onPressed: () => _submit(saveLocally: true),
          child: const Text('Save locally'),
        ),
        FilledButton(
          onPressed: () => _submit(saveLocally: false),
          child: const Text('Post'),
        ),
      ],
    );
  }
}

class _FeedPage extends StatefulWidget {
  const _FeedPage({
    super.key,
    required this.repository,
    required this.notificationRepository,
    required this.userId,
    required this.trips,
    required this.isLoading,
    required this.error,
    required this.onOpenTrip,
    required this.onOpenCircle,
    required this.onCreate,
  });

  final TripRepository repository;
  final NotificationRepository notificationRepository;
  final String userId;
  final List<Trip> trips;
  final bool isLoading;
  final Object? error;
  final ValueChanged<Trip> onOpenTrip;
  final VoidCallback onOpenCircle;
  final VoidCallback onCreate;

  @override
  State<_FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<_FeedPage> {
  final _textController = TextEditingController();
  final _locationController = TextEditingController();
  final _queue = QuickSnippetQueue();
  late Stream<List<AdventureActivity>> _activityStream;
  List<QueuedSnippet> _queued = const [];
  String? _selectedTripId;
  bool _isPosting = false;
  bool _isRetrying = false;

  List<Trip> get _editableTrips => widget.trips
      .where(
        (trip) => trip.accessRole == 'owner' || trip.accessRole == 'editor',
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _activityStream = widget.repository.watchActivityFeed(widget.trips);
    _selectedTripId = _editableTrips.firstOrNull?.id;
    _loadQueue();
  }

  @override
  void didUpdateWidget(covariant _FeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAccess = oldWidget.trips
        .map((trip) => '${trip.id}:${trip.accessRole}')
        .join('|');
    final newAccess = widget.trips
        .map((trip) => '${trip.id}:${trip.accessRole}')
        .join('|');
    if (oldAccess != newAccess) {
      _activityStream = widget.repository.watchActivityFeed(widget.trips);
      if (!_editableTrips.any((trip) => trip.id == _selectedTripId)) {
        _selectedTripId = _editableTrips.firstOrNull?.id;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final queued = await _queue.load(widget.userId);
    if (mounted) {
      setState(() => _queued = queued);
    }
  }

  QueuedSnippet? _draftSnippet() {
    final text = _textController.text.trim();
    final location = _locationController.text.trim();
    final trip = _editableTrips
        .where((item) => item.id == _selectedTripId)
        .firstOrNull;
    if (trip == null) {
      _showMessage('Choose an adventure you can edit.');
      return null;
    }
    if (text.isEmpty) {
      _showMessage('Add a quick note first.');
      return null;
    }
    if (text.length > 1000 || location.length > 160) {
      _showMessage(
        'Keep the note under 1,000 characters and location under 160.',
      );
      return null;
    }
    return QueuedSnippet.create(
      tripId: trip.id,
      tripName: trip.name,
      text: text,
      location: location,
    );
  }

  Future<void> _saveLocally() async {
    final snippet = _draftSnippet();
    if (snippet == null) return;
    final queued = await _queue.enqueue(widget.userId, snippet);
    if (!mounted) return;
    setState(() => _queued = queued);
    _clearComposer();
    _showMessage('Saved locally. It is waiting to be posted.');
  }

  Future<void> _postSnippet() async {
    final snippet = _draftSnippet();
    if (snippet == null) return;
    setState(() => _isPosting = true);
    try {
      await _upload(snippet).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _clearComposer();
      _showMessage('Quick snippet posted.');
    } catch (_) {
      final queued = await _queue.enqueue(widget.userId, snippet);
      if (!mounted) return;
      setState(() => _queued = queued);
      _clearComposer();
      _showMessage('Could not post now, so it was saved locally for retry.');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _upload(QueuedSnippet snippet) {
    return widget.repository.createSnippet(
      tripId: snippet.tripId,
      snippetId: snippet.id,
      authorId: widget.userId,
      text: snippet.text,
      location: snippet.location,
      capturedAt: snippet.capturedAt,
    );
  }

  Future<void> _retryQueued() async {
    if (_queued.isEmpty) return;
    setState(() => _isRetrying = true);
    var posted = 0;
    var remaining = _queued;
    for (final snippet in List<QueuedSnippet>.from(_queued).reversed) {
      try {
        await _upload(snippet).timeout(const Duration(seconds: 10));
        remaining = await _queue.remove(widget.userId, snippet.id);
        posted++;
      } catch (_) {
        // Keep failed items in the durable queue for the next retry.
      }
    }
    if (!mounted) return;
    setState(() {
      _queued = remaining;
      _isRetrying = false;
    });
    _showMessage(
      posted == 0
          ? 'Nothing posted yet. Your saved snippets are still safe locally.'
          : '$posted saved ${posted == 1 ? 'snippet' : 'snippets'} posted.',
    );
  }

  Future<void> _discardQueued(String snippetId) async {
    final queued = await _queue.remove(widget.userId, snippetId);
    if (mounted) setState(() => _queued = queued);
  }

  void _clearComposer() {
    _textController.clear();
    _locationController.clear();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showNotifications() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NotificationInbox(
        repository: widget.notificationRepository,
        userId: widget.userId,
        trips: widget.trips,
        onOpenTrip: widget.onOpenTrip,
        onOpenCircle: widget.onOpenCircle,
      ),
    );
  }

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
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: widget.notificationRepository.watchNotifications(
              widget.userId,
            ),
            builder: (context, snapshot) {
              final unread = (snapshot.data ?? const <AppNotification>[])
                  .where((item) => item.isUnread)
                  .length;
              return IconButton(
                tooltip: unread == 0
                    ? 'Notifications'
                    : '$unread unread notifications',
                onPressed: _showNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: Icon(
                    unread > 0
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: widget.isLoading
            ? const Center(child: CircularProgressIndicator())
            : widget.error != null && widget.trips.isEmpty
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
                  _buildComposer(context),
                  if (_queued.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildPendingQueue(context),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Adventure activity',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  if (widget.trips.isEmpty)
                    _FeedEmptyState(onCreate: widget.onCreate)
                  else
                    StreamBuilder<List<AdventureActivity>>(
                      stream: _activityStream,
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
                          return _FeedEmptyState(onCreate: widget.onCreate);
                        }
                        final visibleActivity = activity.take(100).toList();
                        final now = DateTime.now();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < visibleActivity.length;
                              index++
                            ) ...[
                              if (index == 0 ||
                                  activitySectionLabel(
                                        visibleActivity[index].occurredAt,
                                        now,
                                      ) !=
                                      activitySectionLabel(
                                        visibleActivity[index - 1].occurredAt,
                                        now,
                                      )) ...[
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: index == 0 ? 0 : 10,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    activitySectionLabel(
                                      visibleActivity[index].occurredAt,
                                      now,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                              _ActivityCard(
                                activity: visibleActivity[index],
                                now: now,
                                onTap: () => widget.onOpenTrip(
                                  visibleActivity[index].trip,
                                ),
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

  Widget _buildComposer(BuildContext context) {
    final enabled = _editableTrips.isNotEmpty && !_isPosting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Snippet',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Post a short moment now, or save it locally when your connection is unreliable.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              enabled: enabled,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationController,
              enabled: enabled,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'snippet-trip-$_selectedTripId-'
                '${_editableTrips.map((trip) => trip.id).join('|')}',
              ),
              initialValue: _selectedTripId,
              decoration: const InputDecoration(labelText: 'Adventure'),
              items: [
                for (final trip in _editableTrips)
                  DropdownMenuItem(value: trip.id, child: Text(trip.name)),
              ],
              onChanged: enabled
                  ? (value) => setState(() => _selectedTripId = value)
                  : null,
            ),
            if (_editableTrips.isEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Create an adventure or request editor access to post snippets.',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: enabled ? _postSnippet : null,
                  icon: _isPosting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Post Quick Snippet'),
                ),
                OutlinedButton.icon(
                  onPressed: enabled ? _saveLocally : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save locally'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingQueue(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Waiting to post (${_queued.length})',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isRetrying ? null : _retryQueued,
                  icon: _isRetrying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Retry all'),
                ),
              ],
            ),
            for (final snippet in _queued) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snippet.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          snippet.tripName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Discard saved snippet',
                    onPressed: _isRetrying
                        ? null
                        : () => _discardQueued(snippet.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.now,
    required this.onTap,
  });

  final AdventureActivity activity;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = activity.entry;
    final snippet = activity.snippet;
    final (icon, title, message, contextLabel) = switch (activity.type) {
      AdventureActivityType.journalEntry => (
        Icons.auto_stories_outlined,
        entry!.title,
        entry.body,
        activity.trip.name,
      ),
      AdventureActivityType.photoAdded => (
        Icons.photo_outlined,
        'Photo added',
        entry!.title,
        activity.trip.name,
      ),
      AdventureActivityType.quickSnippet => (
        Icons.bolt_outlined,
        'Quick snippet',
        snippet!.text,
        activity.trip.name,
      ),
      AdventureActivityType.commentAdded => (
        Icons.mode_comment_outlined,
        'New comment',
        activity.comment!.body,
        activity.trip.name,
      ),
      AdventureActivityType.memberJoined => (
        Icons.person_add_outlined,
        'Adventure shared',
        'A trusted person was added.',
        activity.trip.name,
      ),
      AdventureActivityType.adventureStarted => (
        Icons.flag_outlined,
        'Adventure started',
        activity.trip.description.isEmpty
            ? '${activity.trip.name} was created.'
            : activity.trip.description,
        activity.trip.name,
      ),
    };
    final localizations = MaterialLocalizations.of(context);
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final timeLabel = friendlyTimeLabel(
      occurredAt: activity.occurredAt,
      now: now,
      formatTime: (value) =>
          localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value)),
      formatDate: localizations.formatMediumDate,
      formatWeekday: (value) => weekdays[value.weekday - 1],
    );
    final exactTime =
        '${localizations.formatFullDate(activity.occurredAt.toLocal())}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(activity.occurredAt.toLocal()))}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (snippet != null && snippet.location.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 16),
                          const SizedBox(width: 4),
                          Expanded(child: Text(snippet.location)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      contextLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: exactTime,
                      child: Text(
                        timeLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

class _NotificationInbox extends StatelessWidget {
  const _NotificationInbox({
    required this.repository,
    required this.userId,
    required this.trips,
    required this.onOpenTrip,
    required this.onOpenCircle,
  });

  final NotificationRepository repository;
  final String userId;
  final List<Trip> trips;
  final ValueChanged<Trip> onOpenTrip;
  final VoidCallback onOpenCircle;

  IconData _iconFor(String type) => switch (type) {
    'circleRequest' => Icons.group_add_outlined,
    'adventureEntry' => Icons.auto_stories_outlined,
    'adventureComment' => Icons.mode_comment_outlined,
    'quickSnippet' => Icons.bolt_outlined,
    'adventureShared' => Icons.landscape_outlined,
    _ => Icons.notifications_outlined,
  };

  Future<void> _open(BuildContext context, AppNotification notification) async {
    if (notification.isUnread) {
      await repository.markRead(userId, notification.id);
    }
    if (notification.type == 'circleRequest' && context.mounted) {
      Navigator.of(context).pop();
      onOpenCircle();
      return;
    }
    final trip = trips
        .where((item) => item.id == notification.tripId)
        .firstOrNull;
    if (trip != null && context.mounted) {
      Navigator.of(context).pop();
      onOpenTrip(trip);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: StreamBuilder<List<AppNotification>>(
        stream: repository.watchNotifications(userId),
        builder: (context, snapshot) {
          final notifications = snapshot.data ?? const <AppNotification>[];
          final unread = notifications.where((item) => item.isUnread).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: unread == 0
                          ? null
                          : () => repository.markAllRead(userId, notifications),
                      child: const Text('Mark all read'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                    ? const _InlineMessage(
                        icon: Icons.cloud_off_outlined,
                        title: 'Notifications are unavailable',
                        message: 'Check your connection and try again.',
                      )
                    : notifications.isEmpty
                    ? const _InlineMessage(
                        icon: Icons.notifications_none_outlined,
                        title: 'You’re all caught up',
                        message: 'Circle requests and shared-adventure activity will appear here.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          final trip = trips
                              .where((item) => item.id == notification.tripId)
                              .firstOrNull;
                          return ListTile(
                            tileColor: notification.isUnread
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withValues(alpha: 0.35)
                                : null,
                            leading: CircleAvatar(
                              child: Icon(_iconFor(notification.type)),
                            ),
                            title: Text(
                              notification.title,
                              style: notification.isUnread
                                  ? const TextStyle(fontWeight: FontWeight.w800)
                                  : null,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notification.body),
                                if (trip != null)
                                  Text(
                                    trip.name,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                Text(
                                  MaterialLocalizations.of(context)
                                      .formatMediumDate(notification.createdAt),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: () => _open(context, notification),
                            trailing: IconButton(
                              tooltip: 'Dismiss notification',
                              onPressed: () =>
                                  repository.dismiss(userId, notification.id),
                              icon: const Icon(Icons.close),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
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

class _CirclePage extends StatefulWidget {
  const _CirclePage({required this.repository});

  final CircleRepository repository;

  @override
  State<_CirclePage> createState() => _CirclePageState();
}

class _CirclePageState extends State<_CirclePage> {
  final _trekIdController = TextEditingController();
  final _busyPeople = <String>{};
  CircleState? _state;
  String? _error;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trekIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final state = await widget.repository.getState();
      if (mounted) setState(() => _state = state);
    } on CircleServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Your Circle could not be loaded.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRequest() async {
    final trekId = _trekIdController.text.trim();
    if (trekId.isEmpty) {
      _showMessage('Enter a TrekIt ID.');
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.repository.sendRequest(trekId);
      _trekIdController.clear();
      await _load();
      if (mounted) _showMessage('Circle request sent.');
    } on CircleServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('The request could not be sent.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _runPersonAction(
    CirclePerson person,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busyPeople.add(person.userId));
    try {
      await action();
      await _load();
      if (mounted) _showMessage(successMessage);
    } on CircleServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('That action could not be completed.');
    } finally {
      if (mounted) setState(() => _busyPeople.remove(person.userId));
    }
  }

  Future<void> _confirmRemove(CirclePerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Circle?'),
        content: Text(
          '${person.displayName} will be removed from your Circle. Existing adventure access is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runPersonAction(
        person,
        () => widget.repository.remove(person.userId),
        '${person.displayName} was removed from your Circle.',
      );
    }
  }

  Future<void> _confirmBlock(CirclePerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this person?'),
        content: Text(
          '${person.displayName} will be removed from your Circle and cannot send you requests. Existing adventure access is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runPersonAction(
        person,
        () => widget.repository.block(person.userId),
        '${person.displayName} was blocked.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circle'),
        actions: [
          IconButton(
            tooltip: 'Refresh Circle',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state == null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Circle is unavailable',
        message: _error ?? 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    final state = _state!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Your trusted people',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Circle connections make people easier to find. Adventure access remains separate and private.',
          ),
          const SizedBox(height: 20),
          _buildIdentityCard(context, state.profile),
          const SizedBox(height: 16),
          _buildInviteCard(context),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Current Circle', state.circle.length),
          if (state.circle.isEmpty)
            const _CircleEmptyMessage('No one is in your Circle yet.')
          else
            for (final person in state.circle)
              _CirclePersonCard(
                person: person,
                busy: _busyPeople.contains(person.userId),
                primaryLabel: 'Remove',
                onPrimary: () => _confirmRemove(person),
                secondaryLabel: 'Block',
                onSecondary: () => _confirmBlock(person),
                destructiveSecondary: true,
              ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Incoming', state.incoming.length),
          if (state.incoming.isEmpty)
            const _CircleEmptyMessage('No incoming requests.')
          else
            for (final person in state.incoming)
              _CirclePersonCard(
                person: person,
                busy: _busyPeople.contains(person.userId),
                primaryLabel: 'Accept',
                onPrimary: () => _runPersonAction(
                  person,
                  () => widget.repository.accept(person.userId),
                  '${person.displayName} joined your Circle.',
                ),
                secondaryLabel: 'Decline',
                onSecondary: () => _runPersonAction(
                  person,
                  () => widget.repository.decline(person.userId),
                  'Request declined.',
                ),
              ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Outgoing / cooldown', state.outgoing.length),
          if (state.outgoing.isEmpty)
            const _CircleEmptyMessage('No outgoing requests.')
          else
            for (final person in state.outgoing)
              _CirclePersonCard(person: person, busy: false),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Blocked users', state.blocked.length),
          if (state.blocked.isEmpty)
            const _CircleEmptyMessage('No blocked users.')
          else
            for (final person in state.blocked)
              _CirclePersonCard(
                person: person,
                busy: _busyPeople.contains(person.userId),
                primaryLabel: 'Unblock',
                onPrimary: () => _runPersonAction(
                  person,
                  () => widget.repository.unblock(person.userId),
                  '${person.displayName} was unblocked.',
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(BuildContext context, CircleProfile profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person_outline)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(profile.trekId),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy TrekIt ID',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: profile.trekId));
                if (mounted) _showMessage('TrekIt ID copied.');
              },
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invite by TrekIt ID',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trekIdController,
              enabled: !_isSending,
              maxLength: 18,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'TREK-XXXXXXX',
                prefixIcon: Icon(Icons.person_add_alt_1_outlined),
              ),
              onSubmitted: (_) => _isSending ? null : _sendRequest(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isSending ? null : _sendRequest,
              icon: _isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CirclePersonCard extends StatelessWidget {
  const _CirclePersonCard({
    required this.person,
    required this.busy,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructiveSecondary = false,
  });

  final CirclePerson person;
  final bool busy;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool destructiveSecondary;

  @override
  Widget build(BuildContext context) {
    final retryAfter = person.retryAfter;
    final cooldown = person.status == 'cooldown' && retryAfter != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.person_outline)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(person.trekId),
                  if (person.status == 'pending') ...[
                    const SizedBox(height: 4),
                    const Text('Request pending'),
                  ],
                  if (cooldown) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Cooldown until ${MaterialLocalizations.of(context).formatMediumDate(retryAfter.toLocal())}',
                    ),
                  ],
                  if (primaryLabel != null || secondaryLabel != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (primaryLabel != null)
                          FilledButton.tonal(
                            onPressed: busy ? null : onPrimary,
                            child: Text(primaryLabel!),
                          ),
                        if (secondaryLabel != null)
                          OutlinedButton(
                            style: destructiveSecondary
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  )
                                : null,
                            onPressed: busy ? null : onSecondary,
                            child: Text(secondaryLabel!),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleEmptyMessage extends StatelessWidget {
  const _CircleEmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({
    required this.repository,
    required this.pushNotificationService,
    required this.isSigningOut,
    required this.isDeletingAccount,
    required this.onOpenSettings,
    required this.onSignOut,
    required this.onSendVerification,
    required this.onRefreshVerification,
    required this.isSendingVerification,
    required this.isRefreshingVerification,
  });

  final ProfileRepository repository;
  final PushNotificationService pushNotificationService;
  final bool isSigningOut;
  final bool isDeletingAccount;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;
  final VoidCallback onSendVerification;
  final VoidCallback onRefreshVerification;
  final bool isSendingVerification;
  final bool isRefreshingVerification;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  ProfileState? _profile;
  String? _error;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isUpdatingPush = false;
  bool _preferencesDirty = false;
  BrowserPushStatus? _pushStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPushStatus();
  }

  Future<void> _loadPushStatus() async {
    try {
      final status = await widget.pushNotificationService.getStatus();
      if (mounted) setState(() => _pushStatus = status);
    } catch (_) {
      if (mounted) setState(() => _pushStatus = BrowserPushStatus.unsupported);
    }
  }

  Future<void> _toggleBrowserPush() async {
    final status = _pushStatus;
    if (status == null) return;
    setState(() => _isUpdatingPush = true);
    try {
      final updated = status == BrowserPushStatus.enabled
          ? await widget.pushNotificationService.disable()
          : await widget.pushNotificationService.enable();
      if (!mounted) return;
      setState(() => _pushStatus = updated);
      _showMessage(
        updated == BrowserPushStatus.enabled
            ? 'Browser notifications enabled.'
            : updated == BrowserPushStatus.blocked
            ? 'Notifications are blocked in this browser. Allow them in your browser settings to continue.'
            : 'Browser notifications disabled.',
      );
    } on PushNotificationException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage('Browser notifications could not be updated.');
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPush = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.getState();
      if (mounted) {
        setState(() {
          _profile = profile;
          _preferencesDirty = false;
        });
      }
    } on ProfileServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Your profile could not be loaded.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editIdentity() async {
    final profile = _profile;
    if (profile == null) return;
    final draft = await showDialog<_ProfileDraft>(
      context: context,
      builder: (_) => _ProfileDialog(profile: profile),
    );
    if (draft == null || !mounted) return;
    await _save(
      profile.copyWith(displayName: draft.displayName, bio: draft.bio),
      'Profile updated.',
    );
  }

  Future<void> _savePreferences() async {
    final profile = _profile;
    if (profile == null) return;
    await _save(profile, 'Preferences saved.');
  }

  Future<void> _save(ProfileState profile, String successMessage) async {
    setState(() => _isSaving = true);
    try {
      final updated = await widget.repository.update(profile);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _preferencesDirty = false;
      });
      _showMessage(successMessage);
    } on ProfileServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Your changes could not be saved.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final data = await widget.repository.exportMyData();
      const encoder = JsonEncoder.withIndent('  ');
      final json = encoder.convert(data);
      final date = DateTime.now().toIso8601String().split('T').first;
      final downloaded = await downloadTextFile(
        filename: 'trekit-data-$date.json',
        contents: json,
        mimeType: 'application/json;charset=utf-8',
      );
      if (!downloaded) {
        await Clipboard.setData(ClipboardData(text: json));
      }
      if (mounted) {
        _showMessage(
          downloaded
              ? 'Your TrekIt data export was downloaded.'
              : 'Your TrekIt data export was copied to the clipboard.',
        );
      }
    } on ProfileServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Your data export could not be created.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showInformation(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profile == null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Profile is unavailable',
        message: _error ?? 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    final profile = _profile!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _buildIdentityCard(context, profile),
          if (!profile.emailVerified) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.isSendingVerification
                  ? null
                  : widget.onSendVerification,
              icon: const Icon(Icons.outgoing_mail),
              label: Text(
                widget.isSendingVerification
                    ? 'Sending…'
                    : 'Send verification email',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.isRefreshingVerification
                  ? null
                  : widget.onRefreshVerification,
              icon: const Icon(Icons.refresh),
              label: Text(
                widget.isRefreshingVerification
                    ? 'Checking…'
                    : 'Check verification',
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildNotificationsCard(context, profile),
          const SizedBox(height: 16),
          _buildPrivacyCard(context, profile),
          const SizedBox(height: 16),
          _buildDataAndSupportCard(context),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.isDeletingAccount ? null : widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Account settings'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.isSigningOut ? null : widget.onSignOut,
            icon: const Icon(Icons.logout),
            label: Text(widget.isSigningOut ? 'Signing out…' : 'Sign out'),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(BuildContext context, ProfileState profile) {
    return Card(
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
              profile.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (profile.bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(profile.bio, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            Text(profile.email, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                profile.emailVerified
                    ? Icons.verified_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              label: Text(
                profile.emailVerified ? 'Email verified' : 'Email not verified',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _editIdentity,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard(BuildContext context, ProfileState profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Notification preferences',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'These choices control the private notification inbox available from the Feed bell.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Circle requests'),
              value: profile.notifyCircleRequests,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() {
                      _profile = profile.copyWith(notifyCircleRequests: value);
                      _preferencesDirty = true;
                    }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Adventure activity'),
              value: profile.notifyAdventureActivity,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() {
                      _profile = profile.copyWith(
                        notifyAdventureActivity: value,
                      );
                      _preferencesDirty = true;
                    }),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Browser notifications'),
              subtitle: Text(switch (_pushStatus) {
                BrowserPushStatus.enabled =>
                  'On for this browser. Alerts follow the choices above.',
                BrowserPushStatus.blocked => 'Blocked by this browser. Allow notifications in its site settings.',
                BrowserPushStatus.notEnabled => 'Off for this browser. TrekIt will ask permission only when you enable it.',
                BrowserPushStatus.unsupported => 'Not available in this browser. Your in-app inbox still works.',
                null => 'Checking this browser…',
              }),
              trailing: _isUpdatingPush
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: _pushStatus == BrowserPushStatus.enabled,
                      onChanged:
                          _pushStatus == null ||
                              _pushStatus == BrowserPushStatus.unsupported ||
                              _pushStatus == BrowserPushStatus.blocked
                          ? null
                          : (_) => _toggleBrowserPush(),
                    ),
            ),
            FilledButton(
              onPressed: !_preferencesDirty || _isSaving
                  ? null
                  : _savePreferences,
              child: Text(_isSaving ? 'Saving…' : 'Save preferences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyCard(BuildContext context, ProfileState profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Privacy and sharing',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow new Circle requests'),
              subtitle: const Text(
                'Turning this off prevents new requests without affecting your current Circle.',
              ),
              value: profile.allowCircleRequests,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() {
                      _profile = profile.copyWith(allowCircleRequests: value);
                      _preferencesDirty = true;
                    }),
            ),
            const Divider(),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline),
              title: Text('Private by default'),
              subtitle: Text(
                'Your profile is not publicly searchable. Adventures are visible only to their authorized members.',
              ),
            ),
            FilledButton(
              onPressed: !_preferencesDirty || _isSaving
                  ? null
                  : _savePreferences,
              child: Text(_isSaving ? 'Saving…' : 'Save privacy preference'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataAndSupportCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Download my data'),
            subtitle: const Text('Export your TrekIt account data as JSON.'),
            trailing: _isExporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isExporting ? null : _exportData,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help and support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showInformation(
              'Help and support',
              'Use Adventures to create private trips and journal entries. Use Circle to connect with trusted people by TrekIt ID. Circle connections do not automatically grant adventure access.\n\nIf something does not save, check your connection and retry. Quick Snippets saved locally remain in the waiting queue until posted or discarded.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy summary'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showInformation(
              'Privacy summary',
              'TrekIt is private by default. There is no public feed or public profile directory. Adventure owners control membership, Circle relationships remain separate from adventure access, and blocked users cannot send new Circle requests. You can export or delete your account data from Profile.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of use'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showInformation(
              'Terms of use',
              'TrekIt is currently an early-access product. Only upload content you have the right to share, respect the privacy of other adventure members, and do not use the service for unlawful or abusive activity. These in-app terms are a product summary and should be replaced with reviewed legal terms before broad release.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDraft {
  const _ProfileDraft({required this.displayName, required this.bio});

  final String displayName;
  final String bio;
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile});

  final ProfileState profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _nameController = TextEditingController(
    text: widget.profile.displayName,
  );
  late final _bioController = TextEditingController(text: widget.profile.bio);

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _nameController.text.trim().length <= 80 &&
      _bioController.text.trim().length <= 240;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              maxLength: 240,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'About you (optional)',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isValid
              ? () => Navigator.pop(
                  context,
                  _ProfileDraft(
                    displayName: _nameController.text.trim(),
                    bio: _bioController.text.trim(),
                  ),
                )
              : null,
          child: const Text('Save'),
        ),
      ],
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

class _TripCover extends StatefulWidget {
  const _TripCover({required this.repository, required this.trip});

  final TripRepository repository;
  final Trip trip;

  @override
  State<_TripCover> createState() => _TripCoverState();
}

class _TripCoverState extends State<_TripCover> {
  late Future<Uint8List> _cover = widget.repository.getTripCover(widget.trip);

  @override
  void didUpdateWidget(covariant _TripCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.coverImagePath != widget.trip.coverImagePath ||
        oldWidget.trip.updatedAt != widget.trip.updatedAt) {
      _cover = widget.repository.getTripCover(widget.trip);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _cover,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 1200,
          );
        }
        if (snapshot.hasError) {
          return Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: 48),
          );
        }
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        );
      },
    );
  }
}

Color _statusColor(BuildContext context, TripStatus status) {
  return switch (status) {
    TripStatus.draft => const Color(0xFF8A6823),
    TripStatus.live => const Color(0xFF137A62),
    TripStatus.completed => Theme.of(context).colorScheme.primary,
  };
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
              'This permanently removes your account, profile settings, Circle relationships, adventures you own, journal entries and snippets you wrote, uploaded photos, and access to shared adventures. This cannot be undone.',
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
    required this.status,
    required this.removeCover,
    this.startDate,
    this.endDate,
    this.coverImageBytes,
    this.coverContentType,
  });

  final String name;
  final String description;
  final String location;
  final TripStatus status;
  final bool removeCover;
  final DateTime? startDate;
  final DateTime? endDate;
  final Uint8List? coverImageBytes;
  final String? coverContentType;
}

enum _TripAction { edit, delete }

class _TripDialog extends StatefulWidget {
  const _TripDialog({
    required this.repository,
    required this.userId,
    this.trip,
  });

  final TripRepository repository;
  final String userId;
  final Trip? trip;

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  final _formKey = GlobalKey<FormState>();
  final _draftStore = LocalDraftStore();
  late final _nameController = TextEditingController(text: widget.trip?.name);
  late final _descriptionController = TextEditingController(
    text: widget.trip?.description,
  );
  late final _locationController = TextEditingController(
    text: widget.trip?.location,
  );
  late DateTime? _startDate = widget.trip?.startDate;
  late DateTime? _endDate = widget.trip?.endDate;
  late TripStatus _status = widget.trip?.status ?? TripStatus.draft;
  final _imagePicker = ImagePicker();
  Uint8List? _coverImageBytes;
  String? _coverContentType;
  bool _removeCover = false;
  bool _isPickingCover = false;
  Timer? _draftTimer;
  bool _isLoadingDraft = false;
  bool _draftRestored = false;
  bool _draftSaved = false;
  bool _photoNeedsReselection = false;
  bool _draftDiscarded = false;

  bool get _usesLocalDraft => widget.trip == null;

  @override
  void initState() {
    super.initState();
    if (_usesLocalDraft) {
      _isLoadingDraft = true;
      _restoreDraft();
    }
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftStore.loadAdventure(widget.userId);
    if (!mounted) return;
    if (draft != null && !draft.isEmpty) {
      _nameController.text = draft.name;
      _descriptionController.text = draft.description;
      _locationController.text = draft.location;
      _startDate = draft.startDate;
      _endDate = draft.endDate;
      _status =
          TripStatus.values
              .where((status) => status.name == draft.status)
              .firstOrNull ??
          TripStatus.draft;
      _draftRestored = true;
      _draftSaved = true;
      _photoNeedsReselection = draft.hadPhoto;
    }
    _nameController.addListener(_scheduleDraftSave);
    _descriptionController.addListener(_scheduleDraftSave);
    _locationController.addListener(_scheduleDraftSave);
    setState(() => _isLoadingDraft = false);
  }

  void _scheduleDraftSave() {
    if (!_usesLocalDraft || _draftDiscarded || _isLoadingDraft) return;
    _draftTimer?.cancel();
    if (mounted) setState(() => _draftSaved = false);
    _draftTimer = Timer(const Duration(milliseconds: 500), _persistDraft);
  }

  Future<void> _persistDraft({bool updateState = true}) async {
    if (!_usesLocalDraft || _draftDiscarded) return;
    final draft = AdventureFormDraft(
      name: _nameController.text,
      description: _descriptionController.text,
      location: _locationController.text,
      status: _status.name,
      startDate: _startDate,
      endDate: _endDate,
      hadPhoto: _coverImageBytes != null || _photoNeedsReselection,
      updatedAt: DateTime.now(),
    );
    if (draft.isEmpty) {
      await _draftStore.clearAdventure(widget.userId);
    } else {
      await _draftStore.saveAdventure(widget.userId, draft);
    }
    if (updateState && mounted) setState(() => _draftSaved = !draft.isEmpty);
  }

  Future<void> _discardDraft() async {
    _draftTimer?.cancel();
    _draftDiscarded = true;
    await _draftStore.clearAdventure(widget.userId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickCover() async {
    setState(() => _isPickingCover = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (image == null) {
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > TripRepository.maxImageBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose a photo smaller than 25 MB.')),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _coverImageBytes = bytes;
          _coverContentType = _contentTypeFor(image.name, image.mimeType);
          _removeCover = false;
          _photoNeedsReselection = false;
        });
        _scheduleDraftSave();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The photo picker could not open. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingCover = false);
      }
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_usesLocalDraft && !_draftDiscarded) {
      unawaited(_persistDraft(updateState: false));
    }
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
      _scheduleDraftSave();
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
      _scheduleDraftSave();
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _draftTimer?.cancel();
    await _persistDraft();
    if (!mounted) return;
    Navigator.of(context).pop(
      _TripDraft(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        status: _status,
        removeCover: _removeCover,
        startDate: _startDate,
        endDate: _endDate,
        coverImageBytes: _coverImageBytes,
        coverContentType: _coverContentType,
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
                if (_isLoadingDraft) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ] else if (_usesLocalDraft &&
                    (_draftRestored || _draftSaved)) ...[
                  _DraftNotice(
                    restored: _draftRestored,
                    saved: _draftSaved,
                    photoNeedsReselection: _photoNeedsReselection,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  autofocus: !_draftRestored,
                  enabled: !_isLoadingDraft,
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
                  enabled: !_isLoadingDraft,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  enabled: !_isLoadingDraft,
                  maxLength: 160,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TripStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Adventure status',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: [
                    for (final status in TripStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  onChanged: (status) {
                    if (status != null) {
                      setState(() => _status = status);
                      _scheduleDraftSave();
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (_coverImageBytes case final bytes?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      bytes,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else if (widget.trip?.coverImagePath != null &&
                    !_removeCover) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 180,
                      child: _TripCover(
                        repository: widget.repository,
                        trip: widget.trip!,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isPickingCover ? null : _pickCover,
                      icon: _isPickingCover
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _coverImageBytes != null ||
                                (widget.trip?.coverImagePath != null &&
                                    !_removeCover)
                            ? 'Change cover'
                            : 'Add cover',
                      ),
                    ),
                    if (_coverImageBytes != null ||
                        (widget.trip?.coverImagePath != null && !_removeCover))
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _coverImageBytes = null;
                            _coverContentType = null;
                            _removeCover = widget.trip?.coverImagePath != null;
                            _photoNeedsReselection = false;
                          });
                          _scheduleDraftSave();
                        },
                        child: const Text('Remove'),
                      ),
                  ],
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
                        onPressed: () {
                          setState(() => _startDate = null);
                          _scheduleDraftSave();
                        },
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
                        onPressed: () {
                          setState(() => _endDate = null);
                          _scheduleDraftSave();
                        },
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
        if (_usesLocalDraft)
          TextButton(
            onPressed: _isLoadingDraft ? null : _discardDraft,
            child: const Text('Discard draft'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoadingDraft ? null : _submit,
          child: Text(widget.trip == null ? 'Create' : 'Save changes'),
        ),
      ],
    );
  }
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice({
    required this.restored,
    required this.saved,
    required this.photoNeedsReselection,
  });

  final bool restored;
  final bool saved;
  final bool photoNeedsReselection;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(saved ? Icons.cloud_done_outlined : Icons.sync_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saved
                      ? restored
                            ? 'Recovered draft saved locally'
                            : 'Draft saved locally'
                      : 'Saving draft locally…',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (photoNeedsReselection) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'For privacy and browser compatibility, please reselect the photo.',
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

String _contentTypeFor(String fileName, String? detectedType) {
  if (detectedType != null && detectedType.startsWith('image/')) {
    return detectedType;
  }
  final lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerName.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lowerName.endsWith('.heic') || lowerName.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
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
