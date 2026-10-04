import 'package:cloud_firestore/cloud_firestore.dart';

class AdventureComment {
  const AdventureComment({
    required this.id,
    required this.entryId,
    required this.body,
    required this.authorId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String entryId;
  final String body;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdventureComment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return AdventureComment(
      id: snapshot.id,
      entryId: data['entryId'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      createdAt: _dateFrom(data['createdAt']),
      updatedAt: _dateFrom(data['updatedAt']),
    );
  }

  static DateTime _dateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : DateTime.now();
  }
}
