import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class QuickSnippet {
  const QuickSnippet({
    required this.id,
    required this.text,
    required this.authorId,
    required this.capturedAt,
    this.location = '',
  });

  final String id;
  final String text;
  final String authorId;
  final DateTime capturedAt;
  final String location;

  factory QuickSnippet.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return QuickSnippet(
      id: snapshot.id,
      text: data['text'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      capturedAt:
          (data['capturedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'] as String? ?? '',
    );
  }
}

class QueuedSnippet {
  const QueuedSnippet({
    required this.id,
    required this.tripId,
    required this.tripName,
    required this.text,
    required this.capturedAt,
    this.location = '',
  });

  factory QueuedSnippet.create({
    required String tripId,
    required String tripName,
    required String text,
    required String location,
    DateTime? capturedAt,
  }) {
    final now = capturedAt ?? DateTime.now();
    final random = Random().nextInt(0x7fffffff).toRadixString(36);
    return QueuedSnippet(
      id: '${now.microsecondsSinceEpoch.toRadixString(36)}-$random',
      tripId: tripId,
      tripName: tripName,
      text: text.trim(),
      location: location.trim(),
      capturedAt: now,
    );
  }

  factory QueuedSnippet.fromJson(Map<String, dynamic> json) {
    return QueuedSnippet(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      tripName: json['tripName'] as String? ?? 'Adventure',
      text: json['text'] as String,
      location: json['location'] as String? ?? '',
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }

  final String id;
  final String tripId;
  final String tripName;
  final String text;
  final DateTime capturedAt;
  final String location;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'tripId': tripId,
    'tripName': tripName,
    'text': text,
    if (location.isNotEmpty) 'location': location,
    'capturedAt': capturedAt.toIso8601String(),
  };
}
