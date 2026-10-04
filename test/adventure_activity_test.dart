import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/domain/adventure_activity.dart';
import 'package:trekit/features/trips/domain/journal_entry.dart';
import 'package:trekit/features/trips/domain/trip.dart';

void main() {
  test('builds a newest-first feed from authorized adventures and entries', () {
    final trip = Trip(
      id: 'trip-1',
      name: 'Yellowstone',
      description: 'Family loop',
      ownerId: 'user-1',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 3),
    );
    final entry = JournalEntry(
      id: 'entry-1',
      title: 'Old Faithful',
      body: 'A quiet morning near the geyser.',
      authorId: 'user-1',
      createdAt: DateTime(2026, 7, 2),
      updatedAt: DateTime(2026, 7, 2),
    );

    final feed = buildAdventureActivityFeed(
      <Trip>[trip],
      {
        trip.id: <JournalEntry>[entry],
      },
    );

    expect(feed, hasLength(2));
    expect(feed.first.type, AdventureActivityType.journalEntry);
    expect(feed.first.entry, entry);
    expect(feed.last.type, AdventureActivityType.adventureStarted);
  });

  test(
    'does not include activity for adventures outside the supplied list',
    () {
      final visibleTrip = Trip(
        id: 'visible',
        name: 'Visible trip',
        description: '',
        ownerId: 'user-1',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );
      final hiddenEntry = JournalEntry(
        id: 'hidden-entry',
        title: 'Hidden',
        body: 'Not authorized',
        authorId: 'user-2',
        createdAt: DateTime(2026, 7, 4),
        updatedAt: DateTime(2026, 7, 4),
      );

      final feed = buildAdventureActivityFeed(
        <Trip>[visibleTrip],
        {
          'hidden-trip': <JournalEntry>[hiddenEntry],
        },
      );

      expect(feed, hasLength(1));
      expect(feed.single.trip.id, visibleTrip.id);
    },
  );
}
