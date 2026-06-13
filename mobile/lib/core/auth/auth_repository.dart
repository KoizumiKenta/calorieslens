import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import '../state/providers.dart';

final authRepoProvider =
    Provider((ref) => AuthRepository(ref.watch(sharedPrefsProvider)));

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final int id;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
      );
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to /auth/* and persists the token + user locally so the session
/// survives restarts. Token storage is shared_preferences for v1 (matches
/// the rest of the app); a device build moves it to flutter_secure_storage.
class AuthRepository {
  AuthRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _tokenKey = 'auth.token.v1';
  static const _userKey = 'auth.user.v1';

  String? get token => _prefs.getString(_tokenKey);

  AuthUser? get user {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<AuthUser> register(String name, String email, String password) =>
      _authCall('auth/register',
          {'name': name, 'email': email, 'password': password});

  Future<AuthUser> login(String email, String password) =>
      _authCall('auth/login', {'email': email, 'password': password});

  Future<void> logout() async {
    final t = token;
    if (t != null) {
      try {
        await http
            .post(ApiConfig.uri('auth/logout'),
                headers: ApiConfig.headers(token: t))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Best-effort server revoke; clear locally regardless.
      }
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
  }

  Future<AuthUser> _authCall(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await http
          .post(ApiConfig.uri(path),
              headers: ApiConfig.headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw AuthException('Can\'t reach the server. Check your connection.');
    }

    final json = _decode(res);
    if (res.statusCode == 200 || res.statusCode == 201) {
      await _prefs.setString(_tokenKey, json['token'] as String);
      await _prefs.setString(_userKey, jsonEncode(json['user']));
      return AuthUser.fromJson(json['user'] as Map<String, dynamic>);
    }
    throw AuthException(_errorMessage(res.statusCode, json));
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _errorMessage(int status, Map<String, dynamic> json) {
    if (json['errors'] is Map) {
      final first = (json['errors'] as Map).values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    if (json['message'] is String) return json['message'] as String;
    return 'Something went wrong (HTTP $status).';
  }
}
