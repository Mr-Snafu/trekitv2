import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/trip_repository.dart';
import '../domain/journal_entry.dart';
import '../domain/trip.dart';

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
      appBar: AppBar(title: Text(widget.trip.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreatingEntry ? null : _createEntry,
        icon: _isCreatingEntry
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.edit_note),
        label: const Text('New entry'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_uploadProgress case final progress?)
              LinearProgressIndicator(value: progress),
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
                                  imagePath: imagePath,
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
                                  else
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
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatShortDate(entry.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
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

class _EntryTextDraft {
  const _EntryTextDraft({required this.title, required this.body});

  final String title;
  final String body;
}

class _EntryDraft {
  const _EntryDraft({
    required this.title,
    required this.body,
    this.imageBytes,
    this.imageContentType,
  });

  final String title;
  final String body;
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
                if (_imageBytes case final imageBytes?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      imageBytes,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
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

class _EntryPhoto extends StatefulWidget {
  const _EntryPhoto({required this.repository, required this.imagePath});

  final TripRepository repository;
  final String imagePath;

  @override
  State<_EntryPhoto> createState() => _EntryPhotoState();
}

class _EntryPhotoState extends State<_EntryPhoto> {
  late Future<Uint8List?> _image = widget.repository.loadEntryImage(
    widget.imagePath,
  );

  @override
  void didUpdateWidget(covariant _EntryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _image = widget.repository.loadEntryImage(widget.imagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            height: 160,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: 40),
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
                builder: (_) => _FullScreenPhoto(imageBytes: imageBytes),
              ),
            ),
            child: Image.memory(
              imageBytes,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
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
  const _FullScreenPhoto({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
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
