import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/domain/journal_entry.dart';

void main() {
  group('JournalEntry timelineDate', () {
    final createdAt = DateTime(2026, 10, 3);
    final updatedAt = DateTime(2026, 10, 4);

    test('uses the memory date when one is saved', () {
      final memoryDate = DateTime(2024, 7, 12);
      final entry = JournalEntry(
        id: 'entry-1',
        title: 'Mountain overlook',
        body: 'A clear afternoon above the valley.',
        authorId: 'user-1',
        createdAt: createdAt,
        updatedAt: updatedAt,
        memoryDate: memoryDate,
      );

      expect(entry.timelineDate, memoryDate);
    });

    test('falls back to the creation date for legacy entries', () {
      final entry = JournalEntry(
        id: 'entry-2',
        title: 'Older memory',
        body: 'Saved before memory dates were available.',
        authorId: 'user-1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(entry.timelineDate, createdAt);
    });
  });

  group('isFutureMemoryDate', () {
    final todayAtNoon = DateTime(2026, 10, 3, 12);

    test('allows a past date', () {
      expect(
        isFutureMemoryDate(DateTime(2026, 10, 2), comparedTo: todayAtNoon),
        isFalse,
      );
    });

    test('allows today regardless of the time', () {
      expect(
        isFutureMemoryDate(
          DateTime(2026, 10, 3, 23, 59),
          comparedTo: todayAtNoon,
        ),
        isFalse,
      );
    });

    test('rejects a future calendar date', () {
      expect(
        isFutureMemoryDate(DateTime(2026, 10, 4), comparedTo: todayAtNoon),
        isTrue,
      );
    });
  });

  test('normalizeMemoryDate removes the time of day', () {
    expect(
      normalizeMemoryDate(DateTime(2026, 10, 3, 23, 59, 58)),
      DateTime(2026, 10, 3),
    );
  });
}
