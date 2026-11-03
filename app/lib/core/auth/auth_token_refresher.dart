// Token renewal for activated clients.
//
// /activate signs a 30-day token and nothing renewed it: once it lapsed, the B-3 config
// refresh and the node catalog both started failing with 401 and the app silently kept the
// last delivered node. This helper is the single renewal path for every authenticated GET:
//
//   token -> request -> 401? -> POST /api/app/token/refresh (expiry deliberately tolerated
//   server-side when the account and device binding are still valid) -> store -> retry ONCE.
//
// It never retries twice (a rejected renewal must not become a loop) and never throws: a
// renewal failure just returns the original response so the caller keeps its existing
// behaviour (keep the last known-good artifact, never invent a fallback node).

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:nublime/utils/custom_loggers.dart';

const String kTokenRefreshEndpoint =
    'https://www.nublime.com/api/app/token/refresh';

typedef RawResponse = ({int status, String? body});

class AuthorizedClient with InfraLogger {
  AuthorizedClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Renews the stored token. Returns the new token string, or null when renewal is
  /// impossible (no token stored, server refuses, malformed answer).
  Future<String?> renew(String currentToken) async {
    try {
      final res = await _client
          .post(
            Uri.parse(kTokenRefreshEndpoint),
            headers: {'Authorization': 'Bearer $currentToken'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        loggy.info('[AUTH] token refresh rejected: status=${res.statusCode}');
        return null;
      }
      final data = jsonDecode(res.body);
      final token = (data is Map) ? data['token'] : null;
      if (token is! String || token.trim().isEmpty) {
        loggy.info('[AUTH] token refresh returned no token');
        return null;
      }
      final storage = AuthTokenStorage();
      final existing = await storage.getToken();
      if (existing == null) return null;
      await storage.saveToken(AuthToken(
        token: token,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        deviceId: existing.deviceId,
        email: existing.email,
        createdAt: existing.createdAt,
        activationCode: existing.activationCode,
        bonusDays: existing.bonusDays,
      ));
      loggy.info('[AUTH] token renewed (30d)');
      return token;
    } catch (e) {
      loggy.info('[AUTH] token refresh failed: $e');
      return null;
    }
  }

  /// Authenticated GET with one renewal-and-retry on 401.
  ///
  /// Returns `(status: 0, body: null)` when there is no stored token at all — callers treat
  /// that exactly like a transport failure.
  Future<RawResponse> get(Uri url, {Duration timeout = const Duration(seconds: 8)}) async {
    final storage = AuthTokenStorage();
    final stored = await storage.getToken();
    if (stored == null) return (status: 0, body: null);

    Future<RawResponse> once(String token) async {
      final res = await _client
          .get(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(timeout);
      return (status: res.statusCode, body: res.body);
    }

    var res = await once(stored.token);
    if (res.status != 401) return res;

    final renewed = await renew(stored.token);
    if (renewed == null) return res;
    res = await once(renewed);
    return res;
  }
}
