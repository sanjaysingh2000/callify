import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/device_id_store.dart';

/// Stores the display name for this installation.
///
/// Firestore stores the profile for other app features. A local copy lets the
/// app continue to open if the device is temporarily offline.
class UserProfileStore {
  UserProfileStore({this._firestore, DeviceIdStore? deviceIdStore})
    : _deviceIdStore = deviceIdStore ?? DeviceIdStore();

  static const _displayNameKey = 'profile_display_name';

  final FirebaseFirestore? _firestore;
  final DeviceIdStore _deviceIdStore;

  FirebaseFirestore? get firestoreOrNull {
    if (_firestore != null) return _firestore;

    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the latest saved name from Firestore on every app launch, then
  /// refreshes the local cache. Falls back to the local name when offline.
  Future<String?> loadDisplayName() async {
    final deviceId = await _deviceIdStore.getOrCreateDeviceId();
    final prefs = await SharedPreferences.getInstance();
    final firestore = firestoreOrNull;

    if (firestore != null) {
      try {
        final profile = await firestore
            .collection('users')
            .doc(deviceId)
            .get(const GetOptions(source: Source.server));
        final displayName = profile.data()?['displayName'] as String?;
        final normalizedName = _normalize(displayName);
        if (normalizedName != null) {
          await prefs.setString(_displayNameKey, normalizedName);
          return normalizedName;
        }
      } catch (_) {
        // A cached name is sufficient to let a known user continue offline.
      }
    }

    return _normalize(prefs.getString(_displayNameKey));
  }

  Future<String> saveDisplayName(String name) async {
    final displayName = _normalize(name);
    if (displayName == null) {
      throw ArgumentError.value(name, 'name', 'Display name is required');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, displayName);

    final firestore = firestoreOrNull;
    if (firestore != null) {
      try {
        final deviceId = await _deviceIdStore.getOrCreateDeviceId();
        await firestore
            .collection('users')
            .doc(deviceId)
            .set(
              {
                'deviceId': deviceId,
                'displayName': displayName,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            )
            .timeout(const Duration(seconds: 8));
      } catch (error) {
        debugPrint('Could not sync display name to Firestore: $error');
      }
    }

    return displayName;
  }

  String? _normalize(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return null;
    return name.length <= 32 ? name : name.substring(0, 32);
  }
}
