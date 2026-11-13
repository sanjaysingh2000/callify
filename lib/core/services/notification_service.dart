import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/device_id_store.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[NotificationService] Background message received: ${message.messageId}',
  );
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final DeviceIdStore _deviceIdStore = DeviceIdStore();
  static bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'panel_notifications',
    'Panel Notifications',
    description: 'Notifications when new voice panels go live.',
    importance: Importance.high,
  );

  /// Initializes FCM permissions, retrieves & saves token, sets up foreground local notifications,
  /// and listens for incoming messages and token refreshes.
  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      debugPrint(
        '[NotificationService] Notifications are unavailable on this platform.',
      );
      return;
    }

    _initialized = true;

    try {
      // 1. Request notification permission
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint(
        '[NotificationService] Notification permission status: ${settings.authorizationStatus}',
      );

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // 2. Setup local notifications
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint(
            '[NotificationService] Local notification clicked: ${response.payload}',
          );
        },
      );

      // Create Android notification channel with high importance
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // iOS foreground presentation options
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Get FCM token and save to Firestore
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }

      // 4. Listen for token refresh
      _messaging.onTokenRefresh.listen(_onTokenRefresh);

      // 5. Handle foreground notifications with local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '[NotificationService] Foreground message received: ${message.messageId}',
        );
        final notification = message.notification;
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: message.data['panelId']?.toString(),
          );
        }
      });

      // 6. Handle background/terminated message tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          '[NotificationService] App opened from background message: ${message.data}',
        );
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[NotificationService] App launched from terminated notification: ${initialMessage.data}',
        );
      }
    } catch (e) {
      _initialized = false;
      debugPrint('[NotificationService] Initialization failed: $e');
    }
  }

  /// Called when the FCM token refreshes.
  static Future<void> _onTokenRefresh(String token) async {
    debugPrint('[NotificationService] FCM token refreshed');
    await _saveToken(token);
  }

  /// Gets deviceId from DeviceIdStore and writes to `users/{deviceId}`.
  static Future<void> _saveToken(String token) async {
    try {
      final deviceId = await _deviceIdStore.getOrCreateDeviceId();
      if (deviceId.isEmpty) {
        debugPrint(
          '[NotificationService] Device ID is empty; skipping token save.',
        );
        return;
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(deviceId);

      await userRef.set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[NotificationService] Saved FCM token for device: $deviceId');
    } catch (e) {
      debugPrint('[NotificationService] Failed to save FCM token: $e');
    }
  }
}
