import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdStore {
  static const String _key = 'device_matchmaking_id';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final deviceId = _generateDeviceId();
    await prefs.setString(_key, deviceId);
    return deviceId;
  }

  String _generateDeviceId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = random.nextInt(999999).toString().padLeft(6, '0');
    return 'device_${timestamp}_$randomPart';
  }
}
