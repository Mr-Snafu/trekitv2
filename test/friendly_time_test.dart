import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/core/time/friendly_time.dart';

void main() {
  final now = DateTime(2026, 10, 4, 18, 0);
  String time(DateTime value) => '${value.hour}:${value.minute}';
  String date(DateTime value) => '${value.month}/${value.day}/${value.year}';
  String weekday(DateTime value) => 'Weekday ${value.weekday}';

  test('uses friendly relative labels for recent activity', () {
    expect(
      friendlyTimeLabel(
        occurredAt: now.subtract(const Duration(seconds: 20)),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      'Just now',
    );
    expect(
      friendlyTimeLabel(
        occurredAt: now.subtract(const Duration(minutes: 18)),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      '18 min ago',
    );
    expect(
      friendlyTimeLabel(
        occurredAt: now.subtract(const Duration(hours: 2)),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      '2 hrs ago',
    );
  });

  test('uses calendar-aware labels for older activity', () {
    expect(
      friendlyTimeLabel(
        occurredAt: DateTime(2026, 10, 3, 14, 30),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      'Yesterday, 14:30',
    );
    expect(
      friendlyTimeLabel(
        occurredAt: DateTime(2026, 10, 1, 9, 15),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      'Weekday 4, 9:15',
    );
    expect(
      friendlyTimeLabel(
        occurredAt: DateTime(2026, 9, 20),
        now: now,
        formatTime: time,
        formatDate: date,
        formatWeekday: weekday,
      ),
      '9/20/2026',
    );
  });

  test('groups the activity timeline by useful day sections', () {
    expect(activitySectionLabel(now, now), 'Today');
    expect(
      activitySectionLabel(now.subtract(const Duration(days: 1)), now),
      'Yesterday',
    );
    expect(
      activitySectionLabel(now.subtract(const Duration(days: 3)), now),
      'Earlier this week',
    );
    expect(
      activitySectionLabel(now.subtract(const Duration(days: 10)), now),
      'Earlier',
    );
  });
}
