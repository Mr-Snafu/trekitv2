import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/notifications/domain/notification_destination.dart';

void main() {
  test('routes a Circle request link to Circle', () {
    final destination = NotificationDestination.fromUri(
      Uri.parse('https://trekit.online/?notificationType=circleRequest'),
    );

    expect(destination.kind, NotificationDestinationKind.circle);
    expect(destination.isActionable, isTrue);
  });

  test('routes an adventure link to its private trip', () {
    final destination = NotificationDestination.fromUri(
      Uri.parse(
        'https://trekit.online/?notificationType=adventureComment&tripId=trip-123',
      ),
    );

    expect(destination.kind, NotificationDestinationKind.adventure);
    expect(destination.tripId, 'trip-123');
    expect(destination.isActionable, isTrue);
  });

  test('ignores notification data without a destination', () {
    final destination = NotificationDestination.fromMessageData(const {
      'type': 'unknown',
    });

    expect(destination.isActionable, isFalse);
  });
}
