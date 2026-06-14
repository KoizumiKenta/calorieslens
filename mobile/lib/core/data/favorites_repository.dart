import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite.dart';

/// Local store for starred foods. Offline-first like the diary: edits persist
/// immediately and the sync engine pushes them (and pulls others') keyed on the
/// favorite's UUID. Deletes ride along as tombstones.
class FavoritesRepository {
  FavoritesRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'favorites.v1';
  static const _deletionsKey = 'favorites.deletions.v1';

  List<Favorite> all() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => Favorite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  bool isFavorite(String foodName) =>
      all().any((f) => f.foodName.toLowerCase() == foodName.toLowerCase());

  Future<void> _persist(List<Favorite> favs) =>
      _prefs.setString(_key, jsonEncode(favs.map((f) => f.toJson()).toList()));

  /// Add unless a favorite with the same name already exists.
  Future<void> add(Favorite fav) async {
    final favs = all();
    if (favs.any((f) => f.foodName.toLowerCase() == fav.foodName.toLowerCase())) {
      return;
    }
    favs.insert(0, fav);
    await _persist(favs);
  }

  Future<void> removeById(String id) async {
    await _persist(all().where((f) => f.id != id).toList());
    await enqueueDeletion(id);
  }

  /// Remove every favorite matching a food name (for un-starring by name).
  Future<void> removeByName(String foodName) async {
    final favs = all();
    final gone = favs
        .where((f) => f.foodName.toLowerCase() == foodName.toLowerCase())
        .map((f) => f.id)
        .toList();
    if (gone.isEmpty) return;
    await _persist(favs
        .where((f) => f.foodName.toLowerCase() != foodName.toLowerCase())
        .toList());
    for (final id in gone) {
      await enqueueDeletion(id);
    }
  }

  // ── Sync ───────────────────────────────────────────────────────────
  List<Favorite> allForSync() => all();

  Future<void> upsert(Favorite fav) async {
    final favs = all();
    final i = favs.indexWhere((f) => f.id == fav.id);
    if (i >= 0) {
      favs[i] = fav;
    } else {
      favs.add(fav);
    }
    await _persist(favs);
  }

  Future<void> applyRemoteDeletion(String id) async {
    await _persist(all().where((f) => f.id != id).toList());
  }

  Set<String> pendingDeletions() =>
      (_prefs.getStringList(_deletionsKey) ?? const []).toSet();

  Future<void> enqueueDeletion(String id) async {
    final set = pendingDeletions()..add(id);
    await _prefs.setStringList(_deletionsKey, set.toList());
  }

  Future<void> clearDeletions(Iterable<String> ids) async {
    final set = pendingDeletions()..removeAll(ids);
    await _prefs.setStringList(_deletionsKey, set.toList());
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_deletionsKey);
  }
}
