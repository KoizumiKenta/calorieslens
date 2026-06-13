import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/nutrition_facts.dart';
import '../models/scan.dart';

/// Contract for photo → analysis. The real implementation POSTs to
/// /v1/scans and long-polls/streams the result (see docs/04-api). The mock
/// returns realistic decompositions so the entire review→correct→log UX is
/// exercisable with no backend and no API key.
abstract class ScanService {
  /// [note] is optional user context sent with the photo ("milo kosong,
  /// chicken is air-fried") — the model trusts it over visual assumptions.
  Future<ScanAnalysis> analyzePhoto(Uint8List imageBytes, {String? note});

  /// Re-derive one item's identity and nutrition from the user's correction.
  Future<ScanItem> refineItem(ScanItem item, String note);
}

class MockScanService implements ScanService {
  MockScanService({Random? random}) : _random = random ?? Random();

  final Random _random;
  static const _uuid = Uuid();
  int _cursor = 0;

  @override
  Future<ScanAnalysis> analyzePhoto(Uint8List imageBytes, {String? note}) async {
    // Simulate the p95 ≤ 6s pipeline budget at its happy median (~2.5s).
    await Future<void>.delayed(
        Duration(milliseconds: 1800 + _random.nextInt(1400)));

    // Rotate through canned analyses so repeat demos show variety.
    final analysis = _canned[_cursor % _canned.length];
    _cursor++;
    return analysis();
  }

  @override
  Future<ScanItem> refineItem(ScanItem item, String note) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // Offline: relabel honestly but leave nutrition untouched — never
    // invent numbers without a model behind them.
    final label = note.length > 48 ? '${note.substring(0, 48)}…' : note;
    return ScanItem(
      id: item.id,
      label: label[0].toUpperCase() + label.substring(1),
      grams: item.grams,
      gramsLow: item.gramsLow,
      gramsHigh: item.gramsHigh,
      confidence: item.confidence,
      reasoning:
          'Renamed from your note (offline mode — nutrition unchanged until live AI is available).',
      per100g: item.per100g,
      emoji: item.emoji,
      removed: item.removed,
      isDrink: item.isDrink,
    );
  }

  static ScanItem _item({
    required String label,
    required double grams,
    required double low,
    required double high,
    required double confidence,
    required String reasoning,
    required NutritionFacts per100g,
    String emoji = '🍽️',
  }) =>
      ScanItem(
        id: _uuid.v4(),
        label: label,
        grams: grams,
        gramsLow: low,
        gramsHigh: high,
        confidence: confidence,
        reasoning: reasoning,
        per100g: per100g,
        emoji: emoji,
      );

  /// The flagship demo: mixed-dish decomposition, the thing competitors
  /// can't do. Component nutrition from the seeded regional database.
  static final List<ScanAnalysis Function()> _canned = [
    () => ScanAnalysis(
          dishName: 'Nasi Lemak',
          overallNote:
              'Detected nasi lemak — broke it into 7 components. The sambal portion is the biggest uncertainty.',
          items: [
            _item(
              label: 'Coconut rice',
              grams: 180,
              low: 150,
              high: 215,
              confidence: 0.93,
              reasoning:
                  'Rice mound covers about a third of a standard 26 cm plate at typical height. Glossy grains indicate santan (coconut milk) preparation.',
              per100g: const NutritionFacts(
                  kcal: 175, proteinG: 2.8, carbsG: 26.0, fatG: 6.5),
              emoji: '🍚',
            ),
            _item(
              label: 'Sambal',
              grams: 45,
              low: 30,
              high: 65,
              confidence: 0.74,
              reasoning:
                  'Sambal spread is partly under the rice so the true amount is uncertain. Oil sheen suggests a richer hawker-style sambal — counted toward the higher end.',
              per100g: const NutritionFacts(
                  kcal: 145, proteinG: 2.5, carbsG: 14.0, fatG: 9.0, sodiumMg: 850),
              emoji: '🌶️',
            ),
            _item(
              label: 'Fried egg',
              grams: 55,
              low: 50,
              high: 62,
              confidence: 0.96,
              reasoning:
                  'One whole fried egg, standard large size. Crispy edges indicate shallow-fried in oil rather than boiled.',
              per100g: const NutritionFacts(
                  kcal: 196, proteinG: 13.6, carbsG: 0.8, fatG: 15.0),
              emoji: '🍳',
            ),
            _item(
              label: 'Fried anchovies (ikan bilis)',
              grams: 20,
              low: 12,
              high: 30,
              confidence: 0.81,
              reasoning:
                  'Small pile beside the rice. Counted roughly 18–25 anchovies; assumed fried crisp in oil.',
              per100g: const NutritionFacts(
                  kcal: 350, proteinG: 45.0, carbsG: 2.0, fatG: 18.0, sodiumMg: 1100),
              emoji: '🐟',
            ),
            _item(
              label: 'Roasted peanuts',
              grams: 15,
              low: 10,
              high: 22,
              confidence: 0.84,
              reasoning:
                  'Small scatter of peanuts, about a tablespoon and a half.',
              per100g: const NutritionFacts(
                  kcal: 585, proteinG: 24.0, carbsG: 21.0, fatG: 50.0),
              emoji: '🥜',
            ),
            _item(
              label: 'Cucumber slices',
              grams: 30,
              low: 22,
              high: 40,
              confidence: 0.95,
              reasoning: 'Four thin cucumber slices fanned at the plate edge.',
              per100g: const NutritionFacts(
                  kcal: 15, proteinG: 0.7, carbsG: 3.6, fatG: 0.1),
              emoji: '🥒',
            ),
            _item(
              label: 'Fried chicken (ayam goreng)',
              grams: 110,
              low: 85,
              high: 140,
              confidence: 0.88,
              reasoning:
                  'One thigh-size piece with visible batter. Bone-in assumed — edible portion estimated at ~75% of visual volume.',
              per100g: const NutritionFacts(
                  kcal: 260, proteinG: 22.0, carbsG: 6.0, fatG: 16.0, sodiumMg: 420),
              emoji: '🍗',
            ),
          ],
        ),
    () => ScanAnalysis(
          dishName: 'Chicken Rice',
          overallNote:
              'Looks like Hainanese chicken rice with soup. Skin-on roasted chicken raises the fat estimate.',
          items: [
            _item(
              label: 'Seasoned rice',
              grams: 200,
              low: 170,
              high: 235,
              confidence: 0.92,
              reasoning:
                  'Oiled rice with visible sheen, standard hawker scoop ×2 by mound size.',
              per100g: const NutritionFacts(
                  kcal: 160, proteinG: 2.9, carbsG: 27.0, fatG: 4.5, sodiumMg: 320),
              emoji: '🍚',
            ),
            _item(
              label: 'Roasted chicken (skin on)',
              grams: 130,
              low: 100,
              high: 165,
              confidence: 0.85,
              reasoning:
                  'Sliced chicken covering a quarter of the plate, skin visible on most slices. Estimated 8–10 slices at ~15 g each.',
              per100g: const NutritionFacts(
                  kcal: 215, proteinG: 24.0, carbsG: 0.5, fatG: 13.0, sodiumMg: 380),
              emoji: '🍗',
            ),
            _item(
              label: 'Cucumber garnish',
              grams: 25,
              low: 18,
              high: 35,
              confidence: 0.94,
              reasoning: 'Cucumber slices under the chicken.',
              per100g: const NutritionFacts(
                  kcal: 15, proteinG: 0.7, carbsG: 3.6, fatG: 0.1),
              emoji: '🥒',
            ),
            _item(
              label: 'Chilli-ginger sauce',
              grams: 20,
              low: 10,
              high: 35,
              confidence: 0.68,
              reasoning:
                  'Small sauce dish partially visible at frame edge — amount is a guess. Tap to adjust if you used more or less.',
              per100g: const NutritionFacts(
                  kcal: 95, proteinG: 1.5, carbsG: 12.0, fatG: 4.5, sodiumMg: 900),
              emoji: '🌶️',
            ),
          ],
        ),
    () => ScanAnalysis(
          dishName: 'Western Breakfast',
          overallNote:
              'Classic big breakfast. Butter on the toast is assumed — remove it if yours was dry.',
          items: [
            _item(
              label: 'Scrambled eggs',
              grams: 120,
              low: 95,
              high: 150,
              confidence: 0.91,
              reasoning:
                  'Egg portion equivalent to 2 large eggs with milk/butter, by volume against the fork beside the plate (19 cm reference).',
              per100g: const NutritionFacts(
                  kcal: 149, proteinG: 10.0, carbsG: 1.6, fatG: 11.0),
              emoji: '🍳',
            ),
            _item(
              label: 'Toast with butter',
              grams: 70,
              low: 60,
              high: 85,
              confidence: 0.89,
              reasoning:
                  'Two slices of white toast, visible butter sheen (~7 g assumed).',
              per100g: const NutritionFacts(
                  kcal: 310, proteinG: 8.0, carbsG: 44.0, fatG: 11.0, sugarG: 5.0),
              emoji: '🍞',
            ),
            _item(
              label: 'Chicken sausages',
              grams: 80,
              low: 65,
              high: 95,
              confidence: 0.87,
              reasoning: 'Two standard breakfast sausages, ~40 g each.',
              per100g: const NutritionFacts(
                  kcal: 220, proteinG: 12.0, carbsG: 4.0, fatG: 17.0, sodiumMg: 680),
              emoji: '🌭',
            ),
            _item(
              label: 'Baked beans',
              grams: 90,
              low: 70,
              high: 115,
              confidence: 0.90,
              reasoning: 'Half-ladle of baked beans in tomato sauce.',
              per100g: const NutritionFacts(
                  kcal: 94, proteinG: 4.7, carbsG: 17.0, fatG: 0.5, fiberG: 3.7, sugarG: 5.0),
              emoji: '🫘',
            ),
          ],
        ),
  ];
}
