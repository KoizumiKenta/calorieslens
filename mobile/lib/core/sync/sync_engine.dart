import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../auth/auth_repository.dart';
import '../data/repositories.dart';
import '../models/diary_entry.dart';
import '../models/user_profile.dart';
import '../state/providers.dart';

class SyncState {
  const SyncState({this.syncing = false, this.lastSyncedAt, this.error});

  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? error;

  SyncState copyWith({
    bool? syncing,
    DateTime? lastSyncedAt,
    String? error,
    bool clearError = false,
  }) =>
      SyncState(
        syncing: syncing ?? this.syncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Offline-first sync. Push local changes (profile via PUT /profile; diary,
/// water, weights, deletions via POST /sync), then pull everything changed
/// since last sync and merge into the local repositories. The phone is the
/// editor; last-write-wins. No-ops cleanly when signed out.
class SyncEngine extends Notifier<SyncState> {
  static const _lastSyncKey = 'sync.last.v1';

  Timer? _debounce;

  @override
  SyncState build() {
    final raw = ref.read(sharedPrefsProvider).getString(_lastSyncKey);
    ref.onDispose(() => _debounce?.cancel());
    return SyncState(lastSyncedAt: raw == null ? null : DateTime.tryParse(raw));
  }

  /// Coalesce bursts of edits into one sync a couple of seconds later.
  /// No-op when signed out (syncNow checks the token).
  void scheduleSync() {
    if (ref.read(authRepoProvider).token == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  Future<void> reset() async {
    await ref.read(sharedPrefsProvider).remove(_lastSyncKey);
    state = const SyncState();
  }

  Future<void> syncNow({bool initial = false}) async {
    final token = ref.read(authRepoProvider).token;
    if (token == null || state.syncing) return;

    state = state.copyWith(syncing: true, clearError: true);
    final diary = ref.read(diaryRepoProvider);
    final profileRepo = ref.read(profileRepoProvider);

    try {
      await _pushProfile(token, profileRepo);
      await _pushChanges(token, diary);
      // First sync pulls the full set; afterwards only what changed.
      await _pullAndApply(token, diary, profileRepo,
          since: initial ? null : state.lastSyncedAt);

      _invalidateUi();
      state = state.copyWith(syncing: false);
    } catch (e) {
      state = state.copyWith(syncing: false, error: _short(e));
    }
  }

  Future<void> _pushProfile(String token, ProfileRepository repo) async {
    final profile = repo.load();
    if (profile == null) return;
    await http
        .put(ApiConfig.uri('profile'),
            headers: ApiConfig.headers(token: token),
            body: jsonEncode(profile.toJson()))
        .timeout(const Duration(seconds: 20));
  }

  Future<void> _pushChanges(String token, DiaryRepository diary) async {
    final deletions = diary.pendingDeletions().toList();
    final body = {
      'diary_entries': diary.allEntries().map((e) => e.toJson()).toList(),
      'deleted_ids': deletions,
      'water': diary.allWater().map((w) => {'date_key': w.$1, 'ml': w.$2}).toList(),
      'weights':
          diary.weightLogs().map((w) => {'date_key': w.$1, 'kg': w.$2}).toList(),
    };
    final res = await http
        .post(ApiConfig.uri('sync'),
            headers: ApiConfig.headers(token: token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 200) {
      await diary.clearDeletions(deletions);
    } else {
      throw Exception('push failed (${res.statusCode})');
    }
  }

  Future<void> _pullAndApply(
    String token,
    DiaryRepository diary,
    ProfileRepository profileRepo, {
    DateTime? since,
  }) async {
    final res = await http
        .get(
          ApiConfig.uri('sync',
              since == null ? null : {'since': since.toUtc().toIso8601String()}),
          headers: ApiConfig.headers(token: token),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('pull failed (${res.statusCode})');

    final json = jsonDecode(res.body) as Map<String, dynamic>;

    if (json['profile'] is Map<String, dynamic>) {
      await profileRepo.save(
          UserProfile.fromJson(json['profile'] as Map<String, dynamic>));
    }

    for (final raw in (json['diary_entries'] as List? ?? const [])) {
      final e = raw as Map<String, dynamic>;
      if (e['deleted'] == true) {
        await diary.applyRemoteDeletion(e['date_key'] as String, e['id'] as String);
      } else {
        await diary.upsertEntry(DiaryEntry.fromJson(e));
      }
    }

    for (final raw in (json['water'] as List? ?? const [])) {
      final w = raw as Map<String, dynamic>;
      await diary.setWaterMl(w['date_key'] as String, (w['ml'] as num).toInt());
    }

    for (final raw in (json['weights'] as List? ?? const [])) {
      final w = raw as Map<String, dynamic>;
      await diary.logWeight(w['date_key'] as String, (w['kg'] as num).toDouble());
    }

    final serverTime = json['server_time'] as String?;
    final stamp = serverTime != null ? DateTime.parse(serverTime) : DateTime.now();
    await ref.read(sharedPrefsProvider).setString(_lastSyncKey, stamp.toIso8601String());
    state = state.copyWith(lastSyncedAt: stamp);
  }

  /// Rebuild every screen that reads synced data from the repositories.
  void _invalidateUi() {
    ref.invalidate(diaryProvider);
    ref.invalidate(waterProvider);
    ref.invalidate(weightLogProvider);
    ref.invalidate(profileProvider);
  }

  String _short(Object e) {
    final t = e.toString();
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }
}

final syncEngineProvider =
    NotifierProvider<SyncEngine, SyncState>(SyncEngine.new);
