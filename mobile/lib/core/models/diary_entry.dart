import 'nutrition_facts.dart';

enum Meal { breakfast, lunch, dinner, snack }

extension MealLabel on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snack => 'Snacks',
      };

  String get emoji => switch (this) {
        Meal.breakfast => '🌅',
        Meal.lunch => '☀️',
        Meal.dinner => '🌙',
        Meal.snack => '🍿',
      };
}

enum EntrySource { scan, search, quick }

/// One logged food. Nutrition is a snapshot taken at log time — editing the
/// food database later never rewrites history (same rule as the backend).
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.dateKey,
    required this.meal,
    required this.foodName,
    required this.grams,
    required this.nutrition,
    required this.source,
    required this.loggedAt,
    this.emoji = '🍽️',
    this.portionLabel,
    this.hydrationMl = 0,
  });

  final String id;

  /// 'yyyy-MM-dd' local date the entry belongs to.
  final String dateKey;
  final Meal meal;
  final String foodName;
  final double grams;
  final NutritionFacts nutrition;
  final EntrySource source;
  final DateTime loggedAt;
  final String emoji;
  final String? portionLabel;

  /// Hydration this entry contributes (ml) — non-zero only for drinks.
  /// Snapshotted at log time like nutrition; rescales with grams edits.
  final double hydrationMl;

  /// Per-100g basis recovered from the snapshot — lets grams edits rescale
  /// nutrition without needing the original food record.
  NutritionFacts get per100g => grams <= 0
      ? NutritionFacts.zero
      : nutrition.scaled(100 / grams);

  DiaryEntry copyWith({
    Meal? meal,
    double? grams,
    NutritionFacts? nutrition,
    String? portionLabel,
    bool clearPortionLabel = false,
  }) {
    final newGrams = grams ?? this.grams;
    // Hydration scales with the portion, same as nutrition.
    final scaledHydration =
        this.grams <= 0 ? hydrationMl : hydrationMl * (newGrams / this.grams);
    return DiaryEntry(
      id: id,
      dateKey: dateKey,
      meal: meal ?? this.meal,
      foodName: foodName,
      grams: newGrams,
      nutrition: nutrition ?? this.nutrition,
      source: source,
      loggedAt: loggedAt,
      emoji: emoji,
      portionLabel:
          clearPortionLabel ? null : (portionLabel ?? this.portionLabel),
      hydrationMl: scaledHydration,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date_key': dateKey,
        'meal': meal.name,
        'food_name': foodName,
        'grams': grams,
        'nutrition': nutrition.toJson(),
        'source': source.name,
        'logged_at': loggedAt.toIso8601String(),
        'emoji': emoji,
        'portion_label': portionLabel,
        'hydration_ml': hydrationMl,
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
        id: json['id'] as String,
        dateKey: json['date_key'] as String,
        meal: Meal.values.byName(json['meal'] as String),
        foodName: json['food_name'] as String,
        grams: (json['grams'] as num).toDouble(),
        nutrition:
            NutritionFacts.fromJson(json['nutrition'] as Map<String, dynamic>),
        source: EntrySource.values.byName(json['source'] as String),
        loggedAt: DateTime.parse(json['logged_at'] as String),
        emoji: json['emoji'] as String? ?? '🍽️',
        portionLabel: json['portion_label'] as String?,
        hydrationMl: (json['hydration_ml'] as num? ?? 0).toDouble(),
      );
}
