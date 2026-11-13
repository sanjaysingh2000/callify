import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Calls the Vercel endpoint to send push notifications when a panel is created.
class PanelNotificationSender {
  static const _notifyUrl = 'https://livekit-token-server-one.vercel.app/api/send-notification';

  /// Sends notification to all users about a new panel.
  /// Fire-and-forget — errors are logged but not thrown.
  static Future<void> notifyNewPanel({
    required String title,
    required String hostName,
    required String hostId,
    required String panelId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_notifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'hostName': hostName,
          'hostId': hostId,
          'panelId': panelId,
        }),
      );
      debugPrint('[PanelNotification] Response: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('[PanelNotification] Failed to send: $e');
    }
  }
}
