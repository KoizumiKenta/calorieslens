import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_result.freezed.dart';
part 'scan_result.g.dart';

/// Domain entities for the scan review flow. Pure Dart — no Flutter imports.
/// Totals are recomputed locally on every edit (<100 ms budget) from cached
/// per-100g values; the server PATCH happens in the background.
@freezed
class ScanResult with _$ScanResult {
  const ScanResult._();

  const factory ScanResult({
    required String id,
    required List<ScanItem> items,
    required double totalKcal,
    required ({double low, double high}) kcalRange,
    required double confidence,
    required String reasoning,
  }) = _ScanResult;

  factory ScanResult.fromJson(Map<String, dynamic> json) => _$ScanResultFromJson(json);

  /// Items the user actually edits: leaves of composite trees + standalone items.
  List<ScanItem> get editableItems =>
      items.where((i) => !items.any((c) => c.componentOf == i.id)).toList();

  ScanResult withItemEdited(ScanItem edited) {
    final updated = items.map((i) => i.id == edited.id ? edited : i).toList();
    final active = updated.where((i) => !i.removed);
    return copyWith(
      items: updated,
      totalKcal: active.fold(0.0, (sum, i) => sum + i.nutrition.kcal),
    );
  }
}

@freezed
class ScanItem with _$ScanItem {
  const ScanItem._();

  const factory ScanItem({
    required String id,
    required String label,
    String? foodItemId,
    String? componentOf,
    required double grams,
    required ({double low, double high}) gramsRange,
    String? servingLabel,
    String? cookingMethod,
    required NutritionFacts nutrition,
    required NutritionFacts per100g,
    required double confidence,
    double? portionConfidence,
    required String reasoning,
    List<double>? bbox,
    @Default(false) bool removed,
  }) = _ScanItem;

  factory ScanItem.fromJson(Map<String, dynamic> json) => _$ScanItemFromJson(json);

  ConfidenceBand get band => switch (confidence) {
        >= 0.90 => ConfidenceBand.high,
        >= 0.70 => ConfidenceBand.medium,
        _ => ConfidenceBand.low,
      };

  /// Instant local recompute when the user drags the portion slider.
  ScanItem withGrams(double newGrams) => copyWith(
        grams: newGrams,
        nutrition: per100g.scaled(newGrams / 100),
      );
}

/// high → plain number; medium → show range; low → "check this" prompt.
/// (Honest-numbers principle, docs/01-prd.md §6.)
enum ConfidenceBand { high, medium, low }

@freezed
class NutritionFacts with _$NutritionFacts {
  const NutritionFacts._();

  const factory NutritionFacts({
    required double kcal,
    @Default(0) double proteinG,
    @Default(0) double carbsG,
    @Default(0) double fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
  }) = _NutritionFacts;

  factory NutritionFacts.fromJson(Map<String, dynamic> json) => _$NutritionFactsFromJson(json);

  NutritionFacts scaled(double factor) => NutritionFacts(
        kcal: kcal * factor,
        proteinG: proteinG * factor,
        carbsG: carbsG * factor,
        fatG: fatG * factor,
        fiberG: fiberG == null ? null : fiberG! * factor,
        sugarG: sugarG == null ? null : sugarG! * factor,
        sodiumMg: sodiumMg == null ? null : sodiumMg! * factor,
      );
}
