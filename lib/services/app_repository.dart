import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/alarm_model.dart';
import '../models/audit_entry.dart';
import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../models/user_model.dart';

class AppRepository {
  // Новый базовый URL из документации
  String baseUrl = 'http://157.90.127.202:8000/api/v1';
  String? token;
  String? currentUser;
  String? currentUserFullName;
  String? currentUserEmail;
  int?    currentUserId;
  int?    currentLocationId;
  UserRole role = UserRole.viewer;

  List<SensorModel>   sensors          = [];
  List<AlarmModel>    alarms           = [];
  List<AuditEntry>    audit            = [];
  List<LocationModel> locations        = [];
  List<UserModel>     subordinateUsers = [];
  List<Map<String, dynamic>> controlUnits = []; // ControlUnit objects

  List<dynamic> _extractDataList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'] as List<dynamic>;
      }
      return [];
    } catch (_) { return []; }
  }

  // ── Аутентификация ────────────────────────────────────────────────────────

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
        final d = jsonDecode(me.body) as Map<String, dynamic>;
        currentUser         = d['username']   as String?;
        currentUserFullName = d['full_name']  as String?;
        currentUserEmail    = d['email']      as String?;
        currentUserId       = (d['id']          as num?)?.toInt();
        currentLocationId   = (d['location_id'] as num?)?.toInt();
        role = parseRole((d['role'] as String?) ?? 'viewer');
      }
      return null;
    } catch (e) {
      return 'Сервер недоступен: $e';
    }
  }

  void logout() {
    _stopHeartbeatLoop();
    disconnectWebSocket(); // FIX: останавливаем WS при выходе
    token = null; currentUser = null; currentUserFullName = null;
    currentUserEmail = null; currentUserId = null; currentLocationId = null;
    role = UserRole.viewer;
    sensors = []; alarms = []; audit = []; locations = []; subordinateUsers = []; controlUnits = [];
  }

  // ── Профиль ───────────────────────────────────────────────────────────────

  Future<String?> updateProfile({String? fullName, String? email}) async {
    if (currentUserId == null) return 'Не удалось определить ID пользователя';
    final body = <String, dynamic>{};
    if (fullName != null && fullName.isNotEmpty) body['full_name'] = fullName;
    if (email    != null && email.isNotEmpty)    body['email']     = email;
    if (body.isEmpty) return null;
    final r = await patch('/users/${currentUserId!}', body);
    if (r.statusCode == 200 || r.statusCode == 201) {
      if (fullName != null) currentUserFullName = fullName;
      if (email    != null) currentUserEmail    = email;
      return null;
    }
    return parseError(r.body) ?? 'Не удалось обновить профиль (HTTP ${r.statusCode})';
  }

  // ── Загрузка всех данных ──────────────────────────────────────────────────

  Future<String?> loadAll() async {
    if (token == null) return 'Нет токена';

    final s = await get('/sensors/');
    if (s.statusCode != 200) return parseError(s.body) ?? 'Не удалось получить датчики';
    sensors = _extractDataList(s.body)
        .map((e) => sensorFromJson(e as Map<String, dynamic>))
        .toList();

    final a = await get('/alarms/');
    if (a.statusCode == 200) {
      final newAlarms = _extractDataList(a.body)
          .map((e) => alarmFromJson(e as Map<String, dynamic>))
          .toList();
      for (int i = 0; i < newAlarms.length; i++) {
        final old = alarms.where((o) => o.id == newAlarms[i].id).firstOrNull;
        if (old != null && newAlarms[i].comment == null && old.comment != null) {
          newAlarms[i] = AlarmModel(
            id: newAlarms[i].id, title: newAlarms[i].title,
            description: newAlarms[i].description,
            status: newAlarms[i].status, comment: old.comment,
          );
        }
      }
      alarms = newAlarms;
    }

    final loc = await get('/locations/');
    if (loc.statusCode == 200) {
      locations = _extractDataList(loc.body).map((e) => LocationModel(
        id:       ((e as Map<String, dynamic>)['id']   as num?)?.toInt() ?? 0,
        name:     e['name']      as String? ?? '',
        imageUrl: e['image_url'] as String?,
      )).toList();
    } else {
      final m = <String, int>{};
      for (final sensor in sensors) {
        m.putIfAbsent(sensor.location, () => m.length + 1);
      }
      locations = m.entries.map((e) => LocationModel(id: e.value, name: e.key)).toList();
    }

    // FIX: Обогащаем датчики реальными именами локаций из /locations/
    // sensorFromJson делает location = 'Локация #N', здесь заменяем на настоящее имя
    sensors = sensors.map((s) {
      final loc = locations.where((l) => l.id == s.groupId).firstOrNull;
      if (loc == null) return s;
      return SensorModel(
        id:                s.id,
        name:              s.name,
        groupId:           s.groupId,
        location:          loc.name, // реальное имя вместо "Локация #N"
        temperature:       s.temperature,
        humidity:          s.humidity,
        state:             s.state,
        x:                 s.x,
        y:                 s.y,
        points:            s.points,
        humidityPoints:    s.humidityPoints,
        controlUnitId:     s.controlUnitId,
        internalId:        s.internalId,
        alarmDelaySeconds: s.alarmDelaySeconds,
        isOnline:          s.isOnline,
        lastSeen:          s.lastSeen,
      )
        ..warningMinTemp = s.warningMinTemp
        ..warningMaxTemp = s.warningMaxTemp
        ..alarmMinTemp   = s.alarmMinTemp
        ..alarmMaxTemp   = s.alarmMaxTemp
        ..warningMinHum  = s.warningMinHum
        ..warningMaxHum  = s.warningMaxHum
        ..alarmMinHum    = s.alarmMinHum
        ..alarmMaxHum    = s.alarmMaxHum;
    }).toList();

    // ── Блоки управления ─────────────────────────────────────────────────
    final cu = await get('/control-units/');
    if (cu.statusCode == 200) {
      controlUnits = _extractDataList(cu.body)
          .cast<Map<String, dynamic>>()
          .toList();

      // Запускаем периодический heartbeat для всех ЦБУ
      startHeartbeatLoop();

      // Обогащаем датчики техническими данными из ControlUnit
      // FIX: power_status из API приходит как "mains" или "battery"
      // (не "power"), sensor_model.dart уже исправлен под "mains"
      for (int i = 0; i < sensors.length; i++) {
        final cuId = sensors[i].controlUnitId;
        if (cuId == null) continue;
        final unit = controlUnits.where((u) => (u['id'] as num?)?.toInt() == cuId).firstOrNull;
        if (unit == null) continue;
        final batteryLevel = (unit['battery_level'] as num?)?.toInt() ?? 100;
        final isOnline     = sensors[i].isOnline;
        final state        = !isOnline
            ? SensorState.critical
            : (batteryLevel < 25 ? SensorState.warning : SensorState.normal);
        sensors[i] = SensorModel(
          id:                sensors[i].id,
          name:              sensors[i].name,
          groupId:           sensors[i].groupId,
          location:          sensors[i].location,
          temperature:       sensors[i].temperature,
          humidity:          sensors[i].humidity,
          state:             state,
          x:                 sensors[i].x,
          y:                 sensors[i].y,
          points:            sensors[i].points,
          humidityPoints:    sensors[i].humidityPoints,
          controlUnitId:     sensors[i].controlUnitId,
          internalId:        sensors[i].internalId,
          alarmDelaySeconds: sensors[i].alarmDelaySeconds,
          // FIX: поле называется power_status, значения "mains"/"battery"
          powerStatus:       unit['power_status'] as String?,
          batteryLevel:      batteryLevel,
          simBalance:        (unit['sim_balance']  as num?)?.toDouble(),
          gsmSignal:         (unit['gsm_signal']   as num?)?.toInt(),
          isOnline:          sensors[i].isOnline,
          lastSeen:          sensors[i].lastSeen,
        )
          ..warningMinTemp = sensors[i].warningMinTemp
          ..warningMaxTemp = sensors[i].warningMaxTemp
          ..alarmMinTemp   = sensors[i].alarmMinTemp
          ..alarmMaxTemp   = sensors[i].alarmMaxTemp
          ..warningMinHum  = sensors[i].warningMinHum
          ..warningMaxHum  = sensors[i].warningMaxHum
          ..alarmMinHum    = sensors[i].alarmMinHum
          ..alarmMaxHum    = sensors[i].alarmMaxHum;
      }
    }

    await loadSubordinates();
    await loadAuditLog();
    return null;
  }

  Future<void> loadSubordinates() async {
    subordinateUsers = [];
    if (role == UserRole.admin) {
      final r = await get('/users/?skip=0&limit=200');
      if (r.statusCode == 200) {
        subordinateUsers = _extractDataList(r.body)
            .map((e) => userFromJson(e as Map<String, dynamic>))
            .where((u) => u.role == 'editor' || u.role == 'viewer')
            .toList();
      }
    } else if (role == UserRole.editor) {
      final r = await get('/users/by-role/viewer?skip=0&limit=200');
      if (r.statusCode == 200) {
        subordinateUsers = _extractDataList(r.body)
            .map((e) => userFromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
  }

  // ── Телеметрия ────────────────────────────────────────────────────────────
  // GET /api/v1/telemetry/{sensor_id}/latest   — последнее измерение
  // GET /api/v1/telemetry/{sensor_id}/history?limit=N — история

  Future<void> loadHistory(int sensorId, String period) async {
    // FIX: по документации API эндпоинты:
    //   /telemetry/{sensor_id}/latest           — одно последнее
    //   /telemetry/{sensor_id}/history?limit=N  — история (N точек)
    // Эндпоинт /last-24h в документации НЕ указан — используем history с limit.
    // День → 100 точек, Неделя → 300, Месяц → 600
    final int limit;
    switch (period) {
      case 'День':
        limit = 100;
      case 'Неделя':
        limit = 300;
      default: // Месяц
        limit = 600;
    }
    final endpoint = '/telemetry/$sensorId/history?limit=$limit';

    final r = await get(endpoint);
    if (r.statusCode != 200) return;

    List<dynamic> measurements = [];
    dynamic decoded;
    try {
      decoded = jsonDecode(r.body);
      if (decoded is List) {
        measurements = decoded;
      } else if (decoded is Map<String, dynamic>) {
        measurements = (decoded['measurements'] as List<dynamic>?) ?? [];
        if (measurements.isEmpty && decoded['latest'] != null) {
          measurements = [decoded['latest']];
        }
      }
    } catch (_) { return; }

    // FIX: Парсим все три поля вместе, чтобы индексы points/timestamps
    // всегда были синхронизированы. Точки с отсутствующими полями пропускаем.
    final tempPoints  = <double>[];
    final humPoints   = <double>[];
    final tsPoints    = <DateTime>[];
    for (final raw in measurements) {
      final m    = raw as Map<String, dynamic>;
      final temp = (m['temperature'] as num?)?.toDouble();
      final hum  = (m['humidity']    as num?)?.toDouble();
      final tsRaw = m['timestamp']  as String?;
      if (temp == null || hum == null || tsRaw == null) continue;
      DateTime? dt;
      try { dt = DateTime.parse(tsRaw); } catch (_) { continue; }
      tempPoints.add(temp);
      humPoints.add(hum);
      tsPoints.add(dt);
    }

    final i = sensors.indexWhere((e) => e.id == sensorId);
    if (i >= 0) {
      if (tempPoints.isNotEmpty) sensors[i].points         = tempPoints;
      if (humPoints.isNotEmpty)  sensors[i].humidityPoints = humPoints;
      if (tsPoints.isNotEmpty)   sensors[i].timestamps     = tsPoints;

      // Обновляем текущие показания из последнего измерения
      try {
        final latestRaw = decoded is Map<String, dynamic> ? decoded['latest'] : null;
        final last = latestRaw ?? (measurements.isNotEmpty ? measurements.last : null);
        if (last != null) {
          final lastMap = last as Map<String, dynamic>;
          sensors[i] = SensorModel(
            id:                sensors[i].id,
            name:              sensors[i].name,
            groupId:           sensors[i].groupId,
            location:          sensors[i].location,
            temperature:       (lastMap['temperature'] as num?)?.toDouble() ?? sensors[i].temperature,
            humidity:          (lastMap['humidity']    as num?)?.toDouble() ?? sensors[i].humidity,
            state:             sensors[i].state,
            x:                 sensors[i].x,
            y:                 sensors[i].y,
            points:            sensors[i].points,
            humidityPoints:    sensors[i].humidityPoints,
            timestamps:        sensors[i].timestamps,
            controlUnitId:     sensors[i].controlUnitId,
            internalId:        sensors[i].internalId,
            alarmDelaySeconds: sensors[i].alarmDelaySeconds,
            powerStatus:       sensors[i].powerStatus,
            batteryLevel:      sensors[i].batteryLevel,
            simBalance:        sensors[i].simBalance,
            gsmSignal:         sensors[i].gsmSignal,
            isOnline:          sensors[i].isOnline,
            lastSeen:          sensors[i].lastSeen,
          )
            ..warningMinTemp = sensors[i].warningMinTemp
            ..warningMaxTemp = sensors[i].warningMaxTemp
            ..alarmMinTemp   = sensors[i].alarmMinTemp
            ..alarmMaxTemp   = sensors[i].alarmMaxTemp
            ..warningMinHum  = sensors[i].warningMinHum
            ..warningMaxHum  = sensors[i].warningMaxHum
            ..alarmMinHum    = sensors[i].alarmMinHum
            ..alarmMaxHum    = sensors[i].alarmMaxHum;
        }
      } catch (_) {}
    }
  }

  /// GET /api/v1/telemetry/{sensor_id}/latest — одно последнее измерение
  Future<SensorLiveData?> getLatestTelemetry(int sensorId) async {
    try {
      final res = await get('/telemetry/$sensorId/latest');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // FIX: SensorLiveData.fromJson теперь защищён от null-полей
        return SensorLiveData.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Ошибка получения latest telemetry: $e');
      return null;
    }
  }

  // ── WebSocket: real-time обновления ──────────────────────────────────────
  // URL: ws://157.90.127.202:8000/ws/alarms
  // Событие: { "type": "new_measurement", "sensor_id": N, "temp": N, "hum": N, "is_alarm": bool }

  WebSocket? _wsChannel;
  void Function(int sensorId, double temp, double hum, bool isAlarm)? _wsCallback;
  bool _wsReconnecting = false;

  /// Подключает WebSocket для получения live-данных без polling.
  /// [onData] вызывается при каждом новом измерении — используйте для setState().
  void connectWebSocket(
    void Function(int sensorId, double temp, double hum, bool isAlarm) onData,
  ) {
    _wsCallback = onData;
    _wsReconnecting = false;
    _wsConnect();
  }

  void _wsConnect() {
    WebSocket.connect('ws://157.90.127.202:8000/ws/alarms').then((ws) {
      _wsChannel = ws;
      debugPrint('[WS] Подключён к ws/alarms');
      ws.listen(
        _wsOnData,
        onError: (_) => _wsScheduleReconnect(),
        onDone:  ()  => _wsScheduleReconnect(),
        cancelOnError: true,
      );
    }).catchError((e) {
      debugPrint('[WS] Ошибка подключения: $e');
      _wsScheduleReconnect();
    });
  }

  void _wsOnData(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      if (j['type'] != 'new_measurement') return;

      final sensorId = (j['sensor_id'] as num).toInt();
      final temp     = (j['temp']      as num).toDouble();
      final hum      = (j['hum']       as num).toDouble();
      final isAlarm  = j['is_alarm']   as bool? ?? false;
      // FIX: используем серверный timestamp если есть, иначе текущее время
      DateTime eventTime = DateTime.now();
      try {
        final tsRaw = j['timestamp'] as String?;
        if (tsRaw != null) eventTime = DateTime.parse(tsRaw);
      } catch (_) {}

      // Обновляем датчик в локальном списке
      final i = sensors.indexWhere((s) => s.id == sensorId);
      if (i >= 0) {
        final s = sensors[i];
        sensors[i] = SensorModel(
          id:                s.id,
          name:              s.name,
          groupId:           s.groupId,
          location:          s.location,
          temperature:       temp,
          humidity:          hum,
          state:             isAlarm ? SensorState.critical : SensorState.normal,
          x:                 s.x,
          y:                 s.y,
          points:            [
            ...(s.points.length >= 600 ? s.points.sublist(s.points.length - 599) : s.points),
            temp,
          ],
          humidityPoints:    [
            ...(s.humidityPoints.length >= 600 ? s.humidityPoints.sublist(s.humidityPoints.length - 599) : s.humidityPoints),
            hum,
          ],
          timestamps:        [
            ...(s.timestamps.length >= 600 ? s.timestamps.sublist(s.timestamps.length - 599) : s.timestamps),
            eventTime, // FIX: серверное время вместо DateTime.now()
          ],
          controlUnitId:     s.controlUnitId,
          internalId:        s.internalId,
          alarmDelaySeconds: s.alarmDelaySeconds,
          powerStatus:       s.powerStatus,
          batteryLevel:      s.batteryLevel,
          simBalance:        s.simBalance,
          gsmSignal:         s.gsmSignal,
          isOnline:          true,
          lastSeen:          s.lastSeen,
        )
          ..warningMinTemp = s.warningMinTemp
          ..warningMaxTemp = s.warningMaxTemp
          ..alarmMinTemp   = s.alarmMinTemp
          ..alarmMaxTemp   = s.alarmMaxTemp
          ..warningMinHum  = s.warningMinHum
          ..warningMaxHum  = s.warningMaxHum
          ..alarmMinHum    = s.alarmMinHum
          ..alarmMaxHum    = s.alarmMaxHum;
      }

      _wsCallback?.call(sensorId, temp, hum, isAlarm);
    } catch (e) {
      debugPrint('[WS] Ошибка парсинга: $e');
    }
  }

  void _wsScheduleReconnect() {
    if (_wsReconnecting || _wsCallback == null) return;
    _wsReconnecting = true;
    debugPrint('[WS] Реконнект через 5 сек...');
    Future.delayed(const Duration(seconds: 5), () {
      if (_wsCallback != null) {
        _wsReconnecting = false;
        _wsConnect();
      }
    });
  }

  void disconnectWebSocket() {
    _wsCallback = null;
    _wsReconnecting = false;
    _wsChannel?.close();
    _wsChannel = null;
    debugPrint('[WS] Отключён');
  }

  // ── Тревоги ───────────────────────────────────────────────────────────────
  // PATCH /alarms/{id}  { "status": "...", "user_comment": "..." }
  // Статусы: "new" | "in_progress" | "resolved"

  Future<String?> updateAlarm(int alarmId, String status, String comment) async {
    final body = <String, dynamic>{'status': status};
    if (comment.trim().isNotEmpty) body['user_comment'] = comment.trim();

    debugPrint('[alarm PATCH] body=$body');
    final r = await patch('/alarms/$alarmId', body);
    debugPrint('[alarm PATCH] status=${r.statusCode} body=${r.body}');

    if (r.statusCode == 200) {
      final data    = jsonDecode(r.body) as Map<String, dynamic>;
      final updated = alarmFromJson(data);
      final idx     = alarms.indexWhere((a) => a.id == alarmId);
      if (idx >= 0) alarms[idx] = updated;
      return null;
    }
    return parseError(r.body) ?? 'Ошибка изменения тревоги (${r.statusCode})';
  }

  // ── Датчики ───────────────────────────────────────────────────────────────
  // POST /sensors/create_sensor
  // PATCH /sensors/{id}/thresholds  — пороги устанавливаются отдельно

  Future<String?> createSensor({
    required String name,
    required int    locationId,
    int?    controlUnitId,
    String? internalId,
    double? warningMinTemp, double? warningMaxTemp,
    double? alarmMinTemp,   double? alarmMaxTemp,
    double? warningMinHum,  double? warningMaxHum,
    double? alarmMinHum,    double? alarmMaxHum,
    int     alarmDelaySeconds = 0,
  }) async {
    final createBody = <String, dynamic>{
      'name':     name,
      'group_id': locationId,
      if (controlUnitId      != null) 'control_unit_id':     controlUnitId,
      if (internalId         != null) 'internal_id':         internalId,
      if (warningMinTemp     != null) 'warning_min_temp':    warningMinTemp,
      if (warningMaxTemp     != null) 'warning_max_temp':    warningMaxTemp,
      if (alarmMinTemp       != null) 'alarm_min_temp':      alarmMinTemp,
      if (alarmMaxTemp       != null) 'alarm_max_temp':      alarmMaxTemp,
      if (warningMinHum      != null) 'warning_min_hum':     warningMinHum,
      if (warningMaxHum      != null) 'warning_max_hum':     warningMaxHum,
      if (alarmMinHum        != null) 'alarm_min_hum':       alarmMinHum,
      if (alarmMaxHum        != null) 'alarm_max_hum':       alarmMaxHum,
      'alarm_delay_seconds': alarmDelaySeconds,
    };
    final r = await post('/sensors/create_sensor', createBody);

    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ?? 'Не удалось добавить датчик (${r.statusCode})';
    }
    return null;
  }

  Future<String?> updateSensorPosition({
    required int sensorId, required double posX, required double posY,
  }) async {
    final r = await patch('/sensors/$sensorId', {'pos_x': posX, 'pos_y': posY});
    if (r.statusCode != 200) return parseError(r.body) ?? 'Не удалось сохранить позицию';
    final i = sensors.indexWhere((e) => e.id == sensorId);
    if (i >= 0) { sensors[i].x = posX; sensors[i].y = posY; }
    return null;
  }

  Future<String?> updateSensorThresholds({
    required int sensorId,
    required double warningMinTemp, required double warningMaxTemp,
    required double alarmMinTemp,   required double alarmMaxTemp,
    double? warningMinHum, double? warningMaxHum,
    double? alarmMinHum,   double? alarmMaxHum,
  }) async {
    final idx = sensors.indexWhere((e) => e.id == sensorId);
    if (idx < 0) return 'Датчик не найден';
    final body = <String, dynamic>{
      'warning_min_temp': warningMinTemp, 'warning_max_temp': warningMaxTemp,
      'alarm_min_temp':   alarmMinTemp,   'alarm_max_temp':   alarmMaxTemp,
      if (warningMinHum != null) 'warning_min_hum': warningMinHum,
      if (warningMaxHum != null) 'warning_max_hum': warningMaxHum,
      if (alarmMinHum   != null) 'alarm_min_hum':   alarmMinHum,
      if (alarmMaxHum   != null) 'alarm_max_hum':   alarmMaxHum,
    };
    final r = await patch('/sensors/$sensorId/thresholds', body);
    if (r.statusCode != 200) return parseError(r.body) ?? 'Не удалось сохранить пороги (${r.statusCode})';
    sensors[idx]
      ..warningMinTemp = warningMinTemp ..warningMaxTemp = warningMaxTemp
      ..alarmMinTemp   = alarmMinTemp   ..alarmMaxTemp   = alarmMaxTemp
      ..warningMinHum  = warningMinHum  ..warningMaxHum  = warningMaxHum
      ..alarmMinHum    = alarmMinHum    ..alarmMaxHum    = alarmMaxHum;
    return null;
  }

  /// POST /control-units/register — регистрация ЦБУ/AlertBox
  Future<({String? error, String? ingestionToken})> createControlUnit({
    required String name,
    required int    locationId,
    required String serialNumber,
    String? devEui,
    String? appKey,
  }) async {
    final body = <String, dynamic>{
      'name':          name,
      'group_id':      locationId,
      'serial_number': serialNumber,
      if (devEui != null && devEui.isNotEmpty) 'dev_eui': devEui,
      if (appKey != null && appKey.isNotEmpty) 'app_key': appKey,
    };
    final r = await post('/control-units/register', body);
    if (r.statusCode == 200 || r.statusCode == 201) {
      String? ingestionToken;
      try {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        ingestionToken = data['ingestion_token'] as String?;
        final cuList = await get('/control-units/');
        if (cuList.statusCode == 200) {
          controlUnits = _extractDataList(cuList.body).cast<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
      return (error: null, ingestionToken: ingestionToken);
    }
    return (
      error: parseError(r.body) ?? 'Не удалось создать блок управления (${r.statusCode})',
      ingestionToken: null,
    );
  }

  /// POST /control-units/heartbeat — периодическая отправка heartbeat от ЦБУ.
  Future<void> sendHeartbeat({
    required String serialNumber,
    required String ingestionToken,
    int?    batteryLevel,
    String? powerStatus,
    int?    gsmSignal,
  }) async {
    try {
      final body = <String, dynamic>{
        'serial_number': serialNumber,
        'token':         ingestionToken,
        if (batteryLevel != null) 'battery_level': batteryLevel,
        if (powerStatus  != null) 'power_status':  powerStatus,
        if (gsmSignal    != null) 'gsm_signal':     gsmSignal,
      };
      await http.post(
        Uri.parse('$baseUrl/control-units/heartbeat'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[heartbeat] Ошибка: $e');
    }
  }

  void startHeartbeatLoop() {
    _stopHeartbeatLoop();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      for (final unit in controlUnits) {
        final serialNumber    = unit['serial_number'] as String?;
        final ingestionToken  = unit['ingestion_token'] as String?;
        if (serialNumber == null || ingestionToken == null) continue;
        await sendHeartbeat(
          serialNumber:   serialNumber,
          ingestionToken: ingestionToken,
          batteryLevel:   (unit['battery_level'] as num?)?.toInt(),
          powerStatus:    unit['power_status']  as String?,
          gsmSignal:      (unit['gsm_signal']   as num?)?.toInt(),
        );
      }
    });
  }

  void _stopHeartbeatLoop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Timer? _heartbeatTimer;

  void stopHeartbeatLoop() => _stopHeartbeatLoop();

  /// POST /api/v1/sensors/{sensor_id}/set-medication?drug_name=...
  /// ИИ автоматически устанавливает пороги по названию препарата
  Future<String?> setSensorMedication({
    required int sensorId,
    required String drugName,
  }) async {
    final uri = Uri.parse('$baseUrl/sensors/$sensorId/set-medication')
        .replace(queryParameters: {'drug_name': drugName});
    final r = await http.post(uri,
        headers: {'Authorization': 'Bearer $token'}).timeout(_kTimeout);
    if (r.statusCode == 200) {
      try {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final idx  = sensors.indexWhere((e) => e.id == sensorId);
        if (idx >= 0) {
          sensors[idx].warningMinTemp = _thresh(data['warning_min_temp']);
          sensors[idx].warningMaxTemp = _thresh(data['warning_max_temp']);
          sensors[idx].alarmMinTemp   = _thresh(data['alarm_min_temp']);
          sensors[idx].alarmMaxTemp   = _thresh(data['alarm_max_temp']);
          sensors[idx].alarmMinHum    = _thresh(data['alarm_min_hum']);
          sensors[idx].alarmMaxHum    = _thresh(data['alarm_max_hum']);
        }
      } catch (_) {}
      return null;
    }
    if (r.statusCode == 503) return 'ИИ-сервис временно недоступен. Попробуйте позже.';
    return parseError(r.body) ?? 'Ошибка настройки порогов (${r.statusCode})';
  }

  // ── Локации ───────────────────────────────────────────────────────────────

  Future<String?> createLocation({required String name}) async {
    try {
      // FIX: сервер ожидает multipart/form-data, а не JSON.
      // Используем MultipartRequest чтобы передать поле name как form-поле.
      final uri     = Uri.parse('$baseUrl/locations/');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['name'] = name;
      final response = await http.Response.fromStream(
        await request.send().timeout(_kTimeout),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Добавляем новую локацию в локальный список сразу, без лишнего reload
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final id   = (data['id'] as num?)?.toInt();
          final nm   = data['name'] as String? ?? name;
          if (id != null) {
            locations.add(LocationModel(id: id, name: nm));
          }
        } catch (_) {}
        return null;
      }
      return parseError(response.body) ?? 'Не удалось добавить локацию (${response.statusCode})';
    } catch (e) {
      return 'Ошибка создания локации: $e';
    }
  }

  Future<String?> uploadLocationPlan({
    required int locationId,
    required Uint8List fileBytes,
    required String mimeType,
    String? fileName,
  }) async {
    try {
      final uri     = Uri.parse('$baseUrl/locations/$locationId/upload-plan');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'plan',
          contentType: MediaType.parse(mimeType),
        ));
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200 || response.statusCode == 201) {
        final newUrl = (jsonDecode(response.body) as Map<String, dynamic>)['image_url'] as String?;
        final idx    = locations.indexWhere((l) => l.id == locationId);
        if (idx >= 0 && newUrl != null) {
          locations[idx] = LocationModel(id: locations[idx].id, name: locations[idx].name, imageUrl: newUrl);
        }
        return null;
      }
      return parseError(response.body) ?? 'Не удалось загрузить план';
    } catch (e) { return 'Ошибка загрузки файла: $e'; }
  }

  // ── Отчёты ────────────────────────────────────────────────────────────────

  Future<List<int>?> downloadReportByPeriod({
    required int sensorId, required String period, required String format,
    DateTime? startDate, DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date']   = _fmtDate(endDate);
    }
    final uri = Uri.parse('$baseUrl/reports/download-period/$sensorId').replace(queryParameters: params);
    final r   = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    return r.statusCode == 200 ? r.bodyBytes : null;
  }

  Future<List<int>?> downloadLocationReportByPeriod({
    required int locationId, required String period, required String format,
    DateTime? startDate, DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date']   = _fmtDate(endDate);
    }
    final uri = Uri.parse('$baseUrl/reports/download-period-location/$locationId').replace(queryParameters: params);
    final r   = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    return r.statusCode == 200 ? r.bodyBytes : null;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Смена пароля текущего пользователя.
  Future<String?> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (currentUserId == null) return 'Не удалось определить пользователя';
    final r = await patch('/users/${currentUserId!}', {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
    if (r.statusCode == 200) return null;
    return parseError(r.body) ?? 'Не удалось сменить пароль (${r.statusCode})';
  }

  /// GET /users/audit-logs — журнал действий
  Future<void> loadAuditLog() async {
    final r = await get('/users/audit-logs?skip=0&limit=100');
    if (r.statusCode != 200) return;

    // Кешируем имена пользователей: user_id -> отображаемое имя
    final userNames = <int, String>{};
    if (currentUserId != null) {
      final displayName = (currentUserFullName?.isNotEmpty == true)
          ? currentUserFullName!
          : (currentUser ?? '');
      if (displayName.isNotEmpty) userNames[currentUserId!] = displayName;
    }
    for (final u in subordinateUsers) {
      userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
    }

    audit = _extractDataList(r.body).map((e) {
      final j     = e as Map<String, dynamic>;
      final uid   = (j['user_id'] as num?)?.toInt() ?? 0;
      final tsRaw = j['timestamp'] as String? ?? '';

      // Форматируем timestamp в локальное время
      String timeFormatted = tsRaw;
      try {
        final dt    = DateTime.parse(tsRaw).toLocal();
        final h     = dt.hour  .toString().padLeft(2, '0');
        final mn    = dt.minute.toString().padLeft(2, '0');
        final day   = dt.day   .toString().padLeft(2, '0');
        final month = dt.month .toString().padLeft(2, '0');
        timeFormatted = '$day.$month.${dt.year}  $h:$mn';
      } catch (_) {}

      return AuditEntry(
        user:   userNames[uid] ?? 'ID:$uid',
        action: j['action'] as String? ?? '',
        time:   timeFormatted,
      );
    }).toList();
  }

  // ── Пользователи ──────────────────────────────────────────────────────────

  Future<String?> createUser({
    required String username, required String password,
    required String fullName, required String roleName,
    required int? locationId, String? email,
  }) async {
    final r = await post('/users/register', {
      'username': username, 'password': password,
      'full_name': fullName, 'role': roleName,
      'location_id': locationId,
      if (email != null) 'email': email,
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null;
    return parseError(r.body) ?? 'Не удалось создать сотрудника';
  }

  // ── Парсеры ───────────────────────────────────────────────────────────────

  SensorModel sensorFromJson(Map<String, dynamic> j) {
    final id       = (j['id'] as num?)?.toInt() ?? 0;
    final isOnline = j['is_online'] != false;
    final state    = isOnline ? SensorState.normal : SensorState.critical;

    final sensor = SensorModel(
      id:                  id,
      name:                j['name']      as String? ?? 'Датчик',
      groupId:             (j['group_id'] as num?)?.toInt() ?? 0,
      // Временное значение — будет перезаписано реальным именем в loadAll()
      // после загрузки локаций из /locations/
      location:            'Локация #${(j['group_id'] as num?)?.toInt() ?? 0}',
      temperature:         0.0,
      humidity:            0.0,
      state:               state,
      x:                   (j['pos_x'] as num?)?.toDouble() ?? 10.0,
      y:                   (j['pos_y'] as num?)?.toDouble() ?? 10.0,
      points:              [],
      humidityPoints:      [],
      controlUnitId:       (j['control_unit_id']     as num?)?.toInt(),
      internalId:          j['internal_id']           as String?,
      alarmDelaySeconds:   (j['alarm_delay_seconds'] as num?)?.toInt() ?? 0,
      isOnline:            isOnline,
      lastSeen:            j['last_seen']     as String?,
    );

    sensor.warningMinTemp = _thresh(j['warning_min_temp']);
    sensor.warningMaxTemp = _thresh(j['warning_max_temp']);
    sensor.alarmMinTemp   = _thresh(j['alarm_min_temp']);
    sensor.alarmMaxTemp   = _thresh(j['alarm_max_temp']);
    sensor.warningMinHum  = _thresh(j['warning_min_hum']);
    sensor.warningMaxHum  = _thresh(j['warning_max_hum']);
    sensor.alarmMinHum    = _thresh(j['alarm_min_hum']);
    sensor.alarmMaxHum    = _thresh(j['alarm_max_hum']);
    return sensor;
  }

  /// Парсит порог из JSON.
  /// null → не задан. Любое число включая 0.0 → валидное значение.
  double? _thresh(dynamic v) {
    if (v == null) return null;
    return (v as num).toDouble();
  }

  AlarmModel alarmFromJson(Map<String, dynamic> j) {
    final st = switch (j['status'] as String? ?? '') {
      'acknowledged' => AlarmStatus.acknowledged,
      'resolved'     => AlarmStatus.resolved,
      _              => AlarmStatus.newAlarm,
    };
    final sev = switch (j['severity'] as String? ?? '') {
      'critical' => AlarmSeverity.critical,
      'info'     => AlarmSeverity.info,
      _          => AlarmSeverity.warning,
    };

    final alarmType = j['alarm_type'] as String?;
    final title = switch (alarmType) {
      'temperature'     => 'Температура вне нормы',
      'humidity'        => 'Влажность вне нормы',
      'connection_lost' => 'Потеря связи',
      'low_battery'     => 'Низкий заряд батареи',
      _                 => alarmType ?? (j['severity'] as String?) ?? 'Событие',
    };

    return AlarmModel(
      id:            (j['id']   as num?)?.toInt()    ?? 0,
      title:         title,
      description:   (j['description']  as String?)  ?? '',
      status:        st,
      sensorId:      (j['sensor_id']    as num?)?.toInt(),
      severity:      sev,
      alarmType:     alarmType,
      timestamp:     j['timestamp']     as String?,
      comment:       (j['user_comment'] as String?)  ?? (j['comment'] as String?),
      resolvedAt:    j['resolved_at']   as String?,
      resolvedById:  (j['resolved_by_id'] as num?)?.toInt(),
    );
  }

  UserModel userFromJson(Map<String, dynamic> j) => UserModel(
        id:       (j['id'] as num?)?.toInt() ?? 0,
        username: j['username']  as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        role:     j['role']      as String? ?? 'viewer',
        email:    j['email']     as String?,
      );

  String? parseError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['detail'] as String?;
    } catch (_) { return null; }
  }

  // ── HTTP хелперы ──────────────────────────────────────────────────────────

  static const _kTimeout = Duration(seconds: 12);

  Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'),
          headers: {'Authorization': 'Bearer $token'}).timeout(_kTimeout);

  Future<http.Response> post(String path, Map<String, dynamic> body) =>
      http.post(Uri.parse('$baseUrl$path'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(body)).timeout(_kTimeout);

  Future<http.Response> patch(String path, Map<String, dynamic> body) =>
      http.patch(Uri.parse('$baseUrl$path'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(body)).timeout(_kTimeout);
}