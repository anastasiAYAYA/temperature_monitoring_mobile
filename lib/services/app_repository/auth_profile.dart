part of '../app_repository.dart';

extension AppRepositoryAuthProfile on AppRepository {
  Future<String?> login(String username, String password) async {
    try {
      final r = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      );
      if (r.statusCode != 200) {
        return parseError(r.body) ?? 'Ошибка входа';
      }

      token =
          (jsonDecode(r.body) as Map<String, dynamic>)['access_token']
              as String?;

      final me = await get('/users/me');
      if (me.statusCode == 200) {
        final d = jsonDecode(me.body) as Map<String, dynamic>;
        currentUser = d['username'] as String?;
        currentUserFullName = d['full_name'] as String?;
        currentUserEmail = d['email'] as String?;
        currentTelegramChatId = d['telegram_chat_id'] as String?;
        currentNotificationsEnabled =
            d['notifications_enabled'] as bool? ?? true;
        currentUserId = (d['id'] as num?)?.toInt();
        currentLocationId = (d['location_id'] as num?)?.toInt();
        role = parseRole((d['role'] as String?) ?? 'viewer');
      }

      await syncCurrentPushToken();
      return null;
    } catch (e) {
      return 'Сервер недоступен: $e';
    }
  }

  Future<void> logout() async {
    await removeCurrentPushToken();
    await _pushTokenRefreshSub?.cancel();
    _pushTokenRefreshSub = null;

    _stopHeartbeatLoop();
    disconnectWebSocket();
    token = null;
    currentUser = null;
    currentUserFullName = null;
    currentUserEmail = null;
    currentTelegramChatId = null;
    currentNotificationsEnabled = true;
    currentUserId = null;
    currentLocationId = null;
    role = UserRole.viewer;
    sensors = [];
    alarms = [];
    audit = [];
    locations = [];
    subordinateUsers = [];
    controlUnits = [];
    notificationDevices = [];
  }

  Future<String?> updateProfile({String? fullName, String? email}) async {
    if (currentUserId == null) {
      return 'Не удалось определить ID пользователя';
    }

    final body = <String, dynamic>{};
    if (fullName != null && fullName.isNotEmpty) {
      body['full_name'] = fullName;
    }
    if (email != null && email.isNotEmpty) {
      body['email'] = email;
    }
    if (body.isEmpty) return null;

    final r = await patch('/users/${currentUserId!}', body);
    if (r.statusCode == 200 || r.statusCode == 201) {
      if (fullName != null) currentUserFullName = fullName;
      if (email != null) currentUserEmail = email;
      return null;
    }

    return parseError(r.body) ??
        'Не удалось обновить профиль (HTTP ${r.statusCode})';
  }
}
