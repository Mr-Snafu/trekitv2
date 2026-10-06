import 'package:cloud_firestore/cloud_firestore.dart';

enum TripStatus {
  live('live', 'Live'),
  draft('draft', 'Draft'),
  completed('completed', 'Completed');

  const TripStatus(this.value, this.label);

  final String value;
  final String label;

  static TripStatus fromValue(Object? value) {
    return TripStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => TripStatus.live,
    );
  }
}

enum TripCategory {
  roadTrip('road_trip', 'Road Trip'),
  vacation('vacation', 'Vacation'),
  outdoorAdventure('outdoor_adventure', 'Outdoor Adventure'),
  specialEvent('special_event', 'Special Event'),
  familyEvent('family_event', 'Family Event'),
  nightOut('night_out', 'Night Out'),
  dayTrip('day_trip', 'Day Trip'),
  other('other', 'Other');

  const TripCategory(this.value, this.label);

  final String value;
  final String label;

  static TripCategory fromValue(Object? value) {
    return TripCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => TripCategory.other,
    );
  }
}

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.location = '',
    this.startDate,
    this.endDate,
    this.accessRole = 'owner',
    this.status = TripStatus.live,
    this.category = TripCategory.other,
    this.coverImagePath,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String location;
  final DateTime? startDate;
  final DateTime? endDate;
  final String accessRole;
  final TripStatus status;
  final TripCategory category;
  final String? coverImagePath;

  factory Trip.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Trip(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      createdAt: _dateFrom(data['createdAt']),
      updatedAt: _dateFrom(data['updatedAt']),
      location: data['location'] as String? ?? '',
      startDate: _optionalDateFrom(data['startDate']),
      endDate: _optionalDateFrom(data['endDate']),
      status: TripStatus.fromValue(data['status']),
      category: TripCategory.fromValue(data['category']),
      coverImagePath: data['coverImagePath'] as String?,
    );
  }

  Trip withAccessRole(String role) {
    return Trip(
      id: id,
      name: name,
      description: description,
      ownerId: ownerId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      location: location,
      startDate: startDate,
      endDate: endDate,
      accessRole: role,
      status: status,
      category: category,
      coverImagePath: coverImagePath,
    );
  }

  static DateTime _dateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : DateTime.now();
  }

  static DateTime? _optionalDateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }
}
