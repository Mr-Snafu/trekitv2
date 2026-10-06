import '../../trips/domain/trip.dart';

Trip? initialQuickCaptureDestination(List<Trip> editableTrips) {
  final liveTrips = editableTrips
      .where((trip) => trip.status == TripStatus.live)
      .toList(growable: false);
  if (liveTrips.length == 1) return liveTrips.single;
  if (liveTrips.isEmpty && editableTrips.length == 1) {
    return editableTrips.single;
  }
  return null;
}
