import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/core/drafts/local_draft_store.dart';

void main() {
  test('keeps adventure drafts private to one account', () async {
    final store = LocalDraftStore(storage: _MemoryDraftStorage());
    final draft = AdventureFormDraft(
      name: 'Pacific Northwest',
      description: 'Forests and coast',
      location: 'Oregon',
      status: 'draft',
      startDate: DateTime(2026, 11, 2),
      hadPhoto: true,
      updatedAt: DateTime(2026, 10, 4),
    );

    await store.saveAdventure('user-1', draft);
    final restored = await store.loadAdventure('user-1');

    expect(restored?.name, draft.name);
    expect(restored?.startDate, draft.startDate);
    expect(restored?.hadPhoto, isTrue);
    expect(await store.loadAdventure('user-2'), isNull);
    await store.clearAdventure('user-1');
    expect(await store.loadAdventure('user-1'), isNull);
  });

  test('keeps journal drafts separate for each adventure', () async {
    final store = LocalDraftStore(storage: _MemoryDraftStorage());
    final draft = JournalFormDraft(
      title: 'Waterfall trail',
      body: 'Saved during a connection interruption.',
      memoryDate: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 4),
    );

    await store.saveEntry('user-1', 'trip-1', draft);

    expect((await store.loadEntry('user-1', 'trip-1'))?.body, draft.body);
    expect(await store.loadEntry('user-1', 'trip-2'), isNull);
    await store.clearEntry('user-1', 'trip-1');
    expect(await store.loadEntry('user-1', 'trip-1'), isNull);
  });

  test('removes unreadable local draft data', () async {
    final storage = _MemoryDraftStorage();
    final store = LocalDraftStore(storage: storage);
    await storage.write('adventure_draft_v1_user-1', 'not-json');

    expect(await store.loadAdventure('user-1'), isNull);
    expect(await storage.read('adventure_draft_v1_user-1'), isNull);
  });
}

class _MemoryDraftStorage implements DraftStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
