import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.initialize();
}

class PushNotificationService {
  const PushNotificationService._();

  static bool _initialized = false;
  static bool _supported = false;

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static Future<bool> initialize() async {
    if (!isSupported) return false;
    if (_initialized) return _supported;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _supported = true;
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
      _supported = false;
    }

    _initialized = true;
    return _supported;
  }

  static Future<NotificationSettings?> requestPermission() async {
    if (!await initialize()) return null;
    return FirebaseMessaging.instance.requestPermission();
  }

  static Future<String?> getToken() async {
    if (!await initialize()) return null;
    return FirebaseMessaging.instance.getToken();
  }

  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  static Future<void> deleteToken() async {
    if (!await initialize()) return;
    await FirebaseMessaging.instance.deleteToken();
  }
}
