import 'package:cloud_firestore/cloud_firestore.dart';

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.authorId,
    required this.createdAt,
    required this.updatedAt,
    this.memoryDate,
    this.imagePath,
  });

  final String id;
  final String title;
  final String body;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? memoryDate;
  final String? imagePath;

  DateTime get timelineDate => memoryDate ?? createdAt;

  factory JournalEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return JournalEntry(
      id: snapshot.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      createdAt: _dateFrom(data['createdAt']),
      updatedAt: _dateFrom(data['updatedAt']),
      memoryDate: _optionalDateFrom(data['memoryDate']),
      imagePath: data['imagePath'] as String?,
    );
  }

  static DateTime _dateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : DateTime.now();
  }

  static DateTime? _optionalDateFrom(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }
}
