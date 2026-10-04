class TripMember {
  const TripMember({
    required this.userId,
    required this.email,
    required this.role,
  });

  final String userId;
  final String email;
  final String role;

  factory TripMember.fromCallable(Map<Object?, Object?> data) {
    return TripMember(
      userId: data['userId'] as String? ?? '',
      email: data['email'] as String? ?? 'Account unavailable',
      role: data['role'] as String? ?? 'viewer',
    );
  }
}
