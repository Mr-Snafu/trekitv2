import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/trips/data/quick_snippet_queue.dart';
import 'package:trekit/features/trips/domain/quick_snippet.dart';

void main() {
  test('persists, loads, and removes a queued snippet for one user', () async {
    final queue = QuickSnippetQueue(storage: _MemoryStorage());
    final snippet = QueuedSnippet.create(
      tripId: 'trip-1',
      tripName: 'Yellowstone',
      text: 'Bison by the trail',
      location: 'Lamar Valley',
      capturedAt: DateTime.utc(2026, 7, 4, 12),
    );

    await queue.enqueue('user-1', snippet);
    final loaded = await queue.load('user-1');

    expect(loaded, hasLength(1));
    expect(loaded.single.id, snippet.id);
    expect(loaded.single.text, snippet.text);
    expect(loaded.single.location, snippet.location);
    expect(await queue.load('user-2'), isEmpty);

    await queue.remove('user-1', snippet.id);
    expect(await queue.load('user-1'), isEmpty);
  });

  test('deduplicates retry IDs and caps the local queue', () async {
    final queue = QuickSnippetQueue(storage: _MemoryStorage());
    final original = QueuedSnippet.create(
      tripId: 'trip-1',
      tripName: 'Yellowstone',
      text: 'Original',
      location: '',
      capturedAt: DateTime.utc(2026, 7, 4),
    );
    await queue.enqueue('user-1', original);
    await queue.enqueue('user-1', original);

    for (var index = 0; index < QuickSnippetQueue.maxItems + 2; index++) {
      await queue.enqueue(
        'user-1',
        QueuedSnippet.create(
          tripId: 'trip-1',
          tripName: 'Yellowstone',
          text: 'Note $index',
          location: '',
          capturedAt: DateTime.utc(2026, 7, 5).add(Duration(seconds: index)),
        ),
      );
    }

    expect(await queue.load('user-1'), hasLength(QuickSnippetQueue.maxItems));
  });
}

class _MemoryStorage implements QuickSnippetQueueStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
