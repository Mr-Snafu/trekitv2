import 'package:cloud_firestore/cloud_firestore.dart';

class AdventureMemberEvent {
  const AdventureMemberEvent({
    required this.id,
    required this.userId,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String role;
  final DateTime createdAt;

  factory AdventureMemberEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return AdventureMemberEvent(
      id: snapshot.id,
      userId: data['userId'] as String? ?? '',
      role: data['role'] as String? ?? 'viewer',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
