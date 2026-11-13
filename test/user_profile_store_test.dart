import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/profile/data/user_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saves and loads a compressed profile image from Firestore', () async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    final store = UserProfileStore(firestore: firestore);
    const imageBase64 = 'c21hbGwtaW1hZ2UtZGF0YQ==';
    const currentProfile = ProfileDetails(
      displayName: 'Taylor',
      age: null,
      gender: null,
      displayNameChangeUsed: false,
      ageChangeUsed: false,
      genderChangeUsed: false,
    );

    await store.updateProfile(
      userId: 'user-1',
      current: currentProfile,
      displayName: 'Taylor',
      age: null,
      gender: null,
      profileImageBase64: imageBase64,
    );
    final loaded = await store.loadProfile(
      userId: 'user-1',
      fallbackName: 'Unknown',
    );

    expect(loaded.profileImageBase64, imageBase64);
    expect(
      (await firestore.collection('users').doc('user-1').get())
          .data()?['profileImageBase64'],
      imageBase64,
    );
  });

  test(
    'does not replace the saved image when profile image is omitted',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('user-1').set({
        'displayName': 'Taylor',
        'profileImageBase64': 'existing-image',
      });
      final store = UserProfileStore(firestore: firestore);
      const currentProfile = ProfileDetails(
        displayName: 'Taylor',
        age: null,
        gender: null,
        displayNameChangeUsed: false,
        ageChangeUsed: false,
        genderChangeUsed: false,
        profileImageBase64: 'existing-image',
      );

      final updated = await store.updateProfile(
        userId: 'user-1',
        current: currentProfile,
        displayName: 'Taylor',
        age: null,
        gender: null,
      );

      expect(updated.profileImageBase64, 'existing-image');
      expect(
        (await firestore.collection('users').doc('user-1').get())
            .data()?['profileImageBase64'],
        'existing-image',
      );
    },
  );

  test(
    'allows repeated photo changes after profile details are locked',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('user-1').set({
        'displayName': 'Taylor',
        'age': 30,
        'gender': 'Prefer not to say',
        'displayNameChangeUsed': true,
        'ageChangeUsed': true,
        'genderChangeUsed': true,
        'profileImageBase64': 'first-photo',
      });
      final store = UserProfileStore(firestore: firestore);
      const lockedProfile = ProfileDetails(
        displayName: 'Taylor',
        age: 30,
        gender: 'Prefer not to say',
        displayNameChangeUsed: true,
        ageChangeUsed: true,
        genderChangeUsed: true,
        profileImageBase64: 'first-photo',
      );

      final firstUpdate = await store.updateProfile(
        userId: 'user-1',
        current: lockedProfile,
        displayName: 'Taylor',
        age: 30,
        gender: 'Prefer not to say',
        profileImageBase64: 'second-photo',
      );
      final secondUpdate = await store.updateProfile(
        userId: 'user-1',
        current: firstUpdate,
        displayName: 'Taylor',
        age: 30,
        gender: 'Prefer not to say',
        profileImageBase64: 'third-photo',
      );

      expect(secondUpdate.profileImageBase64, 'third-photo');
      expect(
        (await firestore.collection('users').doc('user-1').get())
            .data()?['profileImageBase64'],
        'third-photo',
      );
      expect(secondUpdate.displayNameChangeUsed, isTrue);
      expect(secondUpdate.ageChangeUsed, isTrue);
      expect(secondUpdate.genderChangeUsed, isTrue);
    },
  );
}
