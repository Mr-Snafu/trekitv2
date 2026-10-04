import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/journal_entry.dart';
import '../domain/trip.dart';
import '../domain/trip_member.dart';

class TripRepository {
  TripRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _firestore =
           firestore ??
           FirebaseFirestore.instanceFor(
             app: Firebase.app(),
             databaseId: 'trekit',
           ),
       _storage = storage ?? FirebaseStorage.instanceFor(app: Firebase.app()),
       _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? http.Client();

  static const maxImageBytes = 25 * 1024 * 1024;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

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

  Stream<List<Trip>> watchAccessibleTrips(String userId) {
    return _firestore
        .collectionGroup('members')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((membershipSnapshot) async {
          final trips = await Future.wait(
            membershipSnapshot.docs.map((membership) async {
              final tripReference = membership.reference.parent.parent;
              if (tripReference == null) {
                return null;
              }
              final tripSnapshot = await tripReference.get();
              if (!tripSnapshot.exists) {
                return null;
              }
              final role = membership.data()['role'] as String? ?? 'viewer';
              return Trip.fromFirestore(tripSnapshot).withAccessRole(role);
            }),
          );
          final accessible = trips.whereType<Trip>().toList(growable: false);
          accessible.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return accessible;
        });
  }

  Future<String> createTrip({
    required String ownerId,
    required String name,
    required String description,
    required String location,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trip = _trips.doc();
    final ownerMembership = trip.collection('members').doc(ownerId);
    final now = Timestamp.now();
    final batch = _firestore.batch();

    batch.set(trip, <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      if (location.trim().isNotEmpty) 'location': location.trim(),
      if (startDate != null) 'startDate': Timestamp.fromDate(startDate),
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
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
        .map((snapshot) {
          final entries = snapshot.docs
              .map(JournalEntry.fromFirestore)
              .toList(growable: false);
          entries.sort((a, b) => b.timelineDate.compareTo(a.timelineDate));
          return entries;
        });
  }

  Future<void> createEntry({
    required String tripId,
    required String authorId,
    required String title,
    required String body,
    required DateTime memoryDate,
    Uint8List? imageBytes,
    String? imageContentType,
    void Function(double progress)? onUploadProgress,
  }) async {
    if (isFutureMemoryDate(memoryDate)) {
      throw ArgumentError('The memory date cannot be in the future.');
    }

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
      'memoryDate': Timestamp.fromDate(normalizeMemoryDate(memoryDate)),
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

  Future<Uint8List> getEntryPhoto({
    required String tripId,
    required String entryId,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const TripServiceException('Sign in to continue.');
    }
    final response = await _httpClient.get(
      Uri.https(
        'us-central1-trekit-10e88.cloudfunctions.net',
        '/getEntryPhoto',
        {'tripId': tripId, 'entryId': entryId},
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TripServiceException(
        response.body.isEmpty ? 'Photo unavailable.' : response.body,
      );
    }
    return response.bodyBytes;
  }

  Future<void> shareTrip({
    required String tripId,
    required String email,
    required String role,
  }) async {
    await _callFunction('shareTrip', {
      'tripId': tripId,
      'email': email.trim(),
      'role': role,
    });
  }

  Future<List<TripMember>> listTripMembers(String tripId) async {
    final result = await _callFunction('listTripMembers', {'tripId': tripId});
    final data = result as Map<String, dynamic>;
    final members = data['members'] as List<Object?>? ?? const [];
    return members
        .map(
          (member) => TripMember.fromCallable(
            Map<Object?, Object?>.from(member! as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> removeTripMember({
    required String tripId,
    required String memberId,
  }) async {
    await _callFunction('removeTripMember', {
      'tripId': tripId,
      'memberId': memberId,
    });
  }

  Future<void> updateTrip({
    required String tripId,
    required String name,
    required String description,
    required String location,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _trips.doc(tripId).update({
      'name': name.trim(),
      'description': description.trim(),
      'location': location.trim().isEmpty
          ? FieldValue.delete()
          : location.trim(),
      'startDate': startDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(startDate),
      'endDate': endDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(endDate),
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteTrip(String tripId) async {
    await _callFunction('deleteTrip', {'tripId': tripId});
  }

  Future<Object?> _callFunction(
    String functionName,
    Map<String, Object?> data,
  ) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const TripServiceException('Sign in to continue.');
    }

    final response = await _httpClient.post(
      Uri.parse(
        'https://us-central1-trekit-10e88.cloudfunctions.net/$functionName',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'data': data}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw TripServiceException(
        error?['message'] as String? ?? 'The request could not be completed.',
      );
    }
    return decoded['data'] ?? decoded['result'];
  }

  Future<void> updateEntry({
    required String tripId,
    required String entryId,
    required String title,
    required String body,
    required DateTime memoryDate,
  }) {
    if (isFutureMemoryDate(memoryDate)) {
      throw ArgumentError('The memory date cannot be in the future.');
    }

    return _trips.doc(tripId).collection('entries').doc(entryId).update({
      'title': title.trim(),
      'body': body.trim(),
      'memoryDate': Timestamp.fromDate(normalizeMemoryDate(memoryDate)),
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

class TripServiceException implements Exception {
  const TripServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
