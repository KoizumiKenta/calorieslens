import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/scan_repository.dart';
import '../domain/scan_result.dart';

part 'scan_review_controller.g.dart';

/// Drives the scan review screen: skeleton → result → edits → log.
/// Optimistic by design — every edit updates state instantly from cached
/// per-100g data, then PATCHes the server in the background; logging writes
/// to the local diary first and syncs via the mutation queue.
@riverpod
class ScanReviewController extends _$ScanReviewController {
  StreamSubscription<ScanResult>? _resultSub;

  @override
  AsyncValue<ScanResult> build(String scanId) {
    // Primary channel is the scan.ready WebSocket event; the repository
    // falls back to 1 s polling when the socket is down (docs/02 §3).
    _resultSub = ref.read(scanRepositoryProvider).watchResult(scanId).listen(
          (result) => state = AsyncData(result),
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );
    ref.onDispose(() => _resultSub?.cancel());

    return const AsyncLoading(); // skeleton card while AI works
  }

  /// Portion slider drag: recompute locally now, persist correction behind.
  void updateGrams(String itemId, double grams) {
    final result = state.valueOrNull;
    if (result == null) return;

    final item = result.items.firstWhere((i) => i.id == itemId);
    state = AsyncData(result.withItemEdited(item.withGrams(grams)));

    _debouncedPatch(itemId, {'grams': grams});
  }

  void removeItem(String itemId) {
    final result = state.valueOrNull;
    if (result == null) return;

    final item = result.items.firstWhere((i) => i.id == itemId);
    state = AsyncData(result.withItemEdited(item.copyWith(removed: true)));

    unawaited(ref.read(scanRepositoryProvider).patchItem(scanId, itemId, {'removed': true}));
  }

  Future<void> swapFood(String itemId, String foodItemId) async {
    // Food swaps need server-side nutrition resolution — show inline
    // shimmer on the one item, keep the rest of the card interactive.
    final updated = await ref
        .read(scanRepositoryProvider)
        .patchItem(scanId, itemId, {'food_item_id': foodItemId});

    final result = state.valueOrNull;
    if (result != null) state = AsyncData(result.withItemEdited(updated));
  }

  /// Log everything to the diary: local write + mutation queue, instant
  /// navigation back to the diary with the new entries already visible.
  Future<void> logMeal({required String mealSlot, required DateTime entryDate}) async {
    final result = state.valueOrNull;
    if (result == null) return;

    await ref.read(scanRepositoryProvider).logToDiary(
          scanId: scanId,
          result: result,
          mealSlot: mealSlot,
          entryDate: entryDate,
        );
  }

  Timer? _patchDebounce;
  void _debouncedPatch(String itemId, Map<String, dynamic> changes) {
    _patchDebounce?.cancel();
    _patchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(ref.read(scanRepositoryProvider).patchItem(scanId, itemId, changes));
    });
  }
}
