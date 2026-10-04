import 'journal_entry.dart';
import 'quick_snippet.dart';
import 'trip.dart';

enum AdventureActivityType { adventureStarted, journalEntry, quickSnippet }

class AdventureActivity {
  const AdventureActivity({
    required this.id,
    required this.type,
    required this.trip,
    required this.occurredAt,
    this.entry,
    this.snippet,
  });

  final String id;
  final AdventureActivityType type;
  final Trip trip;
  final DateTime occurredAt;
  final JournalEntry? entry;
  final QuickSnippet? snippet;
}

List<AdventureActivity> buildAdventureActivityFeed(
  List<Trip> trips,
  Map<String, List<JournalEntry>> entriesByTrip,
  Map<String, List<QuickSnippet>> snippetsByTrip,
) {
  final activities = <AdventureActivity>[
    for (final trip in trips)
      AdventureActivity(
        id: 'trip-${trip.id}',
        type: AdventureActivityType.adventureStarted,
        trip: trip,
        occurredAt: trip.createdAt,
      ),
    for (final trip in trips)
      for (final entry in entriesByTrip[trip.id] ?? const <JournalEntry>[])
        AdventureActivity(
          id: 'entry-${trip.id}-${entry.id}',
          type: AdventureActivityType.journalEntry,
          trip: trip,
          occurredAt: entry.createdAt,
          entry: entry,
        ),
    for (final trip in trips)
      for (final snippet in snippetsByTrip[trip.id] ?? const <QuickSnippet>[])
        AdventureActivity(
          id: 'snippet-${trip.id}-${snippet.id}',
          type: AdventureActivityType.quickSnippet,
          trip: trip,
          occurredAt: snippet.capturedAt,
          snippet: snippet,
        ),
  ];
  activities.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return List.unmodifiable(activities);
}
