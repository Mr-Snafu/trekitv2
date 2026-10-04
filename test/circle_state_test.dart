import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/circle/domain/circle_state.dart';

void main() {
  test('parses and sorts private Circle state from the callable response', () {
    final state = CircleState.fromCallable({
      'profile': {
        'userId': 'self',
        'displayName': 'Seth',
        'trekId': 'TREK-ABC1234',
      },
      'circle': [
        {
          'userId': 'renee',
          'displayName': 'Renee',
          'trekId': 'TREK-RENEE12',
          'createdAt': '2026-10-04T12:00:00.000Z',
        },
        {'userId': 'david', 'displayName': 'David', 'trekId': 'TREK-DAVID12'},
      ],
      'incoming': <Object?>[],
      'outgoing': [
        {
          'userId': 'mia',
          'displayName': 'Mia',
          'trekId': 'TREK-MIA1234',
          'status': 'cooldown',
          'retryAfter': '2026-10-05T12:00:00.000Z',
        },
      ],
      'blocked': <Object?>[],
    });

    expect(state.profile.trekId, 'TREK-ABC1234');
    expect(state.circle.map((person) => person.displayName), [
      'David',
      'Renee',
    ]);
    expect(state.outgoing.single.status, 'cooldown');
    expect(state.outgoing.single.retryAfter, DateTime.utc(2026, 10, 5, 12));
  });

  test('uses safe defaults when optional Circle fields are absent', () {
    final person = CirclePerson.fromCallable({
      'userId': 'user-1',
      'trekId': 'TREK-ABC1234',
    });

    expect(person.displayName, 'TrekIt Explorer');
    expect(person.status, 'connected');
    expect(person.createdAt, isNull);
  });
}
