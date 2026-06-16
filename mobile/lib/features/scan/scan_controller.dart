import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/repositories.dart';
import '../../core/models/diary_entry.dart';
import '../../core/models/scan.dart';
import '../../core/state/providers.dart';

class ScanState {
  const ScanState({
    this.imageBytes,
    this.analysis,
    this.analyzing = false,
    this.error,
  });

  final Uint8List? imageBytes;
  final ScanAnalysis? analysis;
  final bool analyzing;
  final String? error;

  ScanState copyWith({
    Uint8List? imageBytes,
    ScanAnalysis? analysis,
    bool? analyzing,
    String? error,
    bool clearAnalysis = false,
    bool clearError = false,
  }) =>
      ScanState(
        imageBytes: imageBytes ?? this.imageBytes,
        analysis: clearAnalysis ? null : (analysis ?? this.analysis),
        analyzing: analyzing ?? this.analyzing,
        error: clearError ? null : (error ?? this.error),
      );
}

class ScanController extends Notifier<ScanState> {
  static const _uuid = Uuid();

  @override
  ScanState build() => const ScanState();

  void setImage(Uint8List bytes) {
    state = ScanState(imageBytes: bytes);
  }

  void reset() => state = const ScanState();

  Future<bool> analyze({String? note}) async {
    final bytes = state.imageBytes;
    if (bytes == null) return false;
    state = state.copyWith(analyzing: true, clearError: true, clearAnalysis: true);
    try {
      final analysis =
          await ref.read(scanServiceProvider).analyzePhoto(bytes, note: note);
      state = state.copyWith(analyzing: false, analysis: analysis);
      return true;
    } catch (e) {
      state = state.copyWith(
        analyzing: false,
        error: 'Could not analyze the photo. Check your connection and try again.',
      );
      return false;
    }
  }

  /// "This is actually air-fried chicken breast" → AI re-derives the item.
  /// Returns null on success, or a user-facing error message.
  Future<String?> refineItem(String itemId, String note) async {
    final analysis = state.analysis;
    if (analysis == null) return 'Nothing to refine.';
    final ScanItem item;
    try {
      item = analysis.items.firstWhere((i) => i.id == itemId);
    } catch (_) {
      return 'Item not found.';
    }

    try {
      final updated =
          await ref.read(scanServiceProvider).refineItem(item, note.trim());
      // Re-read state: the user may have edited other items meanwhile.
      final current = state.analysis;
      if (current == null) return null;
      state = state.copyWith(
        analysis: current.copyWithItems([
          for (final i in current.items)
            if (i.id == itemId) updated else i,
        ]),
      );
      return null;
    } catch (e) {
      return 'Could not update the item: $e';
    }
  }

  void updateGrams(String itemId, double grams) {
    final analysis = state.analysis;
    if (analysis == null) return;
    state = state.copyWith(
      analysis: analysis.copyWithItems([
        for (final item in analysis.items)
          if (item.id == itemId) item.withGrams(grams) else item,
      ]),
    );
  }

  void setRemoved(String itemId, bool removed) {
    final analysis = state.analysis;
    if (analysis == null) return;
    state = state.copyWith(
      analysis: analysis.copyWithItems([
        for (final item in analysis.items)
          if (item.id == itemId) item.withRemoved(removed) else item,
      ]),
    );
  }

  /// Writes one diary entry per active item (decomposed logging — users can
  /// later delete just the sambal, not the whole meal).
  Future<int> logToDiary(Meal meal) async {
    final analysis = state.analysis;
    if (analysis == null) return 0;
    final now = DateTime.now();
    // Respect the diary's selected day so scans can be logged for tomorrow's
    // meal prep, not just today.
    final dateKey = dateKeyOf(ref.read(selectedDateProvider));

    final entries = [
      for (final item in analysis.activeItems)
        DiaryEntry(
          id: _uuid.v4(),
          dateKey: dateKey,
          meal: meal,
          foodName: item.label,
          grams: item.grams,
          nutrition: item.nutrition,
          source: EntrySource.scan,
          loggedAt: now,
          emoji: item.emoji,
          hydrationMl: item.hydrationMl,
        ),
    ];

    await ref.read(diaryProvider(dateKey).notifier).addAll(entries);
    reset();
    return entries.length;
  }
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanState>(ScanController.new);
