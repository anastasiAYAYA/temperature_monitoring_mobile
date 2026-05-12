part of '../app_repository.dart';

extension AppRepositoryAuthProfile on AppRepository {
  Future<String?> login(String username, String password) async {
    // функция для авторизации
    try {
      final r = await http.post(
        // отправляем POST запрос
        Uri.parse('$baseUrl/auth/login'), // URL для авторизации
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
        }, // заголовки для запроса
        body: {'username': username, 'password': password}, // тело запроса
      );
      if (r.statusCode != 200)
        return parseError(r.body) ??
            'Ошибка входа'; // если статус код не 200, то возвращаем ошибку
      token =
          (jsonDecode(r.body) as Map<String, dynamic>)['access_token']
              as String?;
      final me = await get('/users/me'); // отправляем GET запрос
      if (me.statusCode == 200) {
        // если статус код 200, то получаем данные
        final d =
            jsonDecode(me.body) as Map<String, dynamic>; // декодируем JSON
        currentUser =
            d['username'] as String?; // username текущего пользователя
        currentUserFullName =
            d['full_name'] as String?; // полное имя текущего пользователя
        currentUserEmail = d['email'] as String?; // email текущего пользователя
        currentUserId = (d['id'] as num?)?.toInt(); // id текущего пользователя
        currentLocationId = (d['location_id'] as num?)
            ?.toInt(); // id текущей локации
        role = parseRole(
          (d['role'] as String?) ?? 'viewer',
        ); // роль текущего пользователя
      }
      return null; // возвращаем null
    } catch (e) {
      return 'Сервер недоступен: $e'; // возвращаем ошибку
    }
  }

  void logout() {
    // функция для выхода
    _stopHeartbeatLoop(); // останавливаем heartbeat
    disconnectWebSocket(); // останавливаем WS
    token = null;
    currentUser = null;
    currentUserFullName = null;
    currentUserEmail = null;
    currentUserId = null;
    currentLocationId = null; // очищаем данные
    role = UserRole.viewer; // роль текущего пользователя
    sensors = [];
    alarms = [];
    audit = [];
    locations = [];
    subordinateUsers = [];
    controlUnits = []; // очищаем списки
  } // функция для выхода

  // ── Профиль ───────────────────────────────────────────────────────────────
  Future<String?> updateProfile({String? fullName, String? email}) async {
    // функция для обновления профиля
    if (currentUserId == null)
      return 'Не удалось определить ID пользователя'; // если id текущего пользователя не найден, то возвращаем ошибку
    final body = <String, dynamic>{}; // тело запроса
    if (fullName != null && fullName.isNotEmpty)
      body['full_name'] =
          fullName; // если fullName не null и не пустая строка, то добавляем в тело запроса
    if (email != null && email.isNotEmpty)
      body['email'] =
          email; // если email не null и не пустая строка, то добавляем в тело запроса
    if (body.isEmpty)
      return null; // если тело запроса пустое, то возвращаем null
    final r = await patch(
      '/users/${currentUserId!}',
      body,
    ); // отправляем PATCH запрос
    if (r.statusCode == 200 || r.statusCode == 201) {
      // если статус код 200 или 201, то обновляем данные
      if (fullName != null)
        currentUserFullName =
            fullName; // если fullName не null, то обновляем fullName
      if (email != null)
        currentUserEmail = email; // если email не null, то обновляем email
      return null; // возвращаем null
    }
    return parseError(r.body) ??
        'Не удалось обновить профиль (HTTP ${r.statusCode})'; // возвращаем ошибку
  }

  // ── Загрузка всех данных ──────────────────────────────────────────────────
}
