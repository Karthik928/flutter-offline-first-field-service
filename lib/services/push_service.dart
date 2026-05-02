// lib/services/push_service.dart
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushService {
  static const _kTokenKey = 'fcm_token';

  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications.',
    importance: Importance.max,
  );

  /// Call once at app start/login.
  static Future<void> init() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    // ✅ FIXED: named parameter
    await _fln.initialize(initSettings);

    await _fln
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, newToken);
      if (kDebugMode) {
        // ignore: avoid_print
        debugPrint('🔁 FCM token refreshed');
      }
    });
  }

  static Future<void> requestPermissionsIfNeeded() async {
    final androidFln = _fln
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final enabled =
        await (androidFln?.areNotificationsEnabled() ??
            Future<bool>.value(true));
    if (enabled == false) {
      await androidFln?.requestNotificationsPermission();
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  static final notificationClickStream =
      StreamController<Map<String, dynamic>>.broadcast();

  static Future<void> configureNotificationClicks() async {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      notificationClickStream.add(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      notificationClickStream.add(initialMessage.data);
    }
  }

  /// Enable banners while app is open
  static void enableForegroundBanners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
      final n = m.notification;
      if (n == null) return;

      // ✅ FIXED: named parameters
      await _fln.show(
        n.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _PushServiceIds.channelId,
            _PushServiceIds.channelName,
            channelDescription: _PushServiceIds.channelDesc,
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: (m.data['route'] ?? '').toString(),
      );
    });
  }

  static Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  static Future<String?> ensureToken() async {
    var token = await getStoredToken();
    if (token == null || token.isEmpty) {
      token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kTokenKey, token);
      }
    }
    return token;
  }
}

class _PushServiceIds {
  static const channelId = 'high_importance_channel';
  static const channelName = 'High Importance Notifications';
  static const channelDesc = 'Used for important notifications.';
}
