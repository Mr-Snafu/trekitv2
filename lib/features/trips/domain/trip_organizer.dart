import 'trip.dart';

enum TripOwnershipFilter { all, owned, shared }

enum TripSortOrder { recentlyUpdated, newestTripDate, name }

List<Trip> organizeTrips(
  Iterable<Trip> trips, {
  String query = '',
  TripOwnershipFilter filter = TripOwnershipFilter.all,
  TripSortOrder sortOrder = TripSortOrder.recentlyUpdated,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final visible = trips
      .where((trip) {
        final matchesFilter = switch (filter) {
          TripOwnershipFilter.all => true,
          TripOwnershipFilter.owned => trip.accessRole == 'owner',
          TripOwnershipFilter.shared => trip.accessRole != 'owner',
        };
        if (!matchesFilter || normalizedQuery.isEmpty) {
          return matchesFilter;
        }
        return trip.name.toLowerCase().contains(normalizedQuery) ||
            trip.description.toLowerCase().contains(normalizedQuery) ||
            trip.location.toLowerCase().contains(normalizedQuery) ||
            trip.category.label.toLowerCase().contains(normalizedQuery);
      })
      .toList(growable: false);

  visible.sort((a, b) {
    return switch (sortOrder) {
      TripSortOrder.recentlyUpdated => b.updatedAt.compareTo(a.updatedAt),
      TripSortOrder.newestTripDate => _compareTripDates(a, b),
      TripSortOrder.name => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
    };
  });
  return visible;
}

int _compareTripDates(Trip a, Trip b) {
  final aDate = a.startDate ?? a.endDate;
  final bDate = b.startDate ?? b.endDate;
  if (aDate == null && bDate == null) {
    return b.updatedAt.compareTo(a.updatedAt);
  }
  if (aDate == null) {
    return 1;
  }
  if (bDate == null) {
    return -1;
  }
  return bDate.compareTo(aDate);
}
