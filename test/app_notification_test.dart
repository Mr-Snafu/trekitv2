import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/notifications/domain/app_notification.dart';

void main() {
  test('parses a private unread adventure notification', () {
    final createdAt = DateTime.utc(2026, 10, 4, 18);
    final notification = AppNotification.fromMap('notice-1', {
      'type': 'adventureComment',
      'title': 'New comment',
      'body': 'A discussion was updated.',
      'tripId': 'trip-1',
      'createdAt': Timestamp.fromDate(createdAt),
    });

    expect(notification.id, 'notice-1');
    expect(notification.tripId, 'trip-1');
    expect(notification.createdAt.toUtc(), createdAt);
    expect(notification.isUnread, isTrue);
  });

  test('recognizes a read notification', () {
    final notification = AppNotification.fromMap('notice-2', {
      'type': 'circleRequest',
      'title': 'New Circle request',
      'body': 'Someone wants to join your Circle.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 4)),
      'readAt': Timestamp.fromDate(DateTime.utc(2026, 10, 4, 1)),
    });

    expect(notification.isUnread, isFalse);
  });
}
