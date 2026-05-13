part of '../app_repository.dart';

extension AppRepositoryNotifications on AppRepository {
  Future<void> loadNotificationDevices() async {
    final r = await get('/notifications/devices');
    if (r.statusCode != 200) return;

    notificationDevices = _extractDataList(r.body)
        .map((e) => notificationDeviceFromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String?> registerNotificationDevice({
    required String token,
    required String provider,
    required String platform,
    String? deviceName,
    bool enabled = true,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return 'Enter device token';

    final r = await post('/notifications/devices', {
      'token': cleanToken,
      'provider': provider,
      'platform': platform,
      if (deviceName != null && deviceName.trim().isNotEmpty)
        'device_name': deviceName.trim(),
      'enabled': enabled,
    });
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Could not register device (${r.statusCode})';
    }
    await loadNotificationDevices();
    return null;
  }

  Future<String?> updateNotificationDevice({
    required int tokenId,
    required bool enabled,
  }) async {
    final r = await patch('/notifications/devices/$tokenId', {
      'enabled': enabled,
    });
    if (r.statusCode != 200) {
      return parseError(r.body) ?? 'Could not update device (${r.statusCode})';
    }
    final idx = notificationDevices.indexWhere((d) => d.id == tokenId);
    if (idx >= 0) {
      final old = notificationDevices[idx];
      notificationDevices[idx] = NotificationDeviceModel(
        id: old.id,
        token: old.token,
        provider: old.provider,
        platform: old.platform,
        enabled: enabled,
        deviceName: old.deviceName,
        lastSuccessAt: old.lastSuccessAt,
        lastError: old.lastError,
      );
    }
    return null;
  }

  Future<String?> deleteNotificationDevice(int tokenId) async {
    final r = await delete('/notifications/devices/$tokenId');
    if (r.statusCode != 200 && r.statusCode != 204) {
      return parseError(r.body) ?? 'Could not delete device (${r.statusCode})';
    }
    notificationDevices.removeWhere((d) => d.id == tokenId);
    return null;
  }

  Future<String?> sendTestNotification() async {
    final r = await post('/notifications/test', {});
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      return parseError(r.body) ??
          'Could not send test notification (${r.statusCode})';
    }
    return null;
  }

  Future<String?> updateTelegramSettings({
    required String telegramChatId,
    required bool notificationsEnabled,
  }) async {
    final cleanChatId = telegramChatId.trim();
    final r = await put('/users/me/telegram', {
      'telegram_chat_id': cleanChatId.isEmpty ? null : cleanChatId,
      'notifications_enabled': notificationsEnabled,
    });
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Could not update Telegram settings (${r.statusCode})';
    }
    currentTelegramChatId = cleanChatId.isEmpty ? null : cleanChatId;
    currentNotificationsEnabled = notificationsEnabled;
    return null;
  }

  Future<String?> sendTelegramTest() async {
    final r = await post('/users/me/telegram/test', {});
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      return parseError(r.body) ??
          'Could not send Telegram test (${r.statusCode})';
    }
    return null;
  }

  NotificationDeviceModel notificationDeviceFromJson(Map<String, dynamic> j) {
    return NotificationDeviceModel(
      id: (j['id'] as num?)?.toInt() ?? (j['token_id'] as num?)?.toInt() ?? 0,
      token: j['token'] as String? ?? '',
      provider: j['provider'] as String? ?? 'fcm',
      platform: j['platform'] as String? ?? '',
      enabled: j['enabled'] as bool? ?? true,
      deviceName: j['device_name'] as String?,
      lastSuccessAt: j['last_success_at'] as String?,
      lastError: j['last_error'] as String?,
    );
  }

  Future<void> syncCurrentPushToken() async {
    try {
      if (token == null) return;
      final supported = await PushNotificationService.initialize();
      if (!supported) return;

      await PushNotificationService.requestPermission();
      final fcmToken = await PushNotificationService.getToken();
      if (fcmToken == null || fcmToken.trim().isEmpty) return;

      await registerNotificationDevice(
        token: fcmToken,
        provider: 'fcm',
        platform: defaultTargetPlatform.name,
        deviceName: _defaultDeviceName(),
      );
      _registeredPushToken = fcmToken;
      _listenForPushTokenRefresh();
    } catch (e) {
      debugPrint('Push token sync failed: $e');
    }
  }

  Future<void> removeCurrentPushToken() async {
    try {
      final supported = await PushNotificationService.initialize();
      if (!supported) return;

      final fcmToken =
          _registeredPushToken ?? await PushNotificationService.getToken();
      if (fcmToken == null || fcmToken.isEmpty) return;

      if (notificationDevices.isEmpty) {
        await loadNotificationDevices();
      }

      final device = notificationDevices
          .where((d) => d.token == fcmToken)
          .firstOrNull;
      if (device != null) {
        await deleteNotificationDevice(device.id);
      }

      _registeredPushToken = null;
      await PushNotificationService.deleteToken();
    } catch (e) {
      debugPrint('Push token cleanup failed: $e');
    }
  }

  void _listenForPushTokenRefresh() {
    _pushTokenRefreshSub ??= PushNotificationService.onTokenRefresh.listen((
      newToken,
    ) async {
      if (token == null || newToken.trim().isEmpty) return;
      await registerNotificationDevice(
        token: newToken,
        provider: 'fcm',
        platform: defaultTargetPlatform.name,
        deviceName: _defaultDeviceName(),
      );
      _registeredPushToken = newToken;
    });
  }

  String _defaultDeviceName() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iOS device',
      TargetPlatform.macOS => 'macOS device',
      TargetPlatform.windows => 'Windows device',
      TargetPlatform.linux => 'Linux device',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };
  }
}
