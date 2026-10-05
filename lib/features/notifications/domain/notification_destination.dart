enum NotificationDestinationKind { circle, adventure }

class NotificationDestination {
  const NotificationDestination._({required this.kind, this.tripId});

  factory NotificationDestination.circle() =>
      const NotificationDestination._(kind: NotificationDestinationKind.circle);

  factory NotificationDestination.adventure(String tripId) =>
      NotificationDestination._(
        kind: NotificationDestinationKind.adventure,
        tripId: tripId,
      );

  factory NotificationDestination.fromUri(Uri uri) {
    return NotificationDestination.fromValues(
      type: uri.queryParameters['notificationType'],
      tripId: uri.queryParameters['tripId'],
    );
  }

  factory NotificationDestination.fromMessageData(Map<String, dynamic> data) {
    return NotificationDestination.fromValues(
      type: data['type'] as String?,
      tripId: data['tripId'] as String?,
    );
  }

  factory NotificationDestination.fromValues({
    required String? type,
    required String? tripId,
  }) {
    if (type == 'circleRequest') return NotificationDestination.circle();
    final normalizedTripId = tripId?.trim() ?? '';
    if (normalizedTripId.isNotEmpty) {
      return NotificationDestination.adventure(normalizedTripId);
    }
    return const NotificationDestination._(
      kind: NotificationDestinationKind.adventure,
    );
  }

  final NotificationDestinationKind kind;
  final String? tripId;

  bool get isActionable =>
      kind == NotificationDestinationKind.circle ||
      (tripId != null && tripId!.isNotEmpty);
}
