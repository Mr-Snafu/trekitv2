class CirclePerson {
  const CirclePerson({
    required this.userId,
    required this.displayName,
    required this.trekId,
    required this.status,
    this.createdAt,
    this.retryAfter,
  });

  final String userId;
  final String displayName;
  final String trekId;
  final String status;
  final DateTime? createdAt;
  final DateTime? retryAfter;

  factory CirclePerson.fromCallable(Map<Object?, Object?> data) {
    return CirclePerson(
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'TrekIt Explorer',
      trekId: data['trekId'] as String? ?? '',
      status: data['status'] as String? ?? 'connected',
      createdAt: _dateFrom(data['createdAt']),
      retryAfter: _dateFrom(data['retryAfter']),
    );
  }

  static DateTime? _dateFrom(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class CircleProfile {
  const CircleProfile({
    required this.userId,
    required this.displayName,
    required this.trekId,
  });

  final String userId;
  final String displayName;
  final String trekId;

  factory CircleProfile.fromCallable(Map<Object?, Object?> data) {
    return CircleProfile(
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'TrekIt Explorer',
      trekId: data['trekId'] as String? ?? '',
    );
  }
}

class CircleState {
  const CircleState({
    required this.profile,
    required this.circle,
    required this.incoming,
    required this.outgoing,
    required this.blocked,
  });

  final CircleProfile profile;
  final List<CirclePerson> circle;
  final List<CirclePerson> incoming;
  final List<CirclePerson> outgoing;
  final List<CirclePerson> blocked;

  factory CircleState.fromCallable(Map<Object?, Object?> data) {
    List<CirclePerson> people(String key) {
      final values = data[key] as List<Object?>? ?? const <Object?>[];
      return values
          .whereType<Map>()
          .map(
            (value) =>
                CirclePerson.fromCallable(Map<Object?, Object?>.from(value)),
          )
          .toList(growable: false)
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    return CircleState(
      profile: CircleProfile.fromCallable(
        Map<Object?, Object?>.from(data['profile']! as Map),
      ),
      circle: people('circle'),
      incoming: people('incoming'),
      outgoing: people('outgoing'),
      blocked: people('blocked'),
    );
  }
}
