import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/quick_snippet.dart';

abstract interface class QuickSnippetQueueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesSnippetQueueStorage implements QuickSnippetQueueStorage {
  SharedPreferencesSnippetQueueStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class QuickSnippetQueue {
  QuickSnippetQueue({QuickSnippetQueueStorage? storage})
    : _storage = storage ?? SharedPreferencesSnippetQueueStorage();

  static const maxItems = 100;

  final QuickSnippetQueueStorage _storage;

  String _key(String userId) => 'quick_snippet_queue_v1_$userId';

  Future<List<QueuedSnippet>> load(String userId) async {
    final encoded = await _storage.read(_key(userId));
    if (encoded == null || encoded.isEmpty) {
      return const <QueuedSnippet>[];
    }
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      return values
          .map(
            (value) => QueuedSnippet.fromJson(
              Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <QueuedSnippet>[];
    }
  }

  Future<List<QueuedSnippet>> enqueue(
    String userId,
    QueuedSnippet snippet,
  ) async {
    final current = await load(userId);
    final withoutDuplicate = current
        .where((item) => item.id != snippet.id)
        .toList();
    final updated = <QueuedSnippet>[
      snippet,
      ...withoutDuplicate,
    ].take(maxItems).toList(growable: false);
    await _save(userId, updated);
    return updated;
  }

  Future<List<QueuedSnippet>> remove(String userId, String snippetId) async {
    final current = await load(userId);
    final updated = current
        .where((item) => item.id != snippetId)
        .toList(growable: false);
    await _save(userId, updated);
    return updated;
  }

  Future<void> _save(String userId, List<QueuedSnippet> snippets) async {
    await _storage.write(
      _key(userId),
      jsonEncode(snippets.map((snippet) => snippet.toJson()).toList()),
    );
  }
}
