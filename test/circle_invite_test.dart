import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/circle/domain/circle_invite.dart';

void main() {
  test('creates a shareable HTTPS invite without exposing a user UID', () {
    final invite = CircleInvite.forTrekId('trek-8qdads7');

    expect(invite.trekId, 'TREK-8QDADS7');
    expect(invite.uri.toString(), 'https://trekit.online/?invite=TREK-8QDADS7');
  });

  test('parses a valid Circle invite link', () {
    final invite = CircleInvite.fromUri(
      Uri.parse('https://trekit.online/?invite=trek-v4hj7ga'),
    );

    expect(invite?.trekId, 'TREK-V4HJ7GA');
  });

  test('rejects malformed invite parameters', () {
    expect(
      CircleInvite.fromUri(Uri.parse('https://trekit.online/?invite=user-1')),
      isNull,
    );
  });
}
