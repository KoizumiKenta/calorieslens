import 'nutrition_facts.dart';

/// A named serving size: "1 plate" → 350 g.
class Portion {
  const Portion({required this.label, required this.grams});

  final String label;
  final double grams;

  factory Portion.fromJson(Map<String, dynamic> j) => Portion(
        label: j['label'] as String,
        grams: (j['grams'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'grams': grams};
}

/// An entry in the food database. [per100g] is the canonical basis;
/// portions are display conveniences.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.per100g,
    this.brand,
    this.aliases = const [],
    this.portions = const [],
    this.region,
    this.emoji = '🍽️',
    this.hydrationFactor,
  });

  final String id;
  final String name;
  final String? brand;

  /// Alternate names/spellings used for search ("kuey teow", "kway teow").
  final List<String> aliases;
  final NutritionFacts per100g;
  final List<Portion> portions;

  /// 'MY', 'SG', 'ID', 'TH' for regional dishes; null for universal foods.
  final String? region;
  final String emoji;

  /// For beverages: fraction of the weight that counts toward hydration
  /// (water ≈ 1.0, teh tarik ≈ 0.9, kopi ≈ 0.9 — caffeine offsets a little).
  /// null = not a drink, contributes nothing.
  final double? hydrationFactor;

  /// Default logging size: first named portion, else 100 g.
  double get defaultGrams => portions.isNotEmpty ? portions.first.grams : 100;

  String get defaultPortionLabel =>
      portions.isNotEmpty ? portions.first.label : '100 g';

  /// Parses a backend search result (Food::toClientArray on the server).
  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: j['name'] as String,
        brand: j['brand'] as String?,
        region: j['region'] as String?,
        emoji: (j['emoji'] as String?)?.isNotEmpty == true
            ? j['emoji'] as String
            : '🍽️',
        per100g:
            NutritionFacts.fromJson(j['per_100g'] as Map<String, dynamic>),
        portions: ((j['portions'] as List?) ?? const [])
            .map((p) => Portion.fromJson(p as Map<String, dynamic>))
            .toList(),
        aliases: ((j['aliases'] as List?) ?? const [])
            .map((a) => a.toString())
            .toList(),
        hydrationFactor: (j['hydration_factor'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'region': region,
        'emoji': emoji,
        'per_100g': per100g.toJson(),
        'portions': portions.map((p) => p.toJson()).toList(),
        'aliases': aliases,
        'hydration_factor': hydrationFactor,
      };
}
