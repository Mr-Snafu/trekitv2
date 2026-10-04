import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/domain/adventure_activity.dart';
import 'package:trekit/features/trips/domain/adventure_comment.dart';
import 'package:trekit/features/trips/domain/adventure_member_event.dart';
import 'package:trekit/features/trips/domain/journal_entry.dart';
import 'package:trekit/features/trips/domain/quick_snippet.dart';
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
      const <String, List<QuickSnippet>>{},
      const <String, List<AdventureComment>>{},
      const <String, List<AdventureMemberEvent>>{},
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
        const <String, List<QuickSnippet>>{},
        const <String, List<AdventureComment>>{},
        const <String, List<AdventureMemberEvent>>{},
      );

      expect(feed, hasLength(1));
      expect(feed.single.trip.id, visibleTrip.id);
    },
  );

  test('includes quick snippets in newest-first order', () {
    final trip = Trip(
      id: 'trip-1',
      name: 'Yellowstone',
      description: 'Family loop',
      ownerId: 'user-1',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 3),
    );
    final snippet = QuickSnippet(
      id: 'snippet-1',
      text: 'Spotted a bison near the trail.',
      location: 'Lamar Valley',
      authorId: 'user-1',
      capturedAt: DateTime(2026, 7, 4),
    );

    final feed = buildAdventureActivityFeed(
      <Trip>[trip],
      const <String, List<JournalEntry>>{},
      {
        trip.id: <QuickSnippet>[snippet],
      },
      const <String, List<AdventureComment>>{},
      const <String, List<AdventureMemberEvent>>{},
    );

    expect(feed.first.type, AdventureActivityType.quickSnippet);
    expect(feed.first.snippet, snippet);
  });

  test('includes photo, comment, and non-owner sharing activity', () {
    final trip = Trip(
      id: 'trip-1',
      name: 'Yellowstone',
      description: '',
      ownerId: 'owner-1',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 5),
    );
    final entry = JournalEntry(
      id: 'entry-1',
      title: 'Trail view',
      body: 'A clear afternoon.',
      authorId: 'owner-1',
      imagePath: 'users/owner-1/photo',
      createdAt: DateTime(2026, 7, 2),
      updatedAt: DateTime(2026, 7, 2),
    );
    final comment = AdventureComment(
      id: 'comment-1',
      entryId: entry.id,
      body: 'What a view!',
      authorId: 'member-1',
      createdAt: DateTime(2026, 7, 4),
      updatedAt: DateTime(2026, 7, 4),
    );
    final member = AdventureMemberEvent(
      id: 'member-1',
      userId: 'member-1',
      role: 'viewer',
      createdAt: DateTime(2026, 7, 3),
    );
    final ownerMembership = AdventureMemberEvent(
      id: 'owner-1',
      userId: 'owner-1',
      role: 'owner',
      createdAt: DateTime(2026, 7, 1),
    );

    final feed = buildAdventureActivityFeed(
      <Trip>[trip],
      {
        trip.id: <JournalEntry>[entry],
      },
      const <String, List<QuickSnippet>>{},
      {
        trip.id: <AdventureComment>[comment],
      },
      {
        trip.id: <AdventureMemberEvent>[member, ownerMembership],
      },
    );

    expect(
      feed.where((item) => item.type == AdventureActivityType.photoAdded),
      hasLength(1),
    );
    expect(feed.first.type, AdventureActivityType.commentAdded);
    expect(
      feed.where((item) => item.type == AdventureActivityType.memberJoined),
      hasLength(1),
    );
    expect(feed.where((item) => item.member?.role == 'owner'), isEmpty);
  });
}
