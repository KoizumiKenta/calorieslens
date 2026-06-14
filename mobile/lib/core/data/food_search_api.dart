import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../models/food.dart';
import 'food_database.dart';

/// Food search backed by the Laravel `/foods/search` endpoint (curated SEA
/// seed + Open Food Facts, cached server-side). Falls back to the bundled
/// on-device seed when the backend is unreachable, so search always works
/// offline — just with narrower coverage.
class FoodSearchApi {
  const FoodSearchApi();

  Future<FoodSearchResult> search(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      // Pre-keystroke: show regional favourites from the local seed.
      return FoodSearchResult(
        foods: FoodDatabase.all.where((f) => f.region != null).take(10).toList(),
        offline: false,
      );
    }

    try {
      final res = await http
          .get(ApiConfig.uri('foods/search', {'q': q}),
              headers: ApiConfig.headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final foods = (body['results'] as List)
          .map((e) => Food.fromJson(e as Map<String, dynamic>))
          .toList();
      return FoodSearchResult(foods: foods, offline: false);
    } catch (_) {
      // Backend down / offline → local seed only.
      return FoodSearchResult(foods: FoodDatabase.search(q), offline: true);
    }
  }

  /// Barcode (EAN/UPC) lookup via the backend (Open Food Facts). Returns the
  /// matched [Food], or an error message (e.g. not found → offer custom food).
  /// Requires the backend — there's no offline barcode database.
  Future<({Food? food, String? error})> barcode(String code) async {
    final clean = code.replaceAll(RegExp(r'\D'), '');
    try {
      final res = await http
          .get(ApiConfig.uri('foods/barcode/$clean'), headers: ApiConfig.headers())
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return (food: Food.fromJson(body['food'] as Map<String, dynamic>), error: null);
      }
      return (food: null, error: (body['message'] ?? 'Lookup failed.').toString());
    } catch (_) {
      return (food: null, error: "Couldn't reach the server. Check your connection.");
    }
  }

  /// "Estimate any dish with AI" — for local foods (ban mee, loh mee…) no
  /// database carries. Returns the estimated [Food], or null on failure.
  /// Requires the backend (no offline equivalent — it needs the model).
  Future<Food?> estimate(String name) async {
    try {
      final res = await http
          .post(ApiConfig.uri('foods/estimate'),
              headers: ApiConfig.headers(),
              body: jsonEncode({'name': name.trim()}))
          .timeout(const Duration(seconds: 35));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return Food.fromJson(body['food'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class FoodSearchResult {
  const FoodSearchResult({required this.foods, required this.offline});

  final List<Food> foods;

  /// True when results came from the on-device seed because the backend
  /// couldn't be reached — the UI surfaces this so narrow results are explained.
  final bool offline;
}

final foodSearchApiProvider = Provider((ref) => const FoodSearchApi());
