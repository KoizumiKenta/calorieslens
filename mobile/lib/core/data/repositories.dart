import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../models/user_profile.dart';

/// shared_preferences-backed persistence for v1 (works on web, iOS, Android
/// with zero native setup). Each repository is an interface-shaped class so
/// the Drift implementation can replace it for device builds without
/// touching feature code.
class ProfileRepository {
  ProfileRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'profile.v1';

  UserProfile? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(UserProfile profile) =>
      _prefs.setString(_key, jsonEncode(profile.toJson()));

  Future<void> clear() => _prefs.remove(_key);
}

class DiaryRepository {
  DiaryRepository(this._prefs);

  final SharedPreferences _prefs;

  String _entriesKey(String dateKey) => 'diary.v1.$dateKey';

  List<DiaryEntry> entriesFor(String dateKey) {
    final raw = _prefs.getString(_entriesKey(dateKey));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(DiaryEntry entry) async {
    final entries = entriesFor(entry.dateKey)..add(entry);
    await _persist(entry.dateKey, entries);
  }

  Future<void> addAll(List<DiaryEntry> newEntries) async {
    if (newEntries.isEmpty) return;
    final dateKey = newEntries.first.dateKey;
    final entries = entriesFor(dateKey)..addAll(newEntries);
    await _persist(dateKey, entries);
  }

  Future<void> remove(String dateKey, String entryId) async {
    final entries =
        entriesFor(dateKey).where((e) => e.id != entryId).toList();
    await _persist(dateKey, entries);
    await enqueueDeletion(entryId); // so the delete syncs as a tombstone
  }

  Future<void> update(DiaryEntry entry) async {
    final entries = entriesFor(entry.dateKey)
        .map((e) => e.id == entry.id ? entry : e)
        .toList();
    await _persist(entry.dateKey, entries);
  }

  Future<void> _persist(String dateKey, List<DiaryEntry> entries) =>
      _prefs.setString(
        _entriesKey(dateKey),
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );

  // ── Bulk access (sync push) ──────────────────────────────────────
  static const _entriesPrefix = 'diary.v1.';
  static const _waterPrefix = 'water.v1.';

  List<DiaryEntry> allEntries() {
    final out = <DiaryEntry>[];
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_entriesPrefix)) {
        out.addAll(entriesFor(key.substring(_entriesPrefix.length)));
      }
    }
    return out;
  }

  /// Date keys (yyyy-MM-dd) that have at least one entry — for streak math.
  Set<String> loggedDateKeys() {
    final out = <String>{};
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_entriesPrefix)) {
        if (entriesFor(key.substring(_entriesPrefix.length)).isNotEmpty) {
          out.add(key.substring(_entriesPrefix.length));
        }
      }
    }
    return out;
  }

  /// All water tallies as (dateKey, ml), for pushing the full set.
  List<(String, int)> allWater() {
    final out = <(String, int)>[];
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_waterPrefix)) {
        final dateKey = key.substring(_waterPrefix.length);
        out.add((dateKey, _prefs.getInt(key) ?? 0));
      }
    }
    return out;
  }

  /// Upsert a single entry (used when applying pulled changes). Targets the
  /// entry's own date bucket.
  Future<void> upsertEntry(DiaryEntry entry) async {
    final entries = entriesFor(entry.dateKey);
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      entries[i] = entry;
    } else {
      entries.add(entry);
    }
    await _persist(entry.dateKey, entries);
  }

  /// Remove by id without enqueuing a tombstone (server already knows).
  Future<void> applyRemoteDeletion(String dateKey, String entryId) async {
    final entries =
        entriesFor(dateKey).where((e) => e.id != entryId).toList();
    await _persist(dateKey, entries);
  }

  // ── Pending deletions (offline tombstones awaiting push) ──────────
  static const _deletionsKey = 'diary.deletions.v1';

  Set<String> pendingDeletions() =>
      (_prefs.getStringList(_deletionsKey) ?? const []).toSet();

  Future<void> enqueueDeletion(String entryId) async {
    final set = pendingDeletions()..add(entryId);
    await _prefs.setStringList(_deletionsKey, set.toList());
  }

  Future<void> clearDeletions(Iterable<String> ids) async {
    final set = pendingDeletions()..removeAll(ids);
    await _prefs.setStringList(_deletionsKey, set.toList());
  }

  // ── Water ────────────────────────────────────────────────────────
  String _waterKey(String dateKey) => 'water.v1.$dateKey';

  int waterMl(String dateKey) => _prefs.getInt(_waterKey(dateKey)) ?? 0;

  Future<void> setWaterMl(String dateKey, int ml) =>
      _prefs.setInt(_waterKey(dateKey), ml < 0 ? 0 : ml);

  // ── Water vessels (user's own glasses/bottles for one-tap logging) ─
  static const _vesselsKey = 'water.vessels.v1';
  static const defaultVessels = [
    WaterVessel(label: 'Glass', ml: 250),
    WaterVessel(label: 'Bottle', ml: 500),
  ];

  List<WaterVessel> vessels() {
    final raw = _prefs.getString(_vesselsKey);
    if (raw == null) return List.of(defaultVessels);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => WaterVessel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveVessels(List<WaterVessel> vessels) => _prefs.setString(
      _vesselsKey, jsonEncode(vessels.map((v) => v.toJson()).toList()));

  // ── Weight ───────────────────────────────────────────────────────
  static const _weightsKey = 'weights.v1';

  /// Returns (dateKey, kg) pairs, oldest first.
  List<(String, double)> weightLogs() {
    final raw = _prefs.getString(_weightsKey);
    if (raw == null) return [];
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final logs = map.entries
        .map((e) => (e.key, (e.value as num).toDouble()))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return logs;
  }

  Future<void> logWeight(String dateKey, double kg) async {
    final raw = _prefs.getString(_weightsKey);
    final map = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    map[dateKey] = kg;
    await _prefs.setString(_weightsKey, jsonEncode(map));
  }
}

/// A named pour size — "My bottle = 750 ml" — for one-tap water logging.
class WaterVessel {
  const WaterVessel({required this.label, required this.ml});

  final String label;
  final int ml;

  String get emoji => ml < 300 ? '🥤' : (ml < 700 ? '🍶' : '🫙');

  Map<String, dynamic> toJson() => {'label': label, 'ml': ml};

  factory WaterVessel.fromJson(Map<String, dynamic> json) =>
      WaterVessel(label: json['label'] as String, ml: json['ml'] as int);
}

/// 'yyyy-MM-dd' for a local date.
String dateKeyOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
