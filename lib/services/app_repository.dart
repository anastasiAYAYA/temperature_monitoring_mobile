import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/alarm_model.dart';
import '../models/audit_entry.dart';
import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../models/user_model.dart';

class AppRepository {
  String baseUrl = 'http://localhost:8000/api/v1';
  String? token;
  String? currentUser;
  UserRole role = UserRole.viewer;

  List<SensorModel> sensors = [];
  List<AlarmModel> alarms = [];
  List<AuditEntry> audit = [];
  List<LocationModel> locations = [];
  List<UserModel> subordinateUsers = [];

  Future<String?> login(String username, String password) async {
    try {
      final r = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      );
      if (r.statusCode != 200) return parseError(r.body) ?? 'Ошибка входа';
      token = (jsonDecode(r.body) as Map<String, dynamic>)['access_token'] as String?;
      final me = await get('/users/me');
      if (me.statusCode == 200) {
        final data = jsonDecode(me.body) as Map<String, dynamic>;
        currentUser = data['username'] as String?;
        role = parseRole((data['role'] as String?) ?? 'viewer');
      }
      return null;
    } catch (e) {
      return 'Сервер недоступен: $e';
    }
  }

  Future<String?> loadAll() async {
    if (token == null) return 'Нет токена';
    final s = await get('/sensors/');
    if (s.statusCode != 200) return parseError(s.body) ?? 'Не удалось получить датчики';
    final sensorsJson = jsonDecode(s.body) as List<dynamic>;
    sensors = sensorsJson.map((e) => sensorFromJson(e as Map<String, dynamic>)).toList();

    final a = await get('/alarms/');
    if (a.statusCode == 200) {
      alarms = (jsonDecode(a.body) as List<dynamic>).map((e) => alarmFromJson(e as Map<String, dynamic>)).toList();
    }

    final l = await get('/users/audit-logs?skip=0&limit=30');
    if (l.statusCode == 200) {
      audit = (jsonDecode(l.body) as List<dynamic>)
          .map(
            (e) => AuditEntry(
              user: 'ID ${(e as Map<String, dynamic>)['user_id']}',
              action: e['action'] as String? ?? '',
              time: (e['timestamp'] as String? ?? '').replaceFirst('T', ' '),
            ),
          )
          .toList();
    }

    final loc = await get('/locations/');
    if (loc.statusCode == 200) {
      locations = (jsonDecode(loc.body) as List<dynamic>)
          .map(
            (e) => LocationModel(
              id: ((e as Map<String, dynamic>)['id'] as num?)?.toInt() ?? 0,
              name: e['name'] as String? ?? '',
              imageUrl: e['image_url'] as String?,
            ),
          )
          .toList();
    } else if (role != UserRole.admin) {
      final mapByName = <String, int>{};
      for (final sensor in sensors) {
        mapByName.putIfAbsent(sensor.location, () => mapByName.length + 1);
      }
      locations = mapByName.entries.map((e) => LocationModel(id: e.value, name: e.key)).toList();
    }
    await loadSubordinates();
    return null;
  }

  Future<void> loadSubordinates() async {
    subordinateUsers = [];
    if (role == UserRole.admin) {
      final usersResponse = await get('/users/?skip=0&limit=200');
      if (usersResponse.statusCode == 200) {
        final data = jsonDecode(usersResponse.body) as List<dynamic>;
        subordinateUsers = data
            .map((e) => userFromJson(e as Map<String, dynamic>))
            .where((u) => u.role == 'editor' || u.role == 'viewer')
            .toList();
      }
      return;
    }

    if (role == UserRole.editor) {
      final viewersResponse = await get('/users/by-role/viewer?skip=0&limit=200');
      if (viewersResponse.statusCode == 200) {
        final data = jsonDecode(viewersResponse.body) as List<dynamic>;
        subordinateUsers = data.map((e) => userFromJson(e as Map<String, dynamic>)).toList();
      }
    }
  }

  Future<void> loadHistory(int sensorId, String period) async {
    final endpoint = period == 'День'
        ? '/telemetry/$sensorId/last-24h'
        : '/telemetry/$sensorId/history?limit=${period == 'Неделя' ? 120 : 240}';
    final r = await get(endpoint);
    if (r.statusCode != 200) return;
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final points = ((data['measurements'] as List<dynamic>?) ?? [])
        .map((e) => ((e as Map<String, dynamic>)['temperature'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final i = sensors.indexWhere((e) => e.id == sensorId);
    if (i >= 0 && points.isNotEmpty) {
      sensors[i].points = points;
    }
  }

  Future<String?> updateAlarm(int alarmId, String status, String comment) async {
    final r = await patch('/alarms/$alarmId', {'status': status, 'comment': comment});
    if (r.statusCode == 200) return null;
    return parseError(r.body) ?? 'Ошибка изменения тревоги';
  }

  Future<List<int>?> downloadReport(int sensorId, String format) async {
    final r = await get('/reports/download/$sensorId?format=$format');
    return r.statusCode == 200 ? r.bodyBytes : null;
  }

  Future<String?> createSensor({
    required String name,
    required int locationId,
    String? internalId,
    double posX = 30,
    double posY = 30,
  }) async {
    final r = await post('/sensors/create_sensor', {
      'name': name,
      'group_id': locationId,
      'internal_id': internalId,
      'pos_x': posX,
      'pos_y': posY,
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null;
    return parseError(r.body) ?? 'Не удалось добавить датчик';
  }

  Future<String?> updateSensorPosition({
    required int sensorId,
    required double posX,
    required double posY,
  }) async {
    final r = await patch('/sensors/$sensorId/position', {'pos_x': posX, 'pos_y': posY});
    if (r.statusCode == 200) return null;
    return parseError(r.body) ?? 'Не удалось обновить позицию датчика';
  }

  Future<String?> updateSensorThresholds({
    required int sensorId,
    required double warningMinTemp,
    required double warningMaxTemp,
    required double alarmMinTemp,
    required double alarmMaxTemp,
  }) async {
    final idx = sensors.indexWhere((e) => e.id == sensorId);
    if (idx < 0) return 'Датчик не найден';

    sensors[idx].warningMinTemp = warningMinTemp;
    sensors[idx].warningMaxTemp = warningMaxTemp;
    sensors[idx].alarmMinTemp = alarmMinTemp;
    sensors[idx].alarmMaxTemp = alarmMaxTemp;
    return null;
  }

  Future<String?> createLocation({
    required String name,
    String? imageUrl,
  }) async {
    final r = await post('/locations/', {
      'name': name,
      'image_url': imageUrl,
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null;
    return parseError(r.body) ?? 'Не удалось добавить локацию';
  }

  Future<String?> createUser({
    required String username,
    required String password,
    required String fullName,
    required String roleName,
    required int? locationId,
    String? email,
  }) async {
    final r = await post('/users/register', {
      'username': username,
      'password': password,
      'full_name': fullName,
      'role': roleName,
      'location_id': locationId,
      'email': email,
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null;
    return parseError(r.body) ?? 'Не удалось создать сотрудника';
  }

  void logout() {
    token = null;
    currentUser = null;
    role = UserRole.viewer;
    sensors = [];
    alarms = [];
    audit = [];
    locations = [];
  }

  SensorModel sensorFromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt() ?? 0;
    final temp = 19 + Random(id + 1).nextDouble() * 10;
    final hum = 22 + Random(id + 2).nextDouble() * 15;
    final state = (j['is_online'] == false)
        ? SensorState.critical
        : (((j['battery_level'] as num?)?.toInt() ?? 100) < 25 ? SensorState.warning : SensorState.normal);
    return SensorModel(
      id: id,
      name: (j['name'] as String?) ?? 'Датчик',
      groupId: (j['group_id'] as num?)?.toInt() ?? 0,
      location: 'Локация #${(j['group_id'] as num?)?.toInt() ?? 0}',
      temperature: temp,
      humidity: hum,
      state: state,
      x: ((j['pos_x'] as num?)?.toDouble() ?? Random().nextDouble() * 210).clamp(4, 220),
      y: ((j['pos_y'] as num?)?.toDouble() ?? Random().nextDouble() * 130).clamp(4, 150),
      points: [temp - 1, temp - 0.5, temp, temp + 0.3, temp + 0.1],
    );
  }

  UserModel userFromJson(Map<String, dynamic> j) {
    return UserModel(
      id: (j['id'] as num?)?.toInt() ?? 0,
      username: j['username'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      role: j['role'] as String? ?? 'viewer',
      email: j['email'] as String?,
    );
  }

  AlarmModel alarmFromJson(Map<String, dynamic> j) {
    final st = switch (j['status']) {
      'acknowledged' => AlarmStatus.acknowledged,
      'resolved' => AlarmStatus.resolved,
      _ => AlarmStatus.newAlarm,
    };
    return AlarmModel(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (j['alarm_type'] as String?) ?? 'Событие',
      description: (j['description'] as String?) ?? '',
      status: st,
    );
  }

  String? parseError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['detail'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: {'Authorization': 'Bearer $token'});

  Future<http.Response> post(String path, Map<String, dynamic> body) => http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

  Future<http.Response> patch(String path, Map<String, dynamic> body) => http.patch(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
}
