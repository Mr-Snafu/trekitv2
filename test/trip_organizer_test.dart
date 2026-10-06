import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/domain/trip.dart';
import 'package:trekit/features/trips/domain/trip_organizer.dart';

void main() {
  final recent = DateTime(2026, 10, 3);
  final older = DateTime(2026, 9, 1);
  final trips = [
    Trip(
      id: 'owned',
      name: 'Mountain Weekend',
      description: 'Hiking with the family',
      location: 'Colorado',
      ownerId: 'user-1',
      createdAt: older,
      updatedAt: recent,
      startDate: DateTime(2026, 12, 10),
      category: TripCategory.outdoorAdventure,
    ),
    Trip(
      id: 'shared',
      name: 'Lake Escape',
      description: 'A quiet cabin',
      location: 'Minnesota',
      ownerId: 'user-2',
      createdAt: older,
      updatedAt: older,
      startDate: DateTime(2027, 1, 4),
      accessRole: 'viewer',
      category: TripCategory.vacation,
    ),
  ];

  test(
    'searches names, descriptions, and locations without case sensitivity',
    () {
      expect(organizeTrips(trips, query: 'colorado').single.id, 'owned');
      expect(organizeTrips(trips, query: 'QUIET').single.id, 'shared');
      expect(organizeTrips(trips, query: 'lake').single.id, 'shared');
      expect(organizeTrips(trips, query: 'outdoor').single.id, 'owned');
    },
  );

  test('filters owned and shared adventures', () {
    expect(
      organizeTrips(trips, filter: TripOwnershipFilter.owned).single.id,
      'owned',
    );
    expect(
      organizeTrips(trips, filter: TripOwnershipFilter.shared).single.id,
      'shared',
    );
  });

  test('sorts by recent activity, trip date, and name', () {
    expect(organizeTrips(trips).first.id, 'owned');
    expect(
      organizeTrips(trips, sortOrder: TripSortOrder.newestTripDate).first.id,
      'shared',
    );
    expect(
      organizeTrips(trips, sortOrder: TripSortOrder.name).first.id,
      'shared',
    );
  });
}
