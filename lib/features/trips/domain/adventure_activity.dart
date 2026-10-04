import 'adventure_comment.dart';
import 'adventure_member_event.dart';
import 'journal_entry.dart';
import 'quick_snippet.dart';
import 'trip.dart';

enum AdventureActivityType {
  adventureStarted,
  journalEntry,
  photoAdded,
  quickSnippet,
  commentAdded,
  memberJoined,
}

class AdventureActivity {
  const AdventureActivity({
    required this.id,
    required this.type,
    required this.trip,
    required this.occurredAt,
    this.entry,
    this.snippet,
    this.comment,
    this.member,
  });

  final String id;
  final AdventureActivityType type;
  final Trip trip;
  final DateTime occurredAt;
  final JournalEntry? entry;
  final QuickSnippet? snippet;
  final AdventureComment? comment;
  final AdventureMemberEvent? member;
}

List<AdventureActivity> buildAdventureActivityFeed(
  List<Trip> trips,
  Map<String, List<JournalEntry>> entriesByTrip,
  Map<String, List<QuickSnippet>> snippetsByTrip,
  Map<String, List<AdventureComment>> commentsByTrip,
  Map<String, List<AdventureMemberEvent>> membersByTrip,
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
      for (final entry in entriesByTrip[trip.id] ?? const <JournalEntry>[])
        if (entry.imagePath != null)
          AdventureActivity(
            id: 'photo-${trip.id}-${entry.id}',
            type: AdventureActivityType.photoAdded,
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
    for (final trip in trips)
      for (final comment
          in commentsByTrip[trip.id] ?? const <AdventureComment>[])
        AdventureActivity(
          id: 'comment-${trip.id}-${comment.id}',
          type: AdventureActivityType.commentAdded,
          trip: trip,
          occurredAt: comment.createdAt,
          comment: comment,
        ),
    for (final trip in trips)
      for (final member
          in membersByTrip[trip.id] ?? const <AdventureMemberEvent>[])
        if (member.role != 'owner')
          AdventureActivity(
            id: 'member-${trip.id}-${member.id}',
            type: AdventureActivityType.memberJoined,
            trip: trip,
            occurredAt: member.createdAt,
            member: member,
          ),
  ];
  activities.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return List.unmodifiable(activities);
}
