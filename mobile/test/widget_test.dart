import 'package:calorielens/app/theme.dart';
import 'package:calorielens/core/data/food_database.dart';
import 'package:calorielens/core/models/diary_entry.dart';
import 'package:calorielens/core/models/nutrition_facts.dart';
import 'package:calorielens/core/models/scan.dart';
import 'package:calorielens/core/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile targets', () {
    const profile = UserProfile(
      name: 'Aisyah',
      sex: Sex.female,
      age: 28,
      heightCm: 160,
      weightKg: 65,
      activity: ActivityLevel.light,
      goal: Goal.lose,
    );

    test('BMR follows Mifflin-St Jeor', () {
      // 10*65 + 6.25*160 - 5*28 - 161 = 1349
      expect(profile.bmr, closeTo(1349, 0.5));
    });

    test('kcal target never drops below BMR × 0.85 (ED safeguard)', () {
      const extreme = UserProfile(
        name: 'x',
        sex: Sex.female,
        age: 60,
        heightCm: 145,
        weightKg: 40,
        activity: ActivityLevel.sedentary,
        goal: Goal.lose,
      );
      expect(extreme.kcalTarget, greaterThanOrEqualTo(extreme.bmr * 0.85));
    });

    test('macros add back up to roughly the kcal target', () {
      final kcalFromMacros = profile.proteinTargetG * 4 +
          profile.carbsTargetG * 4 +
          profile.fatTargetG * 9;
      expect(kcalFromMacros, closeTo(profile.kcalTarget, 1));
    });
  });

  group('NutritionFacts', () {
    test('forGrams scales from per-100g basis', () {
      const per100 =
          NutritionFacts(kcal: 200, proteinG: 10, carbsG: 20, fatG: 8);
      final half = per100.forGrams(50);
      expect(half.kcal, 100);
      expect(half.proteinG, 5);
    });
  });

  group('Confidence bands (honest-numbers UX)', () {
    test('thresholds match docs/07-ai-services.md', () {
      expect(bandFor(0.95), ConfidenceBand.high);
      expect(bandFor(0.90), ConfidenceBand.high);
      expect(bandFor(0.89), ConfidenceBand.medium);
      expect(bandFor(0.70), ConfidenceBand.medium);
      expect(bandFor(0.69), ConfidenceBand.low);
    });
  });

  group('FoodDatabase search', () {
    test('finds regional dishes by alias', () {
      final results = FoodDatabase.search('kuey teow');
      expect(results, isNotEmpty);
      expect(results.first.id, 'my-char-kway-teow');
    });

    test('exact name outranks substring matches', () {
      final results = FoodDatabase.search('banana');
      expect(results.first.id, 'banana');
    });

    test('empty query returns nothing', () {
      expect(FoodDatabase.search('  '), isEmpty);
    });
  });

  group('DiaryEntry editing', () {
    final entry = DiaryEntry(
      id: 'e1',
      dateKey: '2026-06-12',
      meal: Meal.breakfast,
      foodName: 'Nasi Lemak',
      grams: 330,
      nutrition: const NutritionFacts(
          kcal: 620, proteinG: 19.8, carbsG: 72.6, fatG: 28.1),
      source: EntrySource.scan,
      loggedAt: DateTime(2026, 6, 12, 8, 30),
      portionLabel: '1 plate',
    );

    test('per100g recovers the basis from the snapshot', () {
      expect(entry.per100g.kcal, closeTo(620 / 3.3, 0.01));
    });

    test('halving grams halves nutrition and drops stale portion label', () {
      final updated = entry.copyWith(
        grams: 165,
        nutrition: entry.per100g.forGrams(165),
        clearPortionLabel: true,
      );
      expect(updated.nutrition.kcal, closeTo(310, 0.1));
      expect(updated.portionLabel, isNull);
      expect(updated.id, entry.id); // identity preserved
    });

    test('moving meal keeps nutrition untouched', () {
      final moved = entry.copyWith(meal: Meal.lunch);
      expect(moved.meal, Meal.lunch);
      expect(moved.nutrition.kcal, entry.nutrition.kcal);
      expect(moved.portionLabel, '1 plate');
    });
  });

  group('Hydration credit', () {
    test('drinks in the database carry a hydration factor', () {
      final teh = FoodDatabase.byId('my-teh-tarik')!;
      expect(teh.hydrationFactor, 0.9);
      // 250 g glass → 225 ml hydration
      expect(250 * teh.hydrationFactor!, 225);
      // Solid food contributes nothing
      expect(FoodDatabase.byId('my-nasi-lemak')!.hydrationFactor, isNull);
    });

    test('scan drink items credit hydration; water counts fully', () {
      ScanItem item({required String label, required bool isDrink}) =>
          ScanItem(
            id: 'x',
            label: label,
            grams: 300,
            gramsLow: 250,
            gramsHigh: 350,
            confidence: 0.9,
            reasoning: '',
            per100g: NutritionFacts.zero,
            isDrink: isDrink,
          );
      expect(item(label: 'Milo Ais', isDrink: true).hydrationMl,
          closeTo(264, 0.1)); // 300 × 0.88
      expect(item(label: 'Iced Water', isDrink: true).hydrationMl, 300);
      expect(item(label: 'Fried Rice', isDrink: false).hydrationMl, 0);
    });

    test('entry hydration rescales with grams edits', () {
      final entry = DiaryEntry(
        id: 'd1',
        dateKey: '2026-06-12',
        meal: Meal.breakfast,
        foodName: 'Teh Tarik',
        grams: 250,
        nutrition: const NutritionFacts(
            kcal: 162, proteinG: 3.75, carbsG: 26.25, fatG: 4.5),
        source: EntrySource.search,
        loggedAt: DateTime(2026, 6, 12),
        hydrationMl: 225,
      );
      final doubled = entry.copyWith(grams: 500);
      expect(doubled.hydrationMl, closeTo(450, 0.1));
      // JSON round-trip preserves it
      final reloaded = DiaryEntry.fromJson(doubled.toJson());
      expect(reloaded.hydrationMl, closeTo(450, 0.1));
    });
  });

  test('theme builds both brightness modes', () {
    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().useMaterial3, isTrue);
  });
}
