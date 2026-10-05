import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/drafts/local_draft_store.dart';
import '../data/trip_repository.dart';
import '../domain/adventure_comment.dart';
import '../domain/journal_entry.dart';
import '../domain/trip.dart';
import '../domain/trip_member.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.userId,
    required this.repository,
    this.startWithNewEntry = false,
    this.startEntryWithPhoto = false,
  });

  final Trip trip;
  final String userId;
  final TripRepository repository;
  final bool startWithNewEntry;
  final bool startEntryWithPhoto;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  bool _isCreatingEntry = false;
  double? _uploadProgress;
  final Set<String> _busyEntryIds = <String>{};

  bool get _isOwner => widget.trip.ownerId == widget.userId;
  bool get _canCreateEntry => _isOwner || widget.trip.accessRole == 'editor';

  @override
  void initState() {
    super.initState();
    if (widget.startWithNewEntry && _canCreateEntry) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _createEntry(pickPhotoFirst: widget.startEntryWithPhoto),
      );
    }
  }

  Future<void> _manageSharing() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ManageAccessDialog(trip: widget.trip, repository: widget.repository),
    );
  }

  Future<void> _createEntry({bool pickPhotoFirst = false}) async {
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (_) => _CreateEntryDialog(
        userId: widget.userId,
        tripId: widget.trip.id,
        pickPhotoOnOpen: pickPhotoFirst,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _isCreatingEntry = true);
    try {
      await widget.repository.createEntry(
        tripId: widget.trip.id,
        authorId: widget.userId,
        title: draft.title,
        body: draft.body,
        memoryDate: draft.memoryDate,
        imageBytes: draft.imageBytes,
        imageContentType: draft.imageContentType,
        onUploadProgress: (progress) {
          if (mounted) {
            setState(() => _uploadProgress = progress);
          }
        },
      );
      await LocalDraftStore().clearEntry(widget.userId, widget.trip.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Journal entry saved.')));
      }
    } on FirebaseException catch (error) {
      debugPrint('Entry save failed (${error.code}): ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'permission-denied'
                  ? 'The entry was blocked by its privacy rules. Please try again.'
                  : 'The entry could not be saved. Please try again.',
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Entry save failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The entry could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingEntry = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _editEntry(JournalEntry entry) async {
    final draft = await showDialog<_EntryTextDraft>(
      context: context,
      builder: (_) => _EditEntryDialog(entry: entry),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _busyEntryIds.add(entry.id));
    try {
      await widget.repository.updateEntry(
        tripId: widget.trip.id,
        entryId: entry.id,
        title: draft.title,
        body: draft.body,
        memoryDate: draft.memoryDate,
      );
      if (mounted) {
        _showMessage('Journal entry updated.');
      }
    } on FirebaseException catch (error) {
      debugPrint('Entry update failed (${error.code}): ${error.message}');
      if (mounted) {
        _showMessage('The entry could not be updated. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyEntryIds.remove(entry.id));
      }
    }
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'The journal entry and its photo will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busyEntryIds.add(entry.id));
    try {
      await widget.repository.deleteEntry(tripId: widget.trip.id, entry: entry);
      if (mounted) {
        _showMessage('Journal entry deleted.');
      }
    } on FirebaseException catch (error) {
      debugPrint('Entry delete failed (${error.code}): ${error.message}');
      if (mounted) {
        _showMessage('The entry could not be deleted. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyEntryIds.remove(entry.id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trip.name),
        actions: [
          if (_isOwner)
            IconButton(
              onPressed: _manageSharing,
              tooltip: 'Manage access',
              icon: const Icon(Icons.group_add_outlined),
            ),
        ],
      ),
      floatingActionButton: _canCreateEntry
          ? FloatingActionButton.extended(
              onPressed: _isCreatingEntry ? null : _createEntry,
              icon: _isCreatingEntry
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_note),
              label: const Text('New entry'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (_uploadProgress case final progress?)
              LinearProgressIndicator(value: progress),
            if (widget.trip.description.isNotEmpty ||
                widget.trip.location.isNotEmpty ||
                widget.trip.startDate != null ||
                widget.trip.endDate != null)
              _TripOverview(trip: widget.trip),
            Expanded(
              child: StreamBuilder<List<JournalEntry>>(
                stream: widget.repository.watchEntries(widget.trip.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Journal entries are unavailable. Check your connection and try again.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final entries = snapshot.data ?? const <JournalEntry>[];
                  if (entries.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_stories_outlined, size: 64),
                            const SizedBox(height: 20),
                            Text(
                              'Capture the first moment',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Add a private journal entry for this adventure.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entry.imagePath case final imagePath?) ...[
                                _EntryPhoto(
                                  repository: widget.repository,
                                  tripId: widget.trip.id,
                                  entryId: entry.id,
                                  imagePath: imagePath,
                                  title: entry.title,
                                  memoryDate: entry.timelineDate,
                                ),
                                const SizedBox(height: 16),
                              ],
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                  ),
                                  if (_busyEntryIds.contains(entry.id))
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  else if (_isOwner ||
                                      entry.authorId == widget.userId)
                                    PopupMenuButton<_EntryAction>(
                                      tooltip: 'Entry options',
                                      onSelected: (action) {
                                        switch (action) {
                                          case _EntryAction.edit:
                                            _editEntry(entry);
                                          case _EntryAction.delete:
                                            _deleteEntry(entry);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: _EntryAction.edit,
                                          child: ListTile(
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text('Edit'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: _EntryAction.delete,
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('Delete'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(entry.body),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(entry.timelineDate),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Divider(),
                              _EntryComments(
                                repository: widget.repository,
                                tripId: widget.trip.id,
                                entryId: entry.id,
                                currentUserId: widget.userId,
                                isTripOwner: _isOwner,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _EntryAction { edit, delete }

enum _CommentAction { edit, delete }

class _EntryComments extends StatefulWidget {
  const _EntryComments({
    required this.repository,
    required this.tripId,
    required this.entryId,
    required this.currentUserId,
    required this.isTripOwner,
  });

  final TripRepository repository;
  final String tripId;
  final String entryId;
  final String currentUserId;
  final bool isTripOwner;

  @override
  State<_EntryComments> createState() => _EntryCommentsState();
}

class _EntryCommentsState extends State<_EntryComments> {
  final _controller = TextEditingController();
  final Set<String> _busyCommentIds = <String>{};
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendComment() async {
    final body = _controller.text.trim();
    if (body.isEmpty || body.length > 2000 || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.repository.createComment(
        tripId: widget.tripId,
        entryId: widget.entryId,
        authorId: widget.currentUserId,
        body: body,
      );
      _controller.clear();
    } catch (error, stackTrace) {
      debugPrint('Comment save failed: $error\n$stackTrace');
      if (mounted) {
        _showMessage('The comment could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _editComment(AdventureComment comment) async {
    final updatedBody = await showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(initialBody: comment.body),
    );
    if (updatedBody == null || !mounted) return;
    setState(() => _busyCommentIds.add(comment.id));
    try {
      await widget.repository.updateComment(
        tripId: widget.tripId,
        commentId: comment.id,
        body: updatedBody,
      );
    } catch (error, stackTrace) {
      debugPrint('Comment update failed: $error\n$stackTrace');
      if (mounted) _showMessage('The comment could not be updated.');
    } finally {
      if (mounted) setState(() => _busyCommentIds.remove(comment.id));
    }
  }

  Future<void> _deleteComment(AdventureComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyCommentIds.add(comment.id));
    try {
      await widget.repository.deleteComment(
        tripId: widget.tripId,
        commentId: comment.id,
      );
    } catch (error, stackTrace) {
      debugPrint('Comment delete failed: $error\n$stackTrace');
      if (mounted) _showMessage('The comment could not be deleted.');
    } finally {
      if (mounted) setState(() => _busyCommentIds.remove(comment.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdventureComment>>(
      stream: widget.repository.watchComments(
        tripId: widget.tripId,
        entryId: widget.entryId,
      ),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? const <AdventureComment>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comments.isEmpty
                  ? 'Discussion'
                  : 'Discussion (${comments.length})',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Comments are unavailable right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            for (final comment in comments) ...[
              const SizedBox(height: 12),
              _CommentTile(
                comment: comment,
                isCurrentUser: comment.authorId == widget.currentUserId,
                canDelete:
                    widget.isTripOwner ||
                    comment.authorId == widget.currentUserId,
                isBusy: _busyCommentIds.contains(comment.id),
                onEdit: () => _editComment(comment),
                onDelete: () => _deleteComment(comment),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Add a private comment',
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Post comment',
                  onPressed: _isSending ? null : _sendComment,
                  icon: _isSending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isCurrentUser,
    required this.canDelete,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
  });

  final AdventureComment comment;
  final bool isCurrentUser;
  final bool canDelete;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCurrentUser ? 'You' : 'Adventure member',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(comment.body),
                  const SizedBox(height: 5),
                  Text(
                    MaterialLocalizations.of(context)
                        .formatMediumDate(comment.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isBusy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (isCurrentUser || canDelete)
              PopupMenuButton<_CommentAction>(
                tooltip: 'Comment options',
                onSelected: (action) {
                  switch (action) {
                    case _CommentAction.edit:
                      onEdit();
                    case _CommentAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  if (isCurrentUser)
                    const PopupMenuItem(
                      value: _CommentAction.edit,
                      child: Text('Edit'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _CommentAction.delete,
                      child: Text('Delete'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({required this.initialBody});

  final String initialBody;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialBody,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final body = _controller.text.trim();
    if (body.isNotEmpty && body.length <= 2000) {
      Navigator.of(context).pop(body);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit comment'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        decoration: const InputDecoration(labelText: 'Comment'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _TripOverview extends StatelessWidget {
  const _TripOverview({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final startDate = trip.startDate;
    final endDate = trip.endDate;
    final dateLabel = startDate != null && endDate != null
        ? '${localizations.formatMediumDate(startDate)} – ${localizations.formatMediumDate(endDate)}'
        : startDate != null || endDate != null
        ? localizations.formatMediumDate(startDate ?? endDate!)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (trip.location.isNotEmpty)
                _OverviewRow(icon: Icons.place_outlined, text: trip.location),
              if (trip.location.isNotEmpty && dateLabel != null)
                const SizedBox(height: 8),
              if (dateLabel != null)
                _OverviewRow(
                  icon: Icons.calendar_today_outlined,
                  text: dateLabel,
                ),
              if ((trip.location.isNotEmpty || dateLabel != null) &&
                  trip.description.isNotEmpty)
                const SizedBox(height: 12),
              if (trip.description.isNotEmpty) Text(trip.description),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}

class _EntryTextDraft {
  const _EntryTextDraft({
    required this.title,
    required this.body,
    required this.memoryDate,
  });

  final String title;
  final String body;
  final DateTime memoryDate;
}

class _EntryDraft {
  const _EntryDraft({
    required this.title,
    required this.body,
    required this.memoryDate,
    this.imageBytes,
    this.imageContentType,
  });

  final String title;
  final String body;
  final DateTime memoryDate;
  final Uint8List? imageBytes;
  final String? imageContentType;
}

class _CreateEntryDialog extends StatefulWidget {
  const _CreateEntryDialog({
    required this.userId,
    required this.tripId,
    this.pickPhotoOnOpen = false,
  });

  final String userId;
  final String tripId;
  final bool pickPhotoOnOpen;

  @override
  State<_CreateEntryDialog> createState() => _CreateEntryDialogState();
}

class _CreateEntryDialogState extends State<_CreateEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _draftStore = LocalDraftStore();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageContentType;
  bool _isPickingImage = false;
  DateTime _memoryDate = DateUtils.dateOnly(DateTime.now());
  Timer? _draftTimer;
  bool _isLoadingDraft = true;
  bool _draftRestored = false;
  bool _draftSaved = false;
  bool _photoNeedsReselection = false;
  bool _draftDiscarded = false;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftStore.loadEntry(widget.userId, widget.tripId);
    if (!mounted) return;
    if (draft != null && !draft.isEmpty) {
      _titleController.text = draft.title;
      _bodyController.text = draft.body;
      _memoryDate = DateUtils.dateOnly(
        isFutureMemoryDate(draft.memoryDate)
            ? DateTime.now()
            : draft.memoryDate,
      );
      _draftRestored = true;
      _draftSaved = true;
      _photoNeedsReselection = draft.hadPhoto;
    }
    _titleController.addListener(_scheduleDraftSave);
    _bodyController.addListener(_scheduleDraftSave);
    setState(() => _isLoadingDraft = false);
    if (widget.pickPhotoOnOpen && !_photoNeedsReselection) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
    }
  }

  void _scheduleDraftSave() {
    if (_draftDiscarded || _isLoadingDraft) return;
    _draftTimer?.cancel();
    if (mounted) setState(() => _draftSaved = false);
    _draftTimer = Timer(const Duration(milliseconds: 500), _persistDraft);
  }

  Future<void> _persistDraft({bool updateState = true}) async {
    if (_draftDiscarded) return;
    final draft = JournalFormDraft(
      title: _titleController.text,
      body: _bodyController.text,
      memoryDate: _memoryDate,
      hadPhoto: _imageBytes != null || _photoNeedsReselection,
      updatedAt: DateTime.now(),
    );
    if (draft.isEmpty) {
      await _draftStore.clearEntry(widget.userId, widget.tripId);
    } else {
      await _draftStore.saveEntry(widget.userId, widget.tripId, draft);
    }
    if (updateState && mounted) setState(() => _draftSaved = !draft.isEmpty);
  }

  Future<void> _discardDraft() async {
    _draftTimer?.cancel();
    _draftDiscarded = true;
    await _draftStore.clearEntry(widget.userId, widget.tripId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickMemoryDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      helpText: 'When did this happen?',
    );
    if (selectedDate != null && mounted) {
      setState(() => _memoryDate = DateUtils.dateOnly(selectedDate));
      _scheduleDraftSave();
    }
  }

  Future<void> _pickImage() async {
    setState(() => _isPickingImage = true);
    try {
      final image = await _picker.pickImage(
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
          _imageBytes = bytes;
          _imageContentType = image.mimeType ?? _contentTypeFor(image.name);
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
        setState(() => _isPickingImage = false);
      }
    }
  }

  String _contentTypeFor(String fileName) {
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

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_draftDiscarded) {
      unawaited(_persistDraft(updateState: false));
    }
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _draftTimer?.cancel();
    await _persistDraft();
    if (!mounted) return;
    Navigator.of(context).pop(
      _EntryDraft(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        memoryDate: _memoryDate,
        imageBytes: _imageBytes,
        imageContentType: _imageContentType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New journal entry'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingDraft) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ] else if (_draftRestored || _draftSaved) ...[
                  _EntryDraftNotice(
                    restored: _draftRestored,
                    saved: _draftSaved,
                    photoNeedsReselection: _photoNeedsReselection,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _titleController,
                  autofocus: !widget.pickPhotoOnOpen,
                  enabled: !_isLoadingDraft,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Enter a title.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyController,
                  enabled: !_isLoadingDraft,
                  maxLength: 10000,
                  minLines: 5,
                  maxLines: 9,
                  decoration: const InputDecoration(labelText: 'Your memory'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Write something about this moment.'
                      : null,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickMemoryDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      'Memory date: ${MaterialLocalizations.of(context).formatMediumDate(_memoryDate)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_imageBytes case final imageBytes?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      imageBytes,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isPickingImage || _isLoadingDraft
                          ? null
                          : _pickImage,
                      icon: _isPickingImage
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _imageBytes == null ? 'Add photo' : 'Change photo',
                      ),
                    ),
                    if (_imageBytes != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _imageBytes = null;
                            _imageContentType = null;
                            _photoNeedsReselection = false;
                          });
                          _scheduleDraftSave();
                        },
                        child: const Text('Remove'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
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
          child: const Text('Save entry'),
        ),
      ],
    );
  }
}

class _EntryDraftNotice extends StatelessWidget {
  const _EntryDraftNotice({
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
                    'Your writing was recovered. Please reselect the photo before saving.',
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

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry});

  final JournalEntry entry;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController = TextEditingController(
    text: widget.entry.title,
  );
  late final TextEditingController _bodyController = TextEditingController(
    text: widget.entry.body,
  );
  late DateTime _memoryDate = isFutureMemoryDate(widget.entry.timelineDate)
      ? DateUtils.dateOnly(DateTime.now())
      : DateUtils.dateOnly(widget.entry.timelineDate);

  Future<void> _pickMemoryDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      helpText: 'When did this happen?',
    );
    if (selectedDate != null && mounted) {
      setState(() => _memoryDate = DateUtils.dateOnly(selectedDate));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _EntryTextDraft(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        memoryDate: _memoryDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit journal entry'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Enter a title.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyController,
                  maxLength: 10000,
                  minLines: 5,
                  maxLines: 9,
                  decoration: const InputDecoration(labelText: 'Your memory'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Write something about this moment.'
                      : null,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickMemoryDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      'Memory date: ${MaterialLocalizations.of(context).formatMediumDate(_memoryDate)}',
                    ),
                  ),
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
        FilledButton(onPressed: _submit, child: const Text('Save changes')),
      ],
    );
  }
}

class _ManageAccessDialog extends StatefulWidget {
  const _ManageAccessDialog({required this.trip, required this.repository});

  final Trip trip;
  final TripRepository repository;

  @override
  State<_ManageAccessDialog> createState() => _ManageAccessDialogState();
}

class _ManageAccessDialogState extends State<_ManageAccessDialog> {
  final _emailController = TextEditingController();
  late Future<List<TripMember>> _members = _loadMembers();
  String _role = 'viewer';
  bool _isSharing = false;
  String? _error;

  Future<List<TripMember>> _loadMembers() {
    return widget.repository.listTripMembers(widget.trip.id);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _error = 'Enter the email for an existing TrekIt account.',
      );
      return;
    }

    setState(() {
      _isSharing = true;
      _error = null;
    });
    try {
      await widget.repository.shareTrip(
        tripId: widget.trip.id,
        email: email,
        role: _role,
      );
      if (mounted) {
        _emailController.clear();
        setState(() => _members = _loadMembers());
      }
    } on TripServiceException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  Future<void> _remove(TripMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove access?'),
        content: Text(
          '${member.email} will no longer be able to open this trip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.repository.removeTripMember(
        tripId: widget.trip.id,
        memberId: member.userId,
      );
      if (mounted) {
        setState(() => _members = _loadMembers());
      }
    } on TripServiceException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share this adventure'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add someone who already has a TrekIt account. Viewers can read the journal; editors can also add entries.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'TrekIt account email',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Access level'),
                items: const [
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                  DropdownMenuItem(value: 'editor', child: Text('Editor')),
                ],
                onChanged: _isSharing
                    ? null
                    : (value) => setState(() => _role = value ?? 'viewer'),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _isSharing ? null : _share,
                  icon: _isSharing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: const Text('Add person'),
                ),
              ),
              const Divider(height: 32),
              Text(
                'People with access',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<TripMember>>(
                future: _members,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('The access list could not be loaded.');
                  }
                  final members = snapshot.data ?? const <TripMember>[];
                  return Column(
                    children: members
                        .map((member) {
                          final isOwner = member.role == 'owner';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Icon(
                                isOwner
                                    ? Icons.star_outline
                                    : Icons.person_outline,
                              ),
                            ),
                            title: Text(member.email),
                            subtitle: Text(
                              isOwner
                                  ? 'Owner'
                                  : member.role == 'editor'
                                  ? 'Editor'
                                  : 'Viewer',
                            ),
                            trailing: isOwner
                                ? null
                                : IconButton(
                                    onPressed: () => _remove(member),
                                    tooltip: 'Remove access',
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                  ),
                          );
                        })
                        .toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _EntryPhoto extends StatefulWidget {
  const _EntryPhoto({
    required this.repository,
    required this.tripId,
    required this.entryId,
    required this.imagePath,
    required this.title,
    required this.memoryDate,
  });

  final TripRepository repository;
  final String tripId;
  final String entryId;
  final String imagePath;
  final String title;
  final DateTime memoryDate;

  @override
  State<_EntryPhoto> createState() => _EntryPhotoState();
}

class _EntryPhotoState extends State<_EntryPhoto> {
  late Future<Uint8List> _image = widget.repository.getEntryPhoto(
    tripId: widget.tripId,
    entryId: widget.entryId,
  );

  @override
  void didUpdateWidget(covariant _EntryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.entryId != widget.entryId ||
        oldWidget.tripId != widget.tripId) {
      _image = widget.repository.getEntryPhoto(
        tripId: widget.tripId,
        entryId: widget.entryId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'Photo load failed for ${widget.imagePath}: ${snapshot.error}',
          );
          return Container(
            height: 160,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, size: 40),
                SizedBox(height: 8),
                Text('Photo unavailable'),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final imageBytes = snapshot.data!;
        return Semantics(
          button: true,
          label: 'View photo full screen',
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _FullScreenPhoto(
                  imageBytes: imageBytes,
                  title: widget.title,
                  memoryDate: widget.memoryDate,
                ),
              ),
            ),
            child: Image.memory(
              imageBytes,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              cacheWidth: 1200,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({
    required this.imageBytes,
    required this.title,
    required this.memoryDate,
  });

  final Uint8List imageBytes;
  final String title;
  final DateTime memoryDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, overflow: TextOverflow.ellipsis),
            Text(
              MaterialLocalizations.of(context).formatMediumDate(memoryDate),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.75,
          maxScale: 5,
          child: Image.memory(imageBytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
