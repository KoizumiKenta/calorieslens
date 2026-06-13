/// Immutable macro/micro snapshot. Mirrors backend NutritionFacts VO —
/// diary entries store a copy of this, never a reference, so history is
/// immutable even if the food database changes.
class NutritionFacts {
  const NutritionFacts({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG = 0,
    this.sugarG = 0,
    this.sodiumMg = 0,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;
  final double sodiumMg;

  static const zero = NutritionFacts(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);

  NutritionFacts operator +(NutritionFacts other) => NutritionFacts(
        kcal: kcal + other.kcal,
        proteinG: proteinG + other.proteinG,
        carbsG: carbsG + other.carbsG,
        fatG: fatG + other.fatG,
        fiberG: fiberG + other.fiberG,
        sugarG: sugarG + other.sugarG,
        sodiumMg: sodiumMg + other.sodiumMg,
      );

  NutritionFacts scaled(double factor) => NutritionFacts(
        kcal: kcal * factor,
        proteinG: proteinG * factor,
        carbsG: carbsG * factor,
        fatG: fatG * factor,
        fiberG: fiberG * factor,
        sugarG: sugarG * factor,
        sodiumMg: sodiumMg * factor,
      );

  /// These values are per-100g; return the facts for [grams].
  NutritionFacts forGrams(double grams) => scaled(grams / 100);

  Map<String, dynamic> toJson() => {
        'kcal': kcal,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'sugar_g': sugarG,
        'sodium_mg': sodiumMg,
      };

  factory NutritionFacts.fromJson(Map<String, dynamic> json) => NutritionFacts(
        kcal: (json['kcal'] as num).toDouble(),
        proteinG: (json['protein_g'] as num).toDouble(),
        carbsG: (json['carbs_g'] as num).toDouble(),
        fatG: (json['fat_g'] as num).toDouble(),
        fiberG: (json['fiber_g'] as num? ?? 0).toDouble(),
        sugarG: (json['sugar_g'] as num? ?? 0).toDouble(),
        sodiumMg: (json['sodium_mg'] as num? ?? 0).toDouble(),
      );
}
