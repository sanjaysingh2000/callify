import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/device_id_store.dart';

class ProfileDetails {
  const ProfileDetails({
    required this.displayName,
    required this.age,
    required this.gender,
    required this.displayNameChangeUsed,
    required this.ageChangeUsed,
    required this.genderChangeUsed,
    this.profileImageBase64,
  });

  final String displayName;
  final int? age;
  final String? gender;
  final bool displayNameChangeUsed;
  final bool ageChangeUsed;
  final bool genderChangeUsed;
  final String? profileImageBase64;
}

/// Stores the display name for this installation.
///
/// Firestore stores the profile for other app features. A local copy lets the
/// app continue to open if the device is temporarily offline.
class UserProfileStore {
  UserProfileStore({this.firestore, DeviceIdStore? deviceIdStore})
    : _deviceIdStore = deviceIdStore ?? DeviceIdStore();

  static const _displayNameKey = 'profile_display_name';

  final FirebaseFirestore? firestore;
  final DeviceIdStore _deviceIdStore;

  FirebaseFirestore? get firestoreOrNull {
    if (firestore != null) return firestore;

    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Persists the Google profile under the authenticated Firebase UID.
  Future<String> saveAuthenticatedUser(User user) async {
    final fallback = user.email?.split('@').first;
    final googleName = user.displayName?.trim();
    var displayName =
        _normalize(
          googleName == null || googleName.isEmpty
              ? fallback
              : googleName.length > 32
              ? googleName.substring(0, 32)
              : googleName,
        ) ??
        'Callify user';

    final firestore = firestoreOrNull;
    if (firestore != null) {
      final legacyDeviceId = await _deviceIdStore.getOrCreateLegacyDeviceId();
      final profileRef = firestore.collection('users').doc(user.uid);
      try {
        final existing = await profileRef.get().timeout(
          const Duration(seconds: 4),
        );
        displayName =
            _normalize(existing.data()?['displayName'] as String?) ??
            displayName;
      } catch (error) {
        debugPrint('Could not load saved profile from Firestore: $error');
      }
      try {
        await profileRef
            .set({
              'userId': user.uid,
              'displayName': displayName,
              if (user.email != null) 'email': user.email,
              if (user.photoURL != null) 'photoURL': user.photoURL,
              'legacyDeviceId': legacyDeviceId,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 4));
      } catch (error) {
        debugPrint('Could not sync Google profile to Firestore: $error');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_displayNameKey}_${user.uid}', displayName);
    return displayName;
  }

  Future<ProfileDetails> loadProfile({
    required String userId,
    required String fallbackName,
  }) async {
    final firestore = firestoreOrNull;
    if (firestore != null) {
      try {
        final snapshot = await firestore
            .collection('users')
            .doc(userId)
            .get()
            .timeout(const Duration(seconds: 6));
        final data = snapshot.data() ?? const <String, dynamic>{};
        return ProfileDetails(
          displayName:
              _normalize(data['displayName'] as String?) ??
              _normalize(fallbackName) ??
              'Callify user',
          age: data['age'] is num ? (data['age'] as num).toInt() : null,
          gender: data['gender'] as String?,
          displayNameChangeUsed: data['displayNameChangeUsed'] == true,
          ageChangeUsed: data['ageChangeUsed'] == true,
          genderChangeUsed: data['genderChangeUsed'] == true,
          profileImageBase64: data['profileImageBase64'] as String?,
        );
      } catch (error) {
        debugPrint('Could not load profile details: $error');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return ProfileDetails(
      displayName:
          _normalize(prefs.getString('${_displayNameKey}_$userId')) ??
          _normalize(fallbackName) ??
          'Callify user',
      age: null,
      gender: null,
      displayNameChangeUsed: false,
      ageChangeUsed: false,
      genderChangeUsed: false,
      profileImageBase64: null,
    );
  }

  Future<ProfileDetails> updateProfile({
    required String userId,
    required ProfileDetails current,
    required String displayName,
    required int? age,
    required String? gender,
    String? profileImageBase64,
  }) async {
    final normalizedName = _normalize(displayName);
    if (normalizedName == null) {
      throw ArgumentError.value(displayName, 'displayName', 'Name is required');
    }
    if (age != null && (age < 1 || age > 120)) {
      throw ArgumentError.value(age, 'age', 'Age must be between 1 and 120');
    }
    if (profileImageBase64 != null && profileImageBase64.length > 128 * 1024) {
      throw ArgumentError.value(
        profileImageBase64,
        'profileImageBase64',
        'Profile image must be compressed before saving.',
      );
    }
    final firestore = firestoreOrNull;
    if (firestore == null) throw StateError('Profile storage is unavailable');

    var nameUsed = current.displayNameChangeUsed;
    var ageUsed = current.ageChangeUsed;
    var genderUsed = current.genderChangeUsed;
    final profileImageUpdate = profileImageBase64 == null
        ? const <String, Object?>{}
        : {'profileImageBase64': profileImageBase64};
    final profileRef = firestore.collection('users').doc(userId);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(profileRef);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final oldName =
          _normalize(data['displayName'] as String?) ?? current.displayName;
      final oldAge = data['age'] is num ? (data['age'] as num).toInt() : null;
      final oldGender = data['gender'] as String?;
      nameUsed = data['displayNameChangeUsed'] == true || nameUsed;
      ageUsed = data['ageChangeUsed'] == true || ageUsed;
      genderUsed = data['genderChangeUsed'] == true || genderUsed;

      if (normalizedName != oldName && nameUsed) {
        throw StateError('Your name has already used its one change.');
      }
      if (age != oldAge && ageUsed) {
        throw StateError('Your age has already used its one change.');
      }
      if (gender != oldGender && genderUsed) {
        throw StateError('Your gender has already used its one change.');
      }

      nameUsed = nameUsed || normalizedName != oldName;
      ageUsed = ageUsed || (oldAge != null && age != oldAge);
      genderUsed = genderUsed || (oldGender != null && gender != oldGender);
      final profileData = {
        'userId': userId,
        'displayName': normalizedName,
        'age': age,
        'gender': gender,
        ...profileImageUpdate,
        'displayNameChangeUsed': nameUsed,
        'ageChangeUsed': ageUsed,
        'genderChangeUsed': genderUsed,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (snapshot.exists) {
        transaction.update(profileRef, profileData);
      } else {
        transaction.set(profileRef, profileData);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_displayNameKey}_$userId', normalizedName);
    return ProfileDetails(
      displayName: normalizedName,
      age: age,
      gender: gender,
      displayNameChangeUsed: nameUsed,
      ageChangeUsed: ageUsed,
      genderChangeUsed: genderUsed,
      profileImageBase64: profileImageBase64 ?? current.profileImageBase64,
    );
  }

  /// Uses the local name first so app startup does not depend on a Firestore
  /// round trip. A remote profile is only needed when no local name exists.
  Future<String?> loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedName = _normalize(prefs.getString(_displayNameKey));
    if (cachedName != null) return cachedName;

    final deviceId = await _deviceIdStore.getOrCreateDeviceId();
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

    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (attempt > 1) await prefs.reload();
        final saved = await prefs.setString(_displayNameKey, displayName);
        if (!saved) {
          throw StateError(
            'SharedPreferences did not confirm the profile save',
          );
        }
        lastError = null;
        break;
      } catch (error, stackTrace) {
        lastError = error;
        debugPrint(
          'Could not save display name locally (attempt $attempt): $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(
        StateError('Could not persist the display name locally: $lastError'),
        StackTrace.current,
      );
    }

    // The local save is the source of truth for onboarding. Never keep the
    // user on the name screen while Firebase is starting or offline.
    unawaited(_syncDisplayName(displayName));

    return displayName;
  }

  Future<void> _syncDisplayName(String displayName) async {
    final firestore = firestoreOrNull;
    if (firestore == null) return;

    try {
      final deviceId = await _deviceIdStore.getOrCreateDeviceId();
      await firestore
          .collection('users')
          .doc(deviceId)
          .set({
            'deviceId': deviceId,
            'displayName': displayName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('Could not sync display name to Firestore: $error');
    }
  }

  String? _normalize(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return null;
    return name.length <= 32 ? name : name.substring(0, 32);
  }
}
