import 'journal_entry.dart';
import 'trip.dart';

enum AdventureActivityType { adventureStarted, journalEntry }

class AdventureActivity {
  const AdventureActivity({
    required this.id,
    required this.type,
    required this.trip,
    required this.occurredAt,
    this.entry,
  });

  final String id;
  final AdventureActivityType type;
  final Trip trip;
  final DateTime occurredAt;
  final JournalEntry? entry;
}

List<AdventureActivity> buildAdventureActivityFeed(
  List<Trip> trips,
  Map<String, List<JournalEntry>> entriesByTrip,
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
  ];
  activities.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return List.unmodifiable(activities);
}
