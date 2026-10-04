class ProfileState {
  const ProfileState({
    required this.userId,
    required this.email,
    required this.emailVerified,
    required this.displayName,
    required this.bio,
    required this.notifyCircleRequests,
    required this.notifyAdventureActivity,
    required this.allowCircleRequests,
  });

  final String userId;
  final String email;
  final bool emailVerified;
  final String displayName;
  final String bio;
  final bool notifyCircleRequests;
  final bool notifyAdventureActivity;
  final bool allowCircleRequests;

  factory ProfileState.fromCallable(Map<Object?, Object?> data) {
    return ProfileState(
      userId: data['userId'] as String? ?? '',
      email: data['email'] as String? ?? '',
      emailVerified: data['emailVerified'] as bool? ?? false,
      displayName: data['displayName'] as String? ?? 'TrekIt Explorer',
      bio: data['bio'] as String? ?? '',
      notifyCircleRequests: data['notifyCircleRequests'] as bool? ?? true,
      notifyAdventureActivity: data['notifyAdventureActivity'] as bool? ?? true,
      allowCircleRequests: data['allowCircleRequests'] as bool? ?? true,
    );
  }

  ProfileState copyWith({
    String? displayName,
    String? bio,
    bool? notifyCircleRequests,
    bool? notifyAdventureActivity,
    bool? allowCircleRequests,
  }) {
    return ProfileState(
      userId: userId,
      email: email,
      emailVerified: emailVerified,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      notifyCircleRequests: notifyCircleRequests ?? this.notifyCircleRequests,
      notifyAdventureActivity:
          notifyAdventureActivity ?? this.notifyAdventureActivity,
      allowCircleRequests: allowCircleRequests ?? this.allowCircleRequests,
    );
  }
}
