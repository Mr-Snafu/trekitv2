import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/trip_repository.dart';
import '../domain/journal_entry.dart';
import '../domain/trip.dart';
import '../domain/trip_member.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.userId,
    required this.repository,
  });

  final Trip trip;
  final String userId;
  final TripRepository repository;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  bool _isCreatingEntry = false;
  double? _uploadProgress;
  final Set<String> _busyEntryIds = <String>{};

  bool get _isOwner => widget.trip.ownerId == widget.userId;
  bool get _canCreateEntry => _isOwner || widget.trip.accessRole == 'editor';

  Future<void> _manageSharing() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ManageAccessDialog(trip: widget.trip, repository: widget.repository),
    );
  }

  Future<void> _createEntry() async {
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (_) => const _CreateEntryDialog(),
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
  const _CreateEntryDialog();

  @override
  State<_CreateEntryDialog> createState() => _CreateEntryDialogState();
}

class _CreateEntryDialogState extends State<_CreateEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageContentType;
  bool _isPickingImage = false;
  DateTime _memoryDate = DateUtils.dateOnly(DateTime.now());

  Future<void> _pickMemoryDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'When did this happen?',
    );
    if (selectedDate != null && mounted) {
      setState(() => _memoryDate = DateUtils.dateOnly(selectedDate));
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
        });
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
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
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
                      onPressed: _isPickingImage ? null : _pickImage,
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
                        onPressed: () => setState(() {
                          _imageBytes = null;
                          _imageContentType = null;
                        }),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save entry')),
      ],
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
  late DateTime _memoryDate = DateUtils.dateOnly(widget.entry.timelineDate);

  Future<void> _pickMemoryDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
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
