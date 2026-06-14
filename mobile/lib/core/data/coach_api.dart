import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_config.dart';

/// Cloud nutrition coach via the backend `/coach/messages` endpoint. The phone
/// sends the question, a compact context block (today's numbers, goal) and the
/// recent turns; the backend grounds Gemini's reply in those numbers. Callers
/// fall back to the on-device rule coach when this throws (offline / no key).
class CoachApi {
  static const _appToken = String.fromEnvironment('APP_TOKEN');

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_appToken.isNotEmpty) 'X-App-Token': _appToken,
        'ngrok-skip-browser-warning': '1',
      };

  /// Returns the coach's reply text, or throws on any failure.
  static Future<String> reply(
    String message,
    String context, {
    List<({String role, String text})> history = const [],
  }) async {
    final res = await http
        .post(
          ApiConfig.uri('coach/messages'),
          headers: _headers,
          body: jsonEncode({
            'message': message,
            'context': context,
            'history': history
                .map((h) => {'role': h.role, 'text': h.text})
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 60));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
          (body['message'] ?? body['error'] ?? 'HTTP ${res.statusCode}')
              .toString());
    }
    final reply = (body['reply'] as String?)?.trim() ?? '';
    if (reply.isEmpty) throw Exception('empty reply');
    return reply;
  }
}
