import 'package:uuid/uuid.dart';

import 'diary_entry.dart';
import 'food.dart';
import 'nutrition_facts.dart';

const _uuid = Uuid();

/// A starred food the user can re-log in one tap. Carries the per-100g snapshot
/// plus a default portion, so re-logging needs no database lookup. Matches the
/// backend `favorites` table (see Favorite::toClientArray) for sync.
class Favorite {
  const Favorite({
    required this.id,
    required this.foodName,
    required this.per100g,
    required this.defaultGrams,
    this.emoji = '🍽️',
    this.portionLabel,
    this.hydrationFactor,
    this.source = 'search',
  });

  final String id;
  final String foodName;
  final NutritionFacts per100g;
  final double defaultGrams;
  final String emoji;
  final String? portionLabel;
  final double? hydrationFactor;
  final String source;

  factory Favorite.fromFood(Food food) => Favorite(
        id: _uuid.v4(),
        foodName: food.name,
        per100g: food.per100g,
        defaultGrams: food.defaultGrams,
        emoji: food.emoji,
        portionLabel: food.defaultPortionLabel,
        hydrationFactor: food.hydrationFactor,
        source: 'search',
      );

  factory Favorite.fromEntry(DiaryEntry e) => Favorite(
        id: _uuid.v4(),
        foodName: e.foodName,
        per100g: e.per100g,
        defaultGrams: e.grams,
        emoji: e.emoji,
        portionLabel: e.portionLabel,
        hydrationFactor: e.grams > 0 && e.hydrationMl > 0
            ? e.hydrationMl / e.grams
            : null,
        source: e.source.name,
      );

  /// Build a fresh diary entry for [meal] today from this favorite.
  DiaryEntry toEntry(Meal meal, String dateKey) => DiaryEntry(
        id: _uuid.v4(),
        dateKey: dateKey,
        meal: meal,
        foodName: foodName,
        grams: defaultGrams,
        nutrition: per100g.forGrams(defaultGrams),
        source: EntrySource.quick,
        loggedAt: DateTime.now(),
        emoji: emoji,
        portionLabel: portionLabel,
        hydrationMl: defaultGrams * (hydrationFactor ?? 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'food_name': foodName,
        'emoji': emoji,
        'default_grams': defaultGrams,
        'portion_label': portionLabel,
        'per_100g': per100g.toJson(),
        'hydration_factor': hydrationFactor,
        'source': source,
      };

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        id: j['id'] as String,
        foodName: j['food_name'] as String,
        per100g: NutritionFacts.fromJson(j['per_100g'] as Map<String, dynamic>),
        defaultGrams: (j['default_grams'] as num?)?.toDouble() ?? 100,
        emoji: (j['emoji'] as String?)?.isNotEmpty == true
            ? j['emoji'] as String
            : '🍽️',
        portionLabel: j['portion_label'] as String?,
        hydrationFactor: (j['hydration_factor'] as num?)?.toDouble(),
        source: j['source'] as String? ?? 'search',
      );
}
