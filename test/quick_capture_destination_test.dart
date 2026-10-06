import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/capture/domain/quick_capture_destination.dart';
import 'package:trekit/features/trips/domain/trip.dart';

void main() {
  Trip trip(String id, TripStatus status) => Trip(
    id: id,
    name: 'Trip $id',
    description: '',
    ownerId: 'owner',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    status: status,
  );

  test('automatically selects the only Live adventure', () {
    final selected = initialQuickCaptureDestination([
      trip('live', TripStatus.live),
      trip('draft', TripStatus.draft),
    ]);

    expect(selected?.id, 'live');
  });

  test('requires a choice when multiple Live adventures exist', () {
    final selected = initialQuickCaptureDestination([
      trip('live-1', TripStatus.live),
      trip('live-2', TripStatus.live),
    ]);

    expect(selected, isNull);
  });

  test('selects a sole editable non-Live adventure as a fallback', () {
    final selected = initialQuickCaptureDestination([
      trip('draft', TripStatus.draft),
    ]);

    expect(selected?.id, 'draft');
  });
}
