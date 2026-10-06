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

  test('recognizes every supported adventure category', () {
    expect(TripCategory.fromValue('road_trip'), TripCategory.roadTrip);
    expect(TripCategory.fromValue('vacation'), TripCategory.vacation);
    expect(
      TripCategory.fromValue('outdoor_adventure'),
      TripCategory.outdoorAdventure,
    );
    expect(TripCategory.fromValue('special_event'), TripCategory.specialEvent);
    expect(TripCategory.fromValue('family_event'), TripCategory.familyEvent);
    expect(TripCategory.fromValue('night_out'), TripCategory.nightOut);
    expect(TripCategory.fromValue('day_trip'), TripCategory.dayTrip);
    expect(TripCategory.fromValue('other'), TripCategory.other);
  });

  test('treats legacy or unknown adventure categories as other', () {
    expect(TripCategory.fromValue(null), TripCategory.other);
    expect(TripCategory.fromValue('unknown'), TripCategory.other);
  });
}
