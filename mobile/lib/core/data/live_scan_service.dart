import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../api/api_config.dart';
import '../models/nutrition_facts.dart';
import '../models/scan.dart';
import 'scan_service.dart';

/// Real AI analysis via the backend `/scans/analyze` endpoint (one origin
/// shared with auth/sync/foods — see ApiConfig). If the live call fails — no
/// key, offline, provider error — it degrades to [fallback] and says so in
/// the result: degrade visibly, never silently.
class LiveScanService implements ScanService {
  LiveScanService({this.fallback});

  final ScanService? fallback;
  static const _uuid = Uuid();

  /// Gates the public AI endpoints — matches APP_TOKEN on the server.
  static const _appToken = String.fromEnvironment('APP_TOKEN');

  static Uri _endpoint(String path) => ApiConfig.uri(path);

  static final _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_appToken.isNotEmpty) 'X-App-Token': _appToken,
    // ngrok free-tier interstitial bypass; harmless elsewhere.
    'ngrok-skip-browser-warning': '1',
  };

  @override
  Future<ScanAnalysis> analyzePhoto(Uint8List imageBytes, {String? note}) async {
    try {
      return await _analyzeRemote(imageBytes, note: note);
    } catch (e) {
      final fb = fallback;
      if (fb == null) rethrow;
      final sample = await fb.analyzePhoto(imageBytes, note: note);
      return ScanAnalysis(
        dishName: '${sample.dishName} (sample)',
        items: sample.items,
        overallNote:
            '⚠️ Live AI unavailable (${_shortReason(e)}) — this is an OFFLINE SAMPLE, not an analysis of your photo.',
      );
    }
  }

  @override
  Future<ScanItem> refineItem(ScanItem item, String note) async {
    try {
      final response = await http
          .post(
            _endpoint('scans/refine'),
            headers: _headers,
            body: jsonEncode({
              'note': note,
              'item': {
                'label': item.label,
                'grams': item.grams,
                'grams_low': item.gramsLow,
                'grams_high': item.gramsHigh,
                'confidence': item.confidence,
                'reasoning': item.reasoning,
                'per_100g': item.per100g.toJson(),
              },
            }),
          )
          .timeout(const Duration(seconds: 60));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw ScanApiException(
            (body['message'] ?? body['error'] ?? 'HTTP ${response.statusCode}')
                .toString());
      }
      // Backend wraps the corrected item as {item: {...}}. Keep the same id
      // so the controller replaces in place; preserve the removed flag.
      return _itemFromJson(
          body['item'] as Map<String, dynamic>,
          id: item.id,
          removed: item.removed);
    } catch (e) {
      final fb = fallback;
      if (fb == null) rethrow;
      return fb.refineItem(item, note);
    }
  }

  Future<ScanAnalysis> _analyzeRemote(Uint8List imageBytes,
      {String? note}) async {
    final response = await http
        .post(
          _endpoint('scans/analyze'),
          headers: _headers,
          body: jsonEncode({
            'media_type': _mediaType(imageBytes),
            'image': base64Encode(imageBytes),
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 90));

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ScanApiException(
          (body['message'] ?? body['error'] ?? 'HTTP ${response.statusCode}')
              .toString());
    }

    final items = (body['items'] as List<dynamic>)
        .map((raw) => _itemFromJson(raw as Map<String, dynamic>))
        .toList();

    return ScanAnalysis(
      dishName: body['dish_name'] as String? ?? 'Meal',
      items: items,
      overallNote: body['overall_note'] as String? ?? '',
    );
  }

  ScanItem _itemFromJson(Map<String, dynamic> item,
      {String? id, bool removed = false}) {
    return ScanItem(
      id: id ?? _uuid.v4(),
      label: item['label'] as String,
      grams: (item['grams'] as num).toDouble(),
      gramsLow: (item['grams_low'] as num).toDouble(),
      gramsHigh: (item['grams_high'] as num).toDouble(),
      confidence: (item['confidence'] as num).toDouble(),
      reasoning: item['reasoning'] as String,
      per100g:
          NutritionFacts.fromJson(item['per_100g'] as Map<String, dynamic>),
      emoji: (item['emoji'] as String?)?.isNotEmpty == true
          ? item['emoji'] as String
          : '🍽️',
      removed: removed,
      isDrink: item['is_drink'] as bool? ?? false,
    );
  }

  static String _shortReason(Object e) {
    final text = e.toString();
    if (text.contains('no_api_key') || text.contains('ANTHROPIC_API_KEY')) {
      return 'no API key configured';
    }
    if (text.contains('Timeout')) return 'timed out';
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }

  /// Magic-byte sniff — image_picker on web gives bytes with no metadata.
  static String _mediaType(Uint8List b) {
    if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 2 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    if (b.length > 2 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    return 'image/jpeg';
  }
}

class ScanApiException implements Exception {
  ScanApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
