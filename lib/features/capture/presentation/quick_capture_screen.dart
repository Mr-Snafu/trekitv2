import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/trekit_app_bar.dart';
import '../domain/quick_capture_destination.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/trip.dart';

class QuickCaptureScreen extends StatefulWidget {
  const QuickCaptureScreen({
    super.key,
    required this.imageBytes,
    required this.imageContentType,
    required this.userId,
    required this.trips,
    required this.repository,
  });

  final Uint8List imageBytes;
  final String imageContentType;
  final String userId;
  final List<Trip> trips;
  final TripRepository repository;

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController(text: 'A moment to remember');
  final _bodyController = TextEditingController();
  Trip? _selectedTrip;
  DateTime _memoryDate = DateUtils.dateOnly(DateTime.now());
  bool _isUploading = false;
  double? _uploadProgress;
  String? _uploadError;

  List<Trip> get _orderedTrips {
    final trips = List<Trip>.from(widget.trips);
    trips.sort((a, b) {
      if (a.status == TripStatus.live && b.status != TripStatus.live) return -1;
      if (a.status != TripStatus.live && b.status == TripStatus.live) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return trips;
  }

  @override
  void initState() {
    super.initState();
    _selectedTrip = initialQuickCaptureDestination(widget.trips);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      helpText: 'When did this happen?',
    );
    if (date != null && mounted) {
      setState(() => _memoryDate = DateUtils.dateOnly(date));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) ||
        _selectedTrip == null ||
        _isUploading) {
      return;
    }
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _uploadError = null;
    });
    try {
      await widget.repository.createEntry(
        tripId: _selectedTrip!.id,
        authorId: widget.userId,
        title: _titleController.text,
        body: _bodyController.text.trim().isEmpty
            ? 'Captured in the moment.'
            : _bodyController.text,
        memoryDate: _memoryDate,
        imageBytes: widget.imageBytes,
        imageContentType: widget.imageContentType,
        onUploadProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      debugPrint('Quick capture failed (${error.code}): ${error.message}');
      if (mounted) {
        setState(() {
          _uploadError = error.code == 'permission-denied'
              ? 'This adventure no longer allows you to add memories.'
              : 'The photo could not be uploaded. Your capture is still here—check your connection and retry.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Quick capture failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _uploadError = 'The photo could not be uploaded. Your capture is still here—check your connection and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _orderedTrips;
    return PopScope(
      canPop: !_isUploading,
      child: Scaffold(
        appBar: const TrekItAppBar(title: Text('Quick Capture')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                      widget.imageBytes,
                      height: 320,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      semanticLabel: 'Captured photo preview',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (trips.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.hiking_outlined),
                      title: Text('No editable adventures'),
                      subtitle: Text(
                        'Create a Live adventure before saving this moment. The photo will remain here until you close this screen.',
                      ),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<Trip>(
                    initialValue: _selectedTrip,
                    decoration: const InputDecoration(
                      labelText: 'Save to adventure',
                      prefixIcon: Icon(Icons.hiking_outlined),
                    ),
                    items: [
                      for (final trip in trips)
                        DropdownMenuItem(
                          value: trip,
                          child: Text('${trip.name} · ${trip.status.label}'),
                        ),
                    ],
                    onChanged: _isUploading
                        ? null
                        : (trip) => setState(() => _selectedTrip = trip),
                    validator: (trip) => trip == null
                        ? 'Choose the adventure for this moment.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _titleController,
                    enabled: !_isUploading,
                    maxLength: 120,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? 'Give this moment a title.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _bodyController,
                    enabled: !_isUploading,
                    maxLength: 10000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'What happened? (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      'Memory date: ${MaterialLocalizations.of(context).formatMediumDate(_memoryDate)}',
                    ),
                  ),
                ],
                if (_uploadProgress case final progress?) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading ${(progress * 100).round()}%',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_uploadError case final error?) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('Upload paused'),
                      subtitle: Text(error),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: trips.isEmpty || _isUploading ? null : _save,
                  icon: _isUploading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _uploadError == null
                              ? Icons.cloud_upload_outlined
                              : Icons.refresh,
                        ),
                  label: Text(
                    _isUploading
                        ? 'Saving moment…'
                        : _uploadError == null
                        ? 'Save moment'
                        : 'Retry upload',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
