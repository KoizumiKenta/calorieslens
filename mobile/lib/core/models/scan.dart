import 'dart:math' as math;

import 'nutrition_facts.dart';

/// Honest-numbers bands (docs/07-ai-services.md): ≥0.90 show plain value,
/// 0.70–0.89 show range, <0.70 ask the user to check.
enum ConfidenceBand { high, medium, low }

ConfidenceBand bandFor(double confidence) => switch (confidence) {
      >= 0.90 => ConfidenceBand.high,
      >= 0.70 => ConfidenceBand.medium,
      _ => ConfidenceBand.low,
    };

/// One detected food in a scan. Mutable grams via [withGrams] for the
/// optimistic edit loop; nutrition recomputes locally from per-100g.
class ScanItem {
  const ScanItem({
    required this.id,
    required this.label,
    required this.grams,
    required this.gramsLow,
    required this.gramsHigh,
    required this.confidence,
    required this.reasoning,
    required this.per100g,
    this.emoji = '🍽️',
    this.removed = false,
    this.isDrink = false,
  });

  final String id;
  final String label;
  final double grams;
  final double gramsLow;
  final double gramsHigh;
  final double confidence;

  /// Verbatim model reasoning — surfaced via "why this number?" tap.
  final String reasoning;
  final NutritionFacts per100g;
  final String emoji;
  final bool removed;

  /// Beverage flag from the vision model — drives hydration credit.
  final bool isDrink;

  /// Hydration this item contributes when logged (~88% of a drink's weight
  /// is water; plain water counts fully).
  double get hydrationMl => !isDrink
      ? 0
      : grams * (label.toLowerCase().contains('water') ? 1.0 : 0.88);

  ConfidenceBand get band => bandFor(confidence);

  NutritionFacts get nutrition => per100g.forGrams(grams);

  double get kcalLow => per100g.forGrams(gramsLow).kcal;
  double get kcalHigh => per100g.forGrams(gramsHigh).kcal;

  ScanItem withGrams(double newGrams) {
    // Keep the relative spread when the user rescales the portion.
    final ratio = grams == 0 ? 1.0 : newGrams / grams;
    return ScanItem(
      id: id,
      label: label,
      grams: newGrams,
      gramsLow: gramsLow * ratio,
      gramsHigh: gramsHigh * ratio,
      // A user-set portion is ground truth.
      confidence: 0.97,
      reasoning: 'Portion set by you.',
      per100g: per100g,
      emoji: emoji,
      removed: removed,
      isDrink: isDrink,
    );
  }

  ScanItem withRemoved(bool value) => ScanItem(
        id: id,
        label: label,
        grams: grams,
        gramsLow: gramsLow,
        gramsHigh: gramsHigh,
        confidence: confidence,
        reasoning: reasoning,
        per100g: per100g,
        emoji: emoji,
        removed: value,
        isDrink: isDrink,
      );
}

class ScanAnalysis {
  const ScanAnalysis({
    required this.dishName,
    required this.items,
    required this.overallNote,
  });

  final String dishName;
  final List<ScanItem> items;

  /// One-line model summary shown above the item list.
  final String overallNote;

  List<ScanItem> get activeItems =>
      items.where((i) => !i.removed).toList(growable: false);

  NutritionFacts get totals =>
      activeItems.fold(NutritionFacts.zero, (sum, i) => sum + i.nutrition);

  /// Meal-level kcal range: root-sum-square of item spreads, same math as
  /// the backend PortionEstimator (independent errors don't simply add).
  (double, double) get kcalRange {
    final total = totals.kcal;
    double sumSq = 0;
    for (final i in activeItems) {
      final spread = (i.kcalHigh - i.kcalLow) / 2;
      sumSq += spread * spread;
    }
    final halfWidth = math.sqrt(sumSq);
    return (total - halfWidth, total + halfWidth);
  }

  ScanAnalysis copyWithItems(List<ScanItem> newItems) =>
      ScanAnalysis(dishName: dishName, items: newItems, overallNote: overallNote);
}
