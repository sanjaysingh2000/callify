import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdStore {
  static const String _key = 'device_matchmaking_id';

  Future<String> getOrCreateDeviceId() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {
      // Keep previews and isolated tests usable before Firebase is initialized.
    }
    return getOrCreateLegacyDeviceId();
  }

  /// Returns the installation ID used before Google sign-in was introduced.
  /// It is retained so existing profile and friendship data can be migrated.
  Future<String> getOrCreateLegacyDeviceId() async {
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
