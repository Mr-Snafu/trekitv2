import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/journal_entry.dart';
import '../domain/adventure_activity.dart';
import '../domain/adventure_comment.dart';
import '../domain/adventure_member_event.dart';
import '../domain/quick_snippet.dart';
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
    required TripStatus status,
    required TripCategory category,
    DateTime? startDate,
    DateTime? endDate,
    Uint8List? coverImageBytes,
    String? coverContentType,
  }) async {
    final trip = _trips.doc();
    final ownerMembership = trip.collection('members').doc(ownerId);
    final now = Timestamp.now();
    final batch = _firestore.batch();
    final coverImagePath = coverImageBytes == null
        ? null
        : 'users/$ownerId/trips/${trip.id}/cover';

    if (coverImageBytes != null) {
      await _uploadPhoto(
        path: coverImagePath!,
        bytes: coverImageBytes,
        contentType: coverContentType,
      );
    }

    batch.set(trip, <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      if (location.trim().isNotEmpty) 'location': location.trim(),
      if (startDate != null) 'startDate': Timestamp.fromDate(startDate),
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
      'status': status.value,
      'category': category.value,
      'coverImagePath': ?coverImagePath,
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

    try {
      await batch.commit();
    } catch (_) {
      if (coverImagePath != null) {
        try {
          await _storage.ref(coverImagePath).delete();
        } catch (_) {
          // Preserve the original Firestore error if cleanup cannot complete.
        }
      }
      rethrow;
    }
    return trip.id;
  }

  Future<void> _uploadPhoto({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw ArgumentError('The photo must be between 1 byte and 25 MB.');
    }
    await _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(contentType: contentType ?? 'image/jpeg'),
        );
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

  Stream<List<AdventureActivity>> watchActivityFeed(List<Trip> trips) {
    late final StreamController<List<AdventureActivity>> controller;
    final entriesByTrip = <String, List<JournalEntry>>{};
    final snippetsByTrip = <String, List<QuickSnippet>>{};
    final commentsByTrip = <String, List<AdventureComment>>{};
    final membersByTrip = <String, List<AdventureMemberEvent>>{};
    final subscriptions = <StreamSubscription<dynamic>>[];

    void emitFeed() {
      if (!controller.isClosed) {
        controller.add(
          buildAdventureActivityFeed(
            trips,
            entriesByTrip,
            snippetsByTrip,
            commentsByTrip,
            membersByTrip,
          ),
        );
      }
    }

    controller = StreamController<List<AdventureActivity>>(
      onListen: () {
        emitFeed();
        for (final trip in trips) {
          subscriptions.add(
            _watchRecentEntries(trip.id).listen((entries) {
              entriesByTrip[trip.id] = entries;
              emitFeed();
            }, onError: controller.addError),
          );
          subscriptions.add(
            _watchRecentComments(trip.id).listen((comments) {
              commentsByTrip[trip.id] = comments;
              emitFeed();
            }, onError: controller.addError),
          );
          subscriptions.add(
            _watchRecentMembers(trip.id).listen((members) {
              membersByTrip[trip.id] = members;
              emitFeed();
            }, onError: controller.addError),
          );
          subscriptions.add(
            _watchRecentSnippets(trip.id).listen((snippets) {
              snippetsByTrip[trip.id] = snippets;
              emitFeed();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Stream<List<AdventureComment>> _watchRecentComments(String tripId) {
    return _trips
        .doc(tripId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AdventureComment.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<AdventureMemberEvent>> _watchRecentMembers(String tripId) {
    return _trips
        .doc(tripId)
        .collection('members')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AdventureMemberEvent.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<AdventureComment>> watchComments({
    required String tripId,
    required String entryId,
  }) {
    return _trips
        .doc(tripId)
        .collection('comments')
        .where('entryId', isEqualTo: entryId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final comments = snapshot.docs
              .map(AdventureComment.fromFirestore)
              .toList(growable: false);
          comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return comments;
        });
  }

  Future<void> createComment({
    required String tripId,
    required String entryId,
    required String authorId,
    required String body,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty || trimmedBody.length > 2000) {
      throw ArgumentError('A comment must be between 1 and 2,000 characters.');
    }
    final now = Timestamp.now();
    await _trips.doc(tripId).collection('comments').add({
      'entryId': entryId,
      'body': trimmedBody,
      'authorId': authorId,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateComment({
    required String tripId,
    required String commentId,
    required String body,
  }) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty || trimmedBody.length > 2000) {
      throw ArgumentError('A comment must be between 1 and 2,000 characters.');
    }
    return _trips.doc(tripId).collection('comments').doc(commentId).update({
      'body': trimmedBody,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteComment({
    required String tripId,
    required String commentId,
  }) {
    return _trips.doc(tripId).collection('comments').doc(commentId).delete();
  }

  Stream<List<QuickSnippet>> _watchRecentSnippets(String tripId) {
    return _trips
        .doc(tripId)
        .collection('snippets')
        .orderBy('capturedAt', descending: true)
        .limit(25)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(QuickSnippet.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> createSnippet({
    required String tripId,
    required String snippetId,
    required String authorId,
    required String text,
    required String location,
    required DateTime capturedAt,
    Uint8List? imageBytes,
    String? imageContentType,
  }) async {
    final trimmedText = text.trim();
    final trimmedLocation = location.trim();
    if (trimmedText.isEmpty || trimmedText.length > 1000) {
      throw ArgumentError(
        'A quick snippet must be between 1 and 1,000 characters.',
      );
    }
    if (trimmedLocation.length > 160) {
      throw ArgumentError('The location must be 160 characters or fewer.');
    }
    if (capturedAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw ArgumentError('A quick snippet cannot be dated in the future.');
    }

    Reference? imageReference;
    if (imageBytes != null) {
      if (imageBytes.isEmpty || imageBytes.length > maxImageBytes) {
        throw ArgumentError('The photo must be between 1 byte and 25 MB.');
      }
      final imagePath =
          'users/$authorId/trips/$tripId/entries/$snippetId/photo';
      imageReference = _storage.ref(imagePath);
      await imageReference.putData(
        imageBytes,
        SettableMetadata(contentType: imageContentType ?? 'image/jpeg'),
      );
    }

    try {
      await _trips.doc(tripId).collection('snippets').doc(snippetId).set({
        'text': trimmedText,
        if (trimmedLocation.isNotEmpty) 'location': trimmedLocation,
        'authorId': authorId,
        'capturedAt': Timestamp.fromDate(capturedAt),
      });
    } catch (_) {
      if (imageReference != null) {
        try {
          await imageReference.delete();
        } catch (_) {
          // Preserve the Firestore error if photo cleanup cannot complete.
        }
      }
      rethrow;
    }
  }

  Future<Uint8List?> getSnippetPhoto({
    required String tripId,
    required String snippetId,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) return null;
    final response = await _httpClient.get(
      Uri.https(
        'us-central1-trekit-10e88.cloudfunctions.net',
        '/getSnippetPhoto',
        {'tripId': tripId, 'snippetId': snippetId},
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TripServiceException(
        response.body.isEmpty ? 'Photo unavailable.' : response.body,
      );
    }
    return response.bodyBytes;
  }

  Stream<List<JournalEntry>> _watchRecentEntries(String tripId) {
    return _trips
        .doc(tripId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(25)
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

  Future<Uint8List> getTripCover(Trip trip) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const TripServiceException('Sign in to continue.');
    }
    final response = await _httpClient.get(
      Uri.https(
        'us-central1-trekit-10e88.cloudfunctions.net',
        '/getTripCover',
        {
          'tripId': trip.id,
          'version': trip.updatedAt.millisecondsSinceEpoch.toString(),
        },
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TripServiceException(
        response.body.isEmpty ? 'Cover unavailable.' : response.body,
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
    required String ownerId,
    required String name,
    required String description,
    required String location,
    required TripStatus status,
    required TripCategory category,
    DateTime? startDate,
    DateTime? endDate,
    Uint8List? coverImageBytes,
    String? coverContentType,
    bool removeCover = false,
  }) async {
    final coverImagePath = 'users/$ownerId/trips/$tripId/cover';
    if (coverImageBytes != null) {
      await _uploadPhoto(
        path: coverImagePath,
        bytes: coverImageBytes,
        contentType: coverContentType,
      );
    }

    await _trips.doc(tripId).update({
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
      'status': status.value,
      'category': category.value,
      if (coverImageBytes != null) 'coverImagePath': coverImagePath,
      if (removeCover && coverImageBytes == null)
        'coverImagePath': FieldValue.delete(),
      'updatedAt': Timestamp.now(),
    });

    if (removeCover && coverImageBytes == null) {
      try {
        await _storage.ref(coverImagePath).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          rethrow;
        }
      }
    }
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
    await _callFunction('deleteJournalEntry', {
      'tripId': tripId,
      'entryId': entry.id,
    });
  }
}

class TripServiceException implements Exception {
  const TripServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
