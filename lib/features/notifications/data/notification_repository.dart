import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../domain/app_notification.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _firestore =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'trekit',
          );

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _notifications(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  Stream<List<AppNotification>> watchNotifications(String userId) {
    return _notifications(userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AppNotification.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> markRead(String userId, String notificationId) {
    return _notifications(userId)
        .doc(notificationId)
        .update({'readAt': Timestamp.now()});
  }

  Future<void> markAllRead(
    String userId,
    Iterable<AppNotification> notifications,
  ) async {
    final unread = notifications.where((item) => item.isUnread).take(50);
    final batch = _firestore.batch();
    final now = Timestamp.now();
    for (final notification in unread) {
      batch.update(_notifications(userId).doc(notification.id), {
        'readAt': now,
      });
    }
    await batch.commit();
  }

  Future<void> dismiss(String userId, String notificationId) {
    return _notifications(userId).doc(notificationId).delete();
  }
}
