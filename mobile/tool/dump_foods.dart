// Dev tool: serialize the curated food seed to JSON so the Laravel backend
// can import the exact same data. Run: dart run tool/dump_foods.dart
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:calorielens/core/data/food_database.dart';

void main() {
  final list = FoodDatabase.all
      .map((f) => {
            'external_id': f.id,
            'name': f.name,
            'brand': f.brand,
            'region': f.region,
            'emoji': f.emoji,
            'aliases': f.aliases,
            'hydration_factor': f.hydrationFactor,
            'per_100g': {
              'kcal': f.per100g.kcal,
              'protein_g': f.per100g.proteinG,
              'carbs_g': f.per100g.carbsG,
              'fat_g': f.per100g.fatG,
              'fiber_g': f.per100g.fiberG,
              'sugar_g': f.per100g.sugarG,
              'sodium_mg': f.per100g.sodiumMg,
            },
            'portions':
                f.portions.map((p) => {'label': p.label, 'grams': p.grams}).toList(),
          })
      .toList();
  print(const JsonEncoder().convert(list));
}
