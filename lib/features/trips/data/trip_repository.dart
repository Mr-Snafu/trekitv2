import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/journal_entry.dart';
import '../domain/trip.dart';

class TripRepository {
  TripRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'trekit',
          ),
      _storage = storage ?? FirebaseStorage.instanceFor(app: Firebase.app());

  static const maxImageBytes = 25 * 1024 * 1024;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _firestore.collection('trips');

  Future<void> ensureUserProfile(User user) async {
    final profile = _firestore.collection('users').doc(user.uid);
    final snapshot = await profile.get();
    final now = Timestamp.now();
    final email = user.email?.trim() ?? '';

    if (!snapshot.exists) {
      await profile.set({
        'uid': user.uid,
        'email': email,
        'createdAt': now,
        'updatedAt': now,
      });
      return;
    }

    await profile.update({'email': email, 'updatedAt': now});
  }

  Stream<List<Trip>> watchOwnedTrips(String userId) {
    return _trips
        .where('ownerId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(Trip.fromFirestore).toList(growable: false),
        );
  }

  Future<String> createTrip({
    required String ownerId,
    required String name,
    required String description,
  }) async {
    final trip = _trips.doc();
    final ownerMembership = trip.collection('members').doc(ownerId);
    final now = Timestamp.now();
    final batch = _firestore.batch();

    batch.set(trip, {
      'name': name.trim(),
      'description': description.trim(),
      'ownerId': ownerId,
      'createdAt': now,
      'updatedAt': now,
    });
    batch.set(ownerMembership, {
      'userId': ownerId,
      'role': 'owner',
      'createdBy': ownerId,
      'createdAt': now,
    });

    await batch.commit();
    return trip.id;
  }

  Stream<List<JournalEntry>> watchEntries(String tripId) {
    return _trips
        .doc(tripId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(JournalEntry.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> createEntry({
    required String tripId,
    required String authorId,
    required String title,
    required String body,
    Uint8List? imageBytes,
    String? imageContentType,
    void Function(double progress)? onUploadProgress,
  }) async {
    final entry = _trips.doc(tripId).collection('entries').doc();
    final now = Timestamp.now();
    Reference? imageReference;
    String? imagePath;

    if (imageBytes != null) {
      if (imageBytes.isEmpty || imageBytes.length > maxImageBytes) {
        throw ArgumentError('The photo must be between 1 byte and 25 MB.');
      }

      imagePath = 'users/$authorId/trips/$tripId/entries/${entry.id}/photo';
      imageReference = _storage.ref(imagePath);
      final upload = imageReference.putData(
        imageBytes,
        SettableMetadata(contentType: imageContentType ?? 'image/jpeg'),
      );
      upload.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onUploadProgress?.call(
            snapshot.bytesTransferred / snapshot.totalBytes,
          );
        }
      });
      await upload;
    }

    final data = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'authorId': authorId,
      'createdAt': now,
      'updatedAt': now,
      'imagePath': ?imagePath,
    };

    try {
      await entry.set(data);
    } catch (_) {
      if (imageReference != null) {
        try {
          await imageReference.delete();
        } catch (_) {
          // Preserve the original Firestore error if cleanup cannot complete.
        }
      }
      rethrow;
    }
  }

  Future<Uint8List?> loadEntryImage(String imagePath) {
    return _storage.ref(imagePath).getData(maxImageBytes);
  }

  Future<void> updateEntry({
    required String tripId,
    required String entryId,
    required String title,
    required String body,
  }) {
    return _trips.doc(tripId).collection('entries').doc(entryId).update({
      'title': title.trim(),
      'body': body.trim(),
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteEntry({
    required String tripId,
    required JournalEntry entry,
  }) async {
    await _trips.doc(tripId).collection('entries').doc(entry.id).delete();

    if (entry.imagePath case final imagePath?) {
      try {
        await _storage.ref(imagePath).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          // The entry is already gone, so photo cleanup can be retried later.
        }
      }
    }
  }
}
