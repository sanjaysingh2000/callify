import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveKitConfig {
  static const String _serverUrl = String.fromEnvironment(
    'LIVEKIT_SERVER_URL',
    defaultValue: 'wss://callify-99temb0p.livekit.cloud',
  );

  static const String _tokenEndpoint = String.fromEnvironment(
    'LIVEKIT_TOKEN_URL',
    defaultValue: 'https://livekit-token-server-one.vercel.app/api/token',
  );

  static String get serverUrl => _serverUrl;

  static Future<String> requestToken({
    required String roomName,
    required String identity,
  }) async {
    final tokenEndpoint = _tokenEndpoint;
    if (tokenEndpoint.isEmpty) {
      throw StateError(
        'LIVEKIT_TOKEN_URL is not configured. Set it with --dart-define or an environment file, and generate the token on a backend. Current default: https://livekit-token-server-one.vercel.app/api/token',
      );
    }

    debugPrint('[LiveKitConfig] Requesting token from $tokenEndpoint');
    final response = await http
        .post(
          Uri.parse(tokenEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'roomName': roomName, 'identity': identity}),
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('[LiveKitConfig] Token response status: ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to fetch LiveKit token: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body);
    final token =
        payload['token'] as String? ?? payload['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError(
        'The LiveKit token endpoint did not return a valid token payload.',
      );
    }

    return token;
  }
}