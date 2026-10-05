import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DraftStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesDraftStorage implements DraftStorage {
  SharedPreferencesDraftStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

class LocalDraftStore {
  LocalDraftStore({DraftStorage? storage})
    : _storage = storage ?? SharedPreferencesDraftStorage();

  final DraftStorage _storage;

  String _adventureKey(String userId) => 'adventure_draft_v1_$userId';
  String _entryKey(String userId, String tripId) =>
      'entry_draft_v1_${userId}_$tripId';

  Future<AdventureFormDraft?> loadAdventure(String userId) async {
    final value = await _readJson(_adventureKey(userId));
    return value == null ? null : AdventureFormDraft.fromJson(value);
  }

  Future<void> saveAdventure(String userId, AdventureFormDraft draft) =>
      _storage.write(_adventureKey(userId), jsonEncode(draft.toJson()));

  Future<void> clearAdventure(String userId) =>
      _storage.remove(_adventureKey(userId));

  Future<JournalFormDraft?> loadEntry(String userId, String tripId) async {
    final value = await _readJson(_entryKey(userId, tripId));
    return value == null ? null : JournalFormDraft.fromJson(value);
  }

  Future<void> saveEntry(
    String userId,
    String tripId,
    JournalFormDraft draft,
  ) => _storage.write(_entryKey(userId, tripId), jsonEncode(draft.toJson()));

  Future<void> clearEntry(String userId, String tripId) =>
      _storage.remove(_entryKey(userId, tripId));

  Future<Map<String, dynamic>?> _readJson(String key) async {
    final encoded = await _storage.read(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    } catch (_) {
      await _storage.remove(key);
      return null;
    }
  }
}

class AdventureFormDraft {
  const AdventureFormDraft({
    required this.name,
    required this.description,
    required this.location,
    required this.status,
    required this.updatedAt,
    this.startDate,
    this.endDate,
    this.hadPhoto = false,
  });

  factory AdventureFormDraft.fromJson(Map<String, dynamic> json) {
    return AdventureFormDraft(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      startDate: _tryDate(json['startDate']),
      endDate: _tryDate(json['endDate']),
      hadPhoto: json['hadPhoto'] as bool? ?? false,
      updatedAt: _tryDate(json['updatedAt']) ?? DateTime.now(),
    );
  }

  final String name;
  final String description;
  final String location;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool hadPhoto;
  final DateTime updatedAt;

  bool get isEmpty =>
      name.isEmpty &&
      description.isEmpty &&
      location.isEmpty &&
      startDate == null &&
      endDate == null &&
      !hadPhoto;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'location': location,
    'status': status,
    if (startDate != null) 'startDate': startDate!.toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toIso8601String(),
    'hadPhoto': hadPhoto,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class JournalFormDraft {
  const JournalFormDraft({
    required this.title,
    required this.body,
    required this.memoryDate,
    required this.updatedAt,
    this.hadPhoto = false,
  });

  factory JournalFormDraft.fromJson(Map<String, dynamic> json) {
    return JournalFormDraft(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      memoryDate: _tryDate(json['memoryDate']) ?? DateTime.now(),
      hadPhoto: json['hadPhoto'] as bool? ?? false,
      updatedAt: _tryDate(json['updatedAt']) ?? DateTime.now(),
    );
  }

  final String title;
  final String body;
  final DateTime memoryDate;
  final bool hadPhoto;
  final DateTime updatedAt;

  bool get isEmpty => title.isEmpty && body.isEmpty && !hadPhoto;

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'memoryDate': memoryDate.toIso8601String(),
    'hadPhoto': hadPhoto,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

DateTime? _tryDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
