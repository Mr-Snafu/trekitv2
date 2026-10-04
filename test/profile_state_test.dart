import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/profile/domain/profile_state.dart';

void main() {
  test('parses saved Profile identity and preferences', () {
    final profile = ProfileState.fromCallable({
      'userId': 'user-1',
      'email': 'seth@example.com',
      'emailVerified': true,
      'displayName': 'Seth',
      'bio': 'Road trips and quiet places.',
      'notifyCircleRequests': false,
      'notifyAdventureActivity': true,
      'allowCircleRequests': false,
    });

    expect(profile.displayName, 'Seth');
    expect(profile.bio, 'Road trips and quiet places.');
    expect(profile.emailVerified, isTrue);
    expect(profile.notifyCircleRequests, isFalse);
    expect(profile.notifyAdventureActivity, isTrue);
    expect(profile.allowCircleRequests, isFalse);
  });

  test('uses privacy-preserving defaults for legacy profiles', () {
    final profile = ProfileState.fromCallable({
      'userId': 'user-1',
      'email': 'seth@example.com',
    });

    expect(profile.displayName, 'TrekIt Explorer');
    expect(profile.notifyCircleRequests, isTrue);
    expect(profile.notifyAdventureActivity, isTrue);
    expect(profile.allowCircleRequests, isTrue);
  });

  test('copyWith changes preferences without losing identity', () {
    const profile = ProfileState(
      userId: 'user-1',
      email: 'seth@example.com',
      emailVerified: true,
      displayName: 'Seth',
      bio: '',
      notifyCircleRequests: true,
      notifyAdventureActivity: true,
      allowCircleRequests: true,
    );

    final updated = profile.copyWith(allowCircleRequests: false);

    expect(updated.allowCircleRequests, isFalse);
    expect(updated.displayName, profile.displayName);
    expect(updated.email, profile.email);
  });
}
