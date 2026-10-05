import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.tripId,
    this.readAt,
  });

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => AppNotification.fromMap(
    snapshot.id,
    snapshot.data() ?? const <String, dynamic>{},
  );

  factory AppNotification.fromMap(String id, Map<String, dynamic> data) {
    return AppNotification(
      id: id,
      type: data['type'] as String? ?? 'activity',
      title: data['title'] as String? ?? 'TrekIt update',
      body: data['body'] as String? ?? '',
      tripId: data['tripId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String? tripId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
}
