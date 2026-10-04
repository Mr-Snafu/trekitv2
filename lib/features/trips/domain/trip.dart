import 'package:cloud_firestore/cloud_firestore.dart';

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
    );
  }

  static DateTime _dateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : DateTime.now();
  }

  static DateTime? _optionalDateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }
}
