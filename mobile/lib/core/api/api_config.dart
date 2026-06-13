/// Base URL for the CalorieLens account/sync API (Laravel backend).
///
/// Web dev defaults to the local Laravel server; device builds pass their own:
///   --dart-define=SYNC_API_BASE=https://your-host/api/v1
class ApiConfig {
  ApiConfig._();

  static const syncBase = String.fromEnvironment(
    'SYNC_API_BASE',
    defaultValue: 'http://127.0.0.1:8791/api/v1',
  );

  static Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$syncBase/$path').replace(queryParameters: query);

  /// Headers common to every request; [token] adds the Bearer credential.
  static Map<String, String> headers({String? token}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        // Skip ngrok's free-tier interstitial when tunneled; harmless otherwise.
        'ngrok-skip-browser-warning': '1',
        if (token != null) 'Authorization': 'Bearer $token',
      };
}
