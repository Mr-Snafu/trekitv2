import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/domain/trip.dart';

void main() {
  test('recognizes every supported adventure lifecycle status', () {
    expect(TripStatus.fromValue('draft'), TripStatus.draft);
    expect(TripStatus.fromValue('live'), TripStatus.live);
    expect(TripStatus.fromValue('completed'), TripStatus.completed);
  });

  test('treats legacy or unknown adventure statuses as live', () {
    expect(TripStatus.fromValue(null), TripStatus.live);
    expect(TripStatus.fromValue('unknown'), TripStatus.live);
  });
}
