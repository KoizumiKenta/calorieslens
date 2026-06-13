import '../models/food.dart';
import '../models/nutrition_facts.dart';

/// Seeded on-device food database. SEA-heavy on purpose — the regional gap
/// is the product's moat (docs/01-prd.md §personas). Per-100g values are
/// as-served estimates compiled from MyHealth MY / HPB SG published figures.
/// On device builds this becomes a Drift table synced from the backend;
/// the search contract stays identical.
class FoodDatabase {
  FoodDatabase._();

  static List<Food> search(String query, {int limit = 25}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final scored = <(Food, int)>[];
    for (final food in all) {
      final score = _score(food, q);
      if (score > 0) scored.add((food, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  static Food? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  static int _score(Food food, String q) {
    final name = food.name.toLowerCase();
    if (name == q) return 100;
    if (name.startsWith(q)) return 80;
    if (name.contains(q)) return 60;
    for (final alias in food.aliases) {
      final a = alias.toLowerCase();
      if (a == q) return 90;
      if (a.startsWith(q)) return 70;
      if (a.contains(q)) return 50;
    }
    // Every query word must appear somewhere for a partial match.
    final words = q.split(' ').where((w) => w.isNotEmpty);
    final haystack = '$name ${food.aliases.join(' ')}'.toLowerCase();
    if (words.isNotEmpty && words.every(haystack.contains)) return 40;
    return 0;
  }

  static final List<Food> all = [
    // ── Malaysian / Singaporean dishes ──────────────────────────────
    const Food(
      id: 'my-nasi-lemak',
      name: 'Nasi Lemak (with sambal, egg, anchovies)',
      aliases: ['coconut rice'],
      region: 'MY',
      emoji: '🍛',
      per100g: NutritionFacts(kcal: 188, proteinG: 6.0, carbsG: 22.0, fatG: 8.5, fiberG: 1.2, sodiumMg: 320),
      portions: [Portion(label: '1 plate', grams: 330), Portion(label: '1 bungkus (small)', grams: 250)],
    ),
    const Food(
      id: 'my-roti-canai',
      name: 'Roti Canai (plain)',
      aliases: ['roti prata', 'prata'],
      region: 'MY',
      emoji: '🫓',
      per100g: NutritionFacts(kcal: 300, proteinG: 6.5, carbsG: 42.0, fatG: 11.5, sodiumMg: 410),
      portions: [Portion(label: '1 piece', grams: 100)],
    ),
    const Food(
      id: 'my-dhal-curry',
      name: 'Dhal Curry',
      aliases: ['dal', 'dhall'],
      region: 'MY',
      emoji: '🍲',
      per100g: NutritionFacts(kcal: 85, proteinG: 4.5, carbsG: 11.0, fatG: 2.5, fiberG: 2.8, sodiumMg: 290),
      portions: [Portion(label: '1 small bowl', grams: 120)],
    ),
    const Food(
      id: 'my-teh-tarik',
      name: 'Teh Tarik',
      aliases: ['pulled tea', 'milk tea'],
      region: 'MY',
      emoji: '🧋',
      per100g: NutritionFacts(kcal: 65, proteinG: 1.5, carbsG: 10.5, fatG: 1.8, sugarG: 9.5),
      hydrationFactor: 0.9,
      portions: [Portion(label: '1 glass', grams: 250), Portion(label: '1 small cup', grams: 180)],
    ),
    const Food(
      id: 'my-teh-tarik-kurang',
      name: 'Teh Tarik (kurang manis)',
      aliases: ['less sweet tea'],
      region: 'MY',
      emoji: '🧋',
      per100g: NutritionFacts(kcal: 45, proteinG: 1.5, carbsG: 6.5, fatG: 1.8, sugarG: 5.5),
      hydrationFactor: 0.92,
      portions: [Portion(label: '1 glass', grams: 250)],
    ),
    const Food(
      id: 'sg-chicken-rice',
      name: 'Hainanese Chicken Rice',
      aliases: ['chicken rice'],
      region: 'SG',
      emoji: '🍗',
      per100g: NutritionFacts(kcal: 155, proteinG: 9.0, carbsG: 17.0, fatG: 5.5, sodiumMg: 380),
      portions: [Portion(label: '1 plate', grams: 400)],
    ),
    const Food(
      id: 'my-char-kway-teow',
      name: 'Char Kway Teow',
      aliases: ['char kuey teow', 'ckt', 'fried flat noodles'],
      region: 'MY',
      emoji: '🍜',
      per100g: NutritionFacts(kcal: 185, proteinG: 6.5, carbsG: 20.0, fatG: 8.8, sodiumMg: 520),
      portions: [Portion(label: '1 plate', grams: 400)],
    ),
    const Food(
      id: 'my-laksa',
      name: 'Curry Laksa',
      aliases: ['laksa lemak', 'curry mee'],
      region: 'MY',
      emoji: '🍜',
      per100g: NutritionFacts(kcal: 120, proteinG: 5.0, carbsG: 11.5, fatG: 6.2, sodiumMg: 480),
      portions: [Portion(label: '1 bowl', grams: 500)],
    ),
    const Food(
      id: 'my-asam-laksa',
      name: 'Asam Laksa',
      aliases: ['penang laksa'],
      region: 'MY',
      emoji: '🍜',
      per100g: NutritionFacts(kcal: 88, proteinG: 4.2, carbsG: 14.5, fatG: 1.5, sodiumMg: 510),
      portions: [Portion(label: '1 bowl', grams: 500)],
    ),
    const Food(
      id: 'my-nasi-goreng',
      name: 'Nasi Goreng (fried rice)',
      aliases: ['fried rice kampung'],
      region: 'MY',
      emoji: '🍚',
      per100g: NutritionFacts(kcal: 168, proteinG: 5.5, carbsG: 22.0, fatG: 6.5, sodiumMg: 450),
      portions: [Portion(label: '1 plate', grams: 350)],
    ),
    const Food(
      id: 'my-mee-goreng',
      name: 'Mee Goreng Mamak',
      aliases: ['fried noodles', 'indian fried noodles'],
      region: 'MY',
      emoji: '🍝',
      per100g: NutritionFacts(kcal: 175, proteinG: 6.0, carbsG: 23.5, fatG: 6.8, sodiumMg: 540),
      portions: [Portion(label: '1 plate', grams: 350)],
    ),
    const Food(
      id: 'my-satay-chicken',
      name: 'Chicken Satay (with peanut sauce)',
      aliases: ['sate ayam'],
      region: 'MY',
      emoji: '🍢',
      per100g: NutritionFacts(kcal: 215, proteinG: 18.0, carbsG: 8.0, fatG: 12.5, sodiumMg: 350),
      portions: [Portion(label: '5 sticks + sauce', grams: 150), Portion(label: '10 sticks + sauce', grams: 300)],
    ),
    const Food(
      id: 'my-rendang-beef',
      name: 'Beef Rendang',
      aliases: ['rendang daging'],
      region: 'MY',
      emoji: '🥘',
      per100g: NutritionFacts(kcal: 195, proteinG: 15.5, carbsG: 5.0, fatG: 12.8, sodiumMg: 420),
      portions: [Portion(label: '1 serving', grams: 130)],
    ),
    const Food(
      id: 'sg-kaya-toast',
      name: 'Kaya Toast (with butter)',
      aliases: ['kaya butter toast'],
      region: 'SG',
      emoji: '🍞',
      per100g: NutritionFacts(kcal: 330, proteinG: 5.5, carbsG: 45.0, fatG: 14.0, sugarG: 18.0),
      portions: [Portion(label: '2 slices', grams: 90)],
    ),
    const Food(
      id: 'my-milo-ais',
      name: 'Milo Ais',
      aliases: ['iced milo', 'milo dinosaur'],
      region: 'MY',
      emoji: '🥤',
      per100g: NutritionFacts(kcal: 70, proteinG: 1.8, carbsG: 12.5, fatG: 1.5, sugarG: 10.5),
      hydrationFactor: 0.88,
      portions: [Portion(label: '1 glass', grams: 300)],
    ),
    const Food(
      id: 'my-nasi-kandar',
      name: 'Nasi Kandar (rice + curry chicken)',
      region: 'MY',
      emoji: '🍛',
      per100g: NutritionFacts(kcal: 170, proteinG: 8.5, carbsG: 20.0, fatG: 6.5, sodiumMg: 460),
      portions: [Portion(label: '1 plate', grams: 450)],
    ),
    const Food(
      id: 'my-wantan-mee',
      name: 'Wantan Mee (dry)',
      aliases: ['wonton noodles'],
      region: 'MY',
      emoji: '🍜',
      per100g: NutritionFacts(kcal: 150, proteinG: 7.0, carbsG: 21.0, fatG: 4.2, sodiumMg: 560),
      portions: [Portion(label: '1 plate', grams: 330)],
    ),
    const Food(
      id: 'sg-bak-kut-teh',
      name: 'Bak Kut Teh',
      aliases: ['pork rib soup'],
      region: 'SG',
      emoji: '🍲',
      per100g: NutritionFacts(kcal: 95, proteinG: 9.5, carbsG: 1.5, fatG: 5.8, sodiumMg: 480),
      portions: [Portion(label: '1 bowl', grams: 400)],
    ),
    const Food(
      id: 'my-roti-telur',
      name: 'Roti Telur',
      aliases: ['egg prata'],
      region: 'MY',
      emoji: '🫓',
      per100g: NutritionFacts(kcal: 270, proteinG: 8.5, carbsG: 33.0, fatG: 11.5, sodiumMg: 430),
      portions: [Portion(label: '1 piece', grams: 140)],
    ),
    const Food(
      id: 'my-popiah',
      name: 'Popiah (fresh spring roll)',
      region: 'MY',
      emoji: '🌯',
      per100g: NutritionFacts(kcal: 130, proteinG: 4.5, carbsG: 19.0, fatG: 4.0, fiberG: 2.2, sodiumMg: 380),
      portions: [Portion(label: '1 roll', grams: 140)],
    ),
    const Food(
      id: 'my-cendol',
      name: 'Cendol',
      region: 'MY',
      emoji: '🍧',
      per100g: NutritionFacts(kcal: 105, proteinG: 1.2, carbsG: 18.5, fatG: 3.2, sugarG: 15.0),
      portions: [Portion(label: '1 bowl', grams: 240)],
    ),
    const Food(
      id: 'my-curry-puff',
      name: 'Curry Puff',
      aliases: ['karipap'],
      region: 'MY',
      emoji: '🥟',
      per100g: NutritionFacts(kcal: 305, proteinG: 5.5, carbsG: 31.0, fatG: 17.5, sodiumMg: 390),
      portions: [Portion(label: '1 piece', grams: 75)],
    ),
    const Food(
      id: 'sg-chilli-crab',
      name: 'Chilli Crab',
      region: 'SG',
      emoji: '🦀',
      per100g: NutritionFacts(kcal: 110, proteinG: 11.0, carbsG: 6.5, fatG: 4.5, sodiumMg: 540),
      portions: [Portion(label: '1 serving', grams: 250)],
    ),
    const Food(
      id: 'my-ayam-goreng',
      name: 'Ayam Goreng (fried chicken, thigh)',
      aliases: ['fried chicken malay'],
      region: 'MY',
      emoji: '🍗',
      per100g: NutritionFacts(kcal: 260, proteinG: 22.0, carbsG: 6.0, fatG: 16.0, sodiumMg: 420),
      portions: [Portion(label: '1 piece', grams: 120)],
    ),
    const Food(
      id: 'id-gado-gado',
      name: 'Gado-Gado',
      region: 'ID',
      emoji: '🥗',
      per100g: NutritionFacts(kcal: 125, proteinG: 5.5, carbsG: 10.0, fatG: 7.0, fiberG: 3.0, sodiumMg: 310),
      portions: [Portion(label: '1 plate', grams: 350)],
    ),
    const Food(
      id: 'th-pad-thai',
      name: 'Pad Thai',
      region: 'TH',
      emoji: '🍤',
      per100g: NutritionFacts(kcal: 165, proteinG: 7.5, carbsG: 21.0, fatG: 5.8, sodiumMg: 490),
      portions: [Portion(label: '1 plate', grams: 350)],
    ),
    const Food(
      id: 'th-green-curry',
      name: 'Thai Green Curry (chicken)',
      region: 'TH',
      emoji: '🍛',
      per100g: NutritionFacts(kcal: 130, proteinG: 8.0, carbsG: 5.5, fatG: 8.8, sodiumMg: 440),
      portions: [Portion(label: '1 bowl', grams: 300)],
    ),

    // ── Universal staples ───────────────────────────────────────────
    const Food(
      id: 'rice-white-cooked',
      name: 'White Rice (cooked)',
      aliases: ['nasi putih', 'steamed rice'],
      emoji: '🍚',
      per100g: NutritionFacts(kcal: 130, proteinG: 2.7, carbsG: 28.0, fatG: 0.3),
      portions: [Portion(label: '1 bowl', grams: 200), Portion(label: '1 scoop', grams: 100)],
    ),
    const Food(
      id: 'rice-brown-cooked',
      name: 'Brown Rice (cooked)',
      emoji: '🍚',
      per100g: NutritionFacts(kcal: 112, proteinG: 2.6, carbsG: 23.5, fatG: 0.9, fiberG: 1.8),
      portions: [Portion(label: '1 bowl', grams: 200)],
    ),
    const Food(
      id: 'chicken-breast-grilled',
      name: 'Chicken Breast (grilled)',
      emoji: '🍗',
      per100g: NutritionFacts(kcal: 165, proteinG: 31.0, carbsG: 0, fatG: 3.6),
      portions: [Portion(label: '1 breast', grams: 170), Portion(label: '1 small breast', grams: 120)],
    ),
    const Food(
      id: 'egg-whole',
      name: 'Egg (whole, boiled)',
      aliases: ['telur', 'hard boiled egg'],
      emoji: '🥚',
      per100g: NutritionFacts(kcal: 155, proteinG: 13.0, carbsG: 1.1, fatG: 11.0),
      portions: [Portion(label: '1 large egg', grams: 55), Portion(label: '2 eggs', grams: 110)],
    ),
    const Food(
      id: 'egg-fried',
      name: 'Fried Egg',
      aliases: ['telur goreng', 'telur mata'],
      emoji: '🍳',
      per100g: NutritionFacts(kcal: 196, proteinG: 13.6, carbsG: 0.8, fatG: 15.0),
      portions: [Portion(label: '1 egg', grams: 55)],
    ),
    const Food(
      id: 'banana',
      name: 'Banana',
      aliases: ['pisang'],
      emoji: '🍌',
      per100g: NutritionFacts(kcal: 89, proteinG: 1.1, carbsG: 23.0, fatG: 0.3, fiberG: 2.6, sugarG: 12.0),
      portions: [Portion(label: '1 medium', grams: 118)],
    ),
    const Food(
      id: 'apple',
      name: 'Apple',
      aliases: ['epal'],
      emoji: '🍎',
      per100g: NutritionFacts(kcal: 52, proteinG: 0.3, carbsG: 14.0, fatG: 0.2, fiberG: 2.4, sugarG: 10.0),
      portions: [Portion(label: '1 medium', grams: 180)],
    ),
    const Food(
      id: 'oats-cooked',
      name: 'Oatmeal (cooked with water)',
      aliases: ['porridge oats'],
      emoji: '🥣',
      per100g: NutritionFacts(kcal: 71, proteinG: 2.5, carbsG: 12.0, fatG: 1.5, fiberG: 1.7),
      portions: [Portion(label: '1 bowl', grams: 240)],
    ),
    const Food(
      id: 'bread-white',
      name: 'White Bread',
      aliases: ['roti putih'],
      emoji: '🍞',
      per100g: NutritionFacts(kcal: 265, proteinG: 9.0, carbsG: 49.0, fatG: 3.2, fiberG: 2.7, sugarG: 5.0),
      portions: [Portion(label: '1 slice', grams: 30), Portion(label: '2 slices', grams: 60)],
    ),
    const Food(
      id: 'salmon-grilled',
      name: 'Salmon (grilled)',
      emoji: '🐟',
      per100g: NutritionFacts(kcal: 208, proteinG: 20.0, carbsG: 0, fatG: 13.0),
      portions: [Portion(label: '1 fillet', grams: 150)],
    ),
    const Food(
      id: 'tofu-firm',
      name: 'Tofu (firm)',
      aliases: ['tauhu', 'bean curd'],
      emoji: '🧈',
      per100g: NutritionFacts(kcal: 76, proteinG: 8.0, carbsG: 1.9, fatG: 4.8),
      portions: [Portion(label: '1 block', grams: 250), Portion(label: '½ block', grams: 125)],
    ),
    const Food(
      id: 'milk-full',
      name: 'Milk (full cream)',
      aliases: ['susu'],
      emoji: '🥛',
      per100g: NutritionFacts(kcal: 61, proteinG: 3.2, carbsG: 4.8, fatG: 3.3, sugarG: 4.8),
      hydrationFactor: 0.88,
      portions: [Portion(label: '1 glass', grams: 250)],
    ),
    const Food(
      id: 'yogurt-greek',
      name: 'Greek Yogurt (plain)',
      emoji: '🥛',
      per100g: NutritionFacts(kcal: 97, proteinG: 9.0, carbsG: 3.9, fatG: 5.0, sugarG: 3.9),
      portions: [Portion(label: '1 tub', grams: 170)],
    ),
    const Food(
      id: 'instant-noodles',
      name: 'Instant Noodles (cooked, with seasoning)',
      aliases: ['maggi', 'indomie', 'ramen instant'],
      emoji: '🍜',
      per100g: NutritionFacts(kcal: 138, proteinG: 3.0, carbsG: 18.5, fatG: 5.8, sodiumMg: 720),
      portions: [Portion(label: '1 pack', grams: 320)],
    ),
    const Food(
      id: 'french-fries',
      name: 'French Fries',
      emoji: '🍟',
      per100g: NutritionFacts(kcal: 312, proteinG: 3.4, carbsG: 41.0, fatG: 15.0, sodiumMg: 210),
      portions: [Portion(label: 'medium serving', grams: 117), Portion(label: 'large serving', grams: 154)],
    ),
    const Food(
      id: 'pizza-cheese',
      name: 'Pizza (cheese, regular crust)',
      emoji: '🍕',
      per100g: NutritionFacts(kcal: 266, proteinG: 11.0, carbsG: 33.0, fatG: 10.0, sodiumMg: 598),
      portions: [Portion(label: '1 slice', grams: 107), Portion(label: '2 slices', grams: 214)],
    ),
    const Food(
      id: 'burger-cheeseburger',
      name: 'Cheeseburger',
      emoji: '🍔',
      per100g: NutritionFacts(kcal: 263, proteinG: 13.0, carbsG: 28.0, fatG: 11.0, sodiumMg: 560),
      portions: [Portion(label: '1 burger', grams: 150)],
    ),
    const Food(
      id: 'avocado',
      name: 'Avocado',
      emoji: '🥑',
      per100g: NutritionFacts(kcal: 160, proteinG: 2.0, carbsG: 9.0, fatG: 15.0, fiberG: 6.7),
      portions: [Portion(label: '½ avocado', grams: 100)],
    ),
    const Food(
      id: 'almonds',
      name: 'Almonds',
      emoji: '🥜',
      per100g: NutritionFacts(kcal: 579, proteinG: 21.0, carbsG: 22.0, fatG: 50.0, fiberG: 12.5),
      portions: [Portion(label: '1 handful (23 nuts)', grams: 28)],
    ),
    const Food(
      id: 'orange-juice',
      name: 'Orange Juice',
      emoji: '🍊',
      per100g: NutritionFacts(kcal: 45, proteinG: 0.7, carbsG: 10.4, fatG: 0.2, sugarG: 8.4),
      hydrationFactor: 0.89,
      portions: [Portion(label: '1 glass', grams: 250)],
    ),
    const Food(
      id: 'coffee-black',
      name: 'Black Coffee (no sugar)',
      aliases: ['kopi o kosong', 'americano'],
      emoji: '☕',
      per100g: NutritionFacts(kcal: 2, proteinG: 0.1, carbsG: 0, fatG: 0),
      hydrationFactor: 0.99,
      portions: [Portion(label: '1 cup', grams: 240)],
    ),
    const Food(
      id: 'kopi-c',
      name: 'Kopi C (coffee with evaporated milk)',
      aliases: ['kopi'],
      region: 'SG',
      emoji: '☕',
      per100g: NutritionFacts(kcal: 45, proteinG: 1.2, carbsG: 7.0, fatG: 1.4, sugarG: 6.5),
      hydrationFactor: 0.9,
      portions: [Portion(label: '1 cup', grams: 220)],
    ),
    const Food(
      id: 'protein-shake-whey',
      name: 'Whey Protein Shake (1 scoop, water)',
      emoji: '🥤',
      per100g: NutritionFacts(kcal: 40, proteinG: 8.0, carbsG: 1.0, fatG: 0.5),
      hydrationFactor: 0.92,
      portions: [Portion(label: '1 shake (300ml)', grams: 300)],
    ),
    const Food(
      id: 'broccoli-steamed',
      name: 'Broccoli (steamed)',
      emoji: '🥦',
      per100g: NutritionFacts(kcal: 35, proteinG: 2.4, carbsG: 7.2, fatG: 0.4, fiberG: 3.3),
      portions: [Portion(label: '1 cup', grams: 90)],
    ),
    const Food(
      id: 'kangkung-belacan',
      name: 'Kangkung Belacan',
      aliases: ['water spinach', 'stir fried kangkung'],
      region: 'MY',
      emoji: '🥬',
      per100g: NutritionFacts(kcal: 75, proteinG: 3.0, carbsG: 5.5, fatG: 4.8, fiberG: 2.5, sodiumMg: 450),
      portions: [Portion(label: '1 serving', grams: 150)],
    ),
  ];
}
