import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/live_scan_service.dart';
import '../data/repositories.dart';
import '../data/scan_service.dart';
import '../models/diary_entry.dart';
import '../models/nutrition_facts.dart';
import '../models/user_profile.dart';
import '../sync/sync_engine.dart';

/// Overridden with the real instance in main() before runApp.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final profileRepoProvider =
    Provider((ref) => ProfileRepository(ref.watch(sharedPrefsProvider)));

final diaryRepoProvider =
    Provider((ref) => DiaryRepository(ref.watch(sharedPrefsProvider)));

/// Real AI via /api/analyze (webapi/server.php → Claude vision); the mock
/// is the visible fallback when the live path is unavailable.
final scanServiceProvider =
    Provider<ScanService>((ref) => LiveScanService(fallback: MockScanService()));

// ── Profile ──────────────────────────────────────────────────────────
class ProfileNotifier extends Notifier<UserProfile?> {
  @override
  UserProfile? build() => ref.read(profileRepoProvider).load();

  Future<void> save(UserProfile profile) async {
    state = profile;
    await ref.read(profileRepoProvider).save(profile);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }

  Future<void> reset() async {
    state = null;
    await ref.read(profileRepoProvider).clear();
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, UserProfile?>(ProfileNotifier.new);

// ── Selected diary date ─────────────────────────────────────────────
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

// ── Diary entries for a date ────────────────────────────────────────
class DiaryNotifier extends FamilyNotifier<List<DiaryEntry>, String> {
  @override
  List<DiaryEntry> build(String dateKey) =>
      ref.read(diaryRepoProvider).entriesFor(dateKey);

  Future<void> add(DiaryEntry entry) async {
    state = [...state, entry];
    await ref.read(diaryRepoProvider).add(entry);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }

  Future<void> addAll(List<DiaryEntry> entries) async {
    state = [...state, ...entries];
    await ref.read(diaryRepoProvider).addAll(entries);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }

  Future<void> remove(String entryId) async {
    state = state.where((e) => e.id != entryId).toList();
    await ref.read(diaryRepoProvider).remove(arg, entryId);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }

  Future<void> update(DiaryEntry entry) async {
    state = [for (final e in state) e.id == entry.id ? entry : e];
    await ref.read(diaryRepoProvider).update(entry);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }
}

final diaryProvider =
    NotifierProvider.family<DiaryNotifier, List<DiaryEntry>, String>(
        DiaryNotifier.new);

/// Day totals derived from entries.
final dayTotalsProvider = Provider.family<NutritionFacts, String>((ref, dateKey) {
  final entries = ref.watch(diaryProvider(dateKey));
  return entries.fold(NutritionFacts.zero, (sum, e) => sum + e.nutrition);
});

/// Consecutive-day logging streak ending today (or yesterday, so the streak
/// isn't shown as broken before today's first log). 0 means no active streak.
/// Watches today's diary so it recomputes the moment a meal is logged.
final streakProvider = Provider<int>((ref) {
  final today = DateTime.now();
  ref.watch(diaryProvider(dateKeyOf(today))); // recompute on today's edits
  final logged = ref.read(diaryRepoProvider).loggedDateKeys();
  if (logged.isEmpty) return 0;

  // Anchor on today if logged, else yesterday — a fresh day shouldn't read 0
  // until you've eaten.
  var cursor = DateTime(today.year, today.month, today.day);
  if (!logged.contains(dateKeyOf(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!logged.contains(dateKeyOf(cursor))) return 0;
  }

  var streak = 0;
  while (logged.contains(dateKeyOf(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
});

// ── Water ────────────────────────────────────────────────────────────
class WaterNotifier extends FamilyNotifier<int, String> {
  @override
  int build(String dateKey) => ref.read(diaryRepoProvider).waterMl(dateKey);

  Future<void> adjust(int deltaMl) async {
    state = (state + deltaMl).clamp(0, 10000);
    await ref.read(diaryRepoProvider).setWaterMl(arg, state);
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }
}

final waterProvider =
    NotifierProvider.family<WaterNotifier, int, String>(WaterNotifier.new);

/// Hydration credited from drinks logged in the diary (teh tarik, milo…).
final drinksHydrationProvider = Provider.family<double, String>((ref, dateKey) {
  final entries = ref.watch(diaryProvider(dateKey));
  return entries.fold(0.0, (sum, e) => sum + e.hydrationMl);
});

// ── Water vessels ────────────────────────────────────────────────────
class VesselsNotifier extends Notifier<List<WaterVessel>> {
  @override
  List<WaterVessel> build() => ref.read(diaryRepoProvider).vessels();

  Future<void> add(String label, int ml) async {
    state = [...state, WaterVessel(label: label, ml: ml)];
    await ref.read(diaryRepoProvider).saveVessels(state);
  }

  Future<void> removeAt(int index) async {
    state = [...state]..removeAt(index);
    await ref.read(diaryRepoProvider).saveVessels(state);
  }
}

final vesselsProvider =
    NotifierProvider<VesselsNotifier, List<WaterVessel>>(VesselsNotifier.new);

// ── Weight ───────────────────────────────────────────────────────────
class WeightLogNotifier extends Notifier<List<(String, double)>> {
  @override
  List<(String, double)> build() => ref.read(diaryRepoProvider).weightLogs();

  Future<void> log(double kg) async {
    final key = dateKeyOf(DateTime.now());
    await ref.read(diaryRepoProvider).logWeight(key, kg);
    state = ref.read(diaryRepoProvider).weightLogs();
    // Keep the profile's weight (and therefore targets) in sync.
    final profile = ref.read(profileProvider);
    if (profile != null) {
      await ref.read(profileProvider.notifier).save(profile.copyWith(weightKg: kg));
    }
    ref.read(syncEngineProvider.notifier).scheduleSync();
  }
}

final weightLogProvider =
    NotifierProvider<WeightLogNotifier, List<(String, double)>>(
        WeightLogNotifier.new);
