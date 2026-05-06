import 'dart:async'; // асинхронные операции, Future, Stream, etc.
import 'dart:convert'; // конвертер данных, JSON, XML, HTML, CSV, etc.
import 'dart:io'; // IO для Flutter, файловая система
import 'dart:typed_data'; // типы данных, Uint8List, etc.
import 'package:flutter/foundation.dart'; // Foundation для Flutter, основные классы и функции
import 'package:http/http.dart' as http; // HTTP клиент, HTTP запросы
import 'package:http_parser/http_parser.dart'; // парсер HTTP, парсинг HTTP запросов, Content-Type, etc.

import '../models/alarm_model.dart'; // модель аларма
import '../models/audit_entry.dart'; // модель аудита
import '../models/location_details.dart'; // модель деталей локации
import '../models/location_model.dart'; // модель локации
import '../models/sensor_model.dart'; // модель датчика
import '../models/user_role.dart'; // модель роли пользователя
import '../models/user_model.dart'; // модель пользователя

class AppRepository { // класс для работы с данными
  String baseUrl = 'http://157.90.127.202:8000/api/v1'; // базовый URL
  String? token; // токен авторизации
  String? currentUser; // текущий пользователь
  String? currentUserFullName; // полное имя текущего пользователя
  String? currentUserEmail; // email текущего пользователя
  int?    currentUserId; // id текущего пользователя
  int?    currentLocationId; // id текущей локации
  UserRole role = UserRole.viewer; // роль текущего пользователя

  List<SensorModel>   sensors          = []; // список датчиков
  List<AlarmModel>    alarms           = []; // список алармов
  List<AuditEntry>    audit            = []; // список аудитов
  List<LocationModel> locations        = []; // список локаций
  List<UserModel>     subordinateUsers = []; // список подчиненных пользователей
  List<Map<String, dynamic>> controlUnits = []; // список ЦБУ

  List<dynamic> _extractDataList(String body) { // функция для извлечения списка данных
    try {
      final decoded = jsonDecode(body); // декодируем JSON
      if (decoded is List) return decoded; // если decoded является списком, то возвращаем его
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) { // если decoded является мапой и содержит ключ 'data', то возвращаем список данных
        return decoded['data'] as List<dynamic>;
      }
      return []; // возвращаем пустой список
    } catch (_) { return []; }
  }

  // ── Аутентификация ────────────────────────────────────────────────────────

  Future<String?> login(String username, String password) async { // функция для авторизации
    try {
      final r = await http.post( // отправляем POST запрос
        Uri.parse('$baseUrl/auth/login'), // URL для авторизации
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'}, // заголовки для запроса
        body: {'username': username, 'password': password}, // тело запроса
      );
      if (r.statusCode != 200) return parseError(r.body) ?? 'Ошибка входа'; // если статус код не 200, то возвращаем ошибку
      token = (jsonDecode(r.body) as Map<String, dynamic>)['access_token'] as String?;
      final me = await get('/users/me'); // отправляем GET запрос
      if (me.statusCode == 200) { // если статус код 200, то получаем данные
        final d = jsonDecode(me.body) as Map<String, dynamic>; // декодируем JSON
        currentUser         = d['username']   as String?; // username текущего пользователя
        currentUserFullName = d['full_name']  as String?; // полное имя текущего пользователя
        currentUserEmail    = d['email']      as String?; // email текущего пользователя
        currentUserId       = (d['id']          as num?)?.toInt(); // id текущего пользователя
        currentLocationId   = (d['location_id'] as num?)?.toInt(); // id текущей локации
        role = parseRole((d['role'] as String?) ?? 'viewer'); // роль текущего пользователя
      }
      return null; // возвращаем null
    } catch (e) {
      return 'Сервер недоступен: $e'; // возвращаем ошибку
    }
  }

  void logout() { // функция для выхода
    _stopHeartbeatLoop(); // останавливаем heartbeat
    disconnectWebSocket(); // останавливаем WS
    token = null; currentUser = null; currentUserFullName = null;
    currentUserEmail = null; currentUserId = null; currentLocationId = null; // очищаем данные
    role = UserRole.viewer; // роль текущего пользователя
    sensors = []; alarms = []; audit = []; locations = []; subordinateUsers = []; controlUnits = []; // очищаем списки
  } // функция для выхода

  // ── Профиль ───────────────────────────────────────────────────────────────
  Future<String?> updateProfile({String? fullName, String? email}) async { // функция для обновления профиля
    if (currentUserId == null) return 'Не удалось определить ID пользователя'; // если id текущего пользователя не найден, то возвращаем ошибку
    final body = <String, dynamic>{}; // тело запроса
    if (fullName != null && fullName.isNotEmpty) body['full_name'] = fullName; // если fullName не null и не пустая строка, то добавляем в тело запроса
    if (email    != null && email.isNotEmpty)    body['email']     = email; // если email не null и не пустая строка, то добавляем в тело запроса
    if (body.isEmpty) return null; // если тело запроса пустое, то возвращаем null
    final r = await patch('/users/${currentUserId!}', body); // отправляем PATCH запрос
    if (r.statusCode == 200 || r.statusCode == 201) { // если статус код 200 или 201, то обновляем данные
      if (fullName != null) currentUserFullName = fullName; // если fullName не null, то обновляем fullName
      if (email    != null) currentUserEmail    = email; // если email не null, то обновляем email
      return null; // возвращаем null
    }
    return parseError(r.body) ?? 'Не удалось обновить профиль (HTTP ${r.statusCode})'; // возвращаем ошибку
  }  

  // ── Загрузка всех данных ──────────────────────────────────────────────────

  Future<String?> loadAll() async { // загрузка датчиков, тревог, локаций, ЦБУ, подчинённых, аудита
    if (token == null) return 'Нет токена'; // без авторизации запросы бессмысленны

    final s = await get('/sensors/'); // GET список датчиков
    if (s.statusCode != 200) return parseError(s.body) ?? 'Не удалось получить датчики'; // ошибка HTTP
    sensors = _extractDataList(s.body) // парсим массив из JSON
        .map((e) => sensorFromJson(e as Map<String, dynamic>)) // каждый элемент → SensorModel
        .toList(); // материализуем список

    final a = await get('/alarms/'); // GET список тревог
    if (a.statusCode == 200) { // успешный ответ
      final newAlarms = _extractDataList(a.body) // список из тела ответа
          .map((e) => alarmFromJson(e as Map<String, dynamic>)) // парсинг AlarmModel
          .toList(); // новый список тревог с сервера
      for (int i = 0; i < newAlarms.length; i++) { // проходим по каждой новой тревоге
        final old = alarms.where((o) => o.id == newAlarms[i].id).firstOrNull; // старая версия по id
        if (old != null && newAlarms[i].comment == null && old.comment != null) { // сохраняем локальный комментарий
          newAlarms[i] = AlarmModel( // пересобираем модель с сохранённым comment
            id: newAlarms[i].id, title: newAlarms[i].title, // id и заголовок с сервера
            description: newAlarms[i].description, // описание с сервера
            status: newAlarms[i].status, comment: old.comment, // статус новый, комментарий старый
          );
        }
      }
      alarms = newAlarms; // заменяем кеш тревог
    }

    final loc = await get('/locations/'); // GET список локаций (компаний)
    if (loc.statusCode == 200) { // API вернул список
      locations = _extractDataList(loc.body).map((e) => LocationModel( // парсим локации
        id:       ((e as Map<String, dynamic>)['id']   as num?)?.toInt() ?? 0, // id группы
        name:     e['name']      as String? ?? '', // отображаемое имя
        imageUrl: e['image_url'] as String?, // URL плана этажа (если есть)
      )).toList(); // список LocationModel
    } else { // локации недоступны — синтетический список из строк sensor.location
      final m = <String, int>{}; // имя локации → синтетический id
      for (final sensor in sensors) { // для каждого датчика
        m.putIfAbsent(sensor.location, () => m.length + 1); // уникальный номер для каждой строки
      }
      locations = m.entries.map((e) => LocationModel(id: e.value, name: e.key)).toList(); // псевдо-локации
    }

    // FIX: Обогащаем датчики реальными именами локаций из /locations/
    // sensorFromJson делает location = 'Локация #N', здесь заменяем на настоящее имя
    sensors = sensors.map((s) { // пересобираем каждый датчик
      final loc = locations.where((l) => l.id == s.groupId).firstOrNull; // локация по groupId
      if (loc == null) return s; // не нашли — оставляем как есть
      return SensorModel( // копия с исправленным полем location
        id:                s.id, // id датчика
        name:              s.name, // имя
        groupId:           s.groupId, // id группы
        location:          loc.name, // реальное имя вместо "Локация #N"
        temperature:       s.temperature, // текущая температура
        humidity:          s.humidity, // текущая влажность
        state:             s.state, // агрегированное состояние
        x:                 s.x, // позиция X на плане (0–1)
        y:                 s.y, // позиция Y на плане (0–1)
        points:            s.points, // история температуры для графика
        humidityPoints:    s.humidityPoints, // история влажности
        controlUnitId:     s.controlUnitId, // привязка к ЦБУ
        internalId:        s.internalId, // внутренний id на устройстве
        alarmDelaySeconds: s.alarmDelaySeconds, // задержка перед тревогой
        isOnline:          s.isOnline, // признак онлайн
        lastSeen:          s.lastSeen, // время последней связи
      )
        ..warningMinTemp = s.warningMinTemp // порог предупреждения мин t
        ..warningMaxTemp = s.warningMaxTemp // порог предупреждения макс t
        ..alarmMinTemp   = s.alarmMinTemp // порог аварии мин t
        ..alarmMaxTemp   = s.alarmMaxTemp // порог аварии макс t
        ..warningMinHum  = s.warningMinHum // порог предупреждения мин влажность
        ..warningMaxHum  = s.warningMaxHum // порог предупреждения макс влажность
        ..alarmMinHum    = s.alarmMinHum // порог аварии мин влажность
        ..alarmMaxHum    = s.alarmMaxHum; // порог аварии макс влажность
    }).toList(); // обновлённый список датчиков

    // ── Блоки управления ─────────────────────────────────────────────────
    final cu = await get('/control-units/'); // GET все ЦБУ
    if (cu.statusCode == 200) { // успех
      controlUnits = _extractDataList(cu.body) // массив объектов ЦБУ
          .cast<Map<String, dynamic>>() // приводим к типу карты
          .toList(); // сохраняем в репозитории

      // Запускаем периодический heartbeat для всех ЦБУ
      startHeartbeatLoop(); // таймер раз в 30 с шлёт heartbeat

      // Обогащаем датчики техническими данными из ControlUnit
      // FIX: power_status из API приходит как "mains" или "battery"
      // (не "power"), sensor_model.dart уже исправлен под "mains"
      for (int i = 0; i < sensors.length; i++) { // каждый датчик
        final cuId = sensors[i].controlUnitId; // id блока управления
        if (cuId == null) continue; // без ЦБУ — пропуск
        final unit = controlUnits.where((u) => (u['id'] as num?)?.toInt() == cuId).firstOrNull; // найти ЦБУ
        if (unit == null) continue; // не найден — пропуск
        final batteryLevel = (unit['battery_level'] as num?)?.toInt() ?? 100; // уровень батареи %
        final isOnline     = sensors[i].isOnline; // онлайн датчика
        final state        = !isOnline // состояние для UI
            ? SensorState.critical // офлайн — критично
            : (batteryLevel < 25 ? SensorState.warning : SensorState.normal); // низкий заряд — предупреждение
        sensors[i] = SensorModel( // пересобираем датчик с полями из ЦБУ
          id:                sensors[i].id, // id
          name:              sensors[i].name, // имя
          groupId:           sensors[i].groupId, // группа
          location:          sensors[i].location, // локация
          temperature:       sensors[i].temperature, // температура
          humidity:          sensors[i].humidity, // влажность
          state:             state, // вычисленное состояние
          x:                 sensors[i].x, // X
          y:                 sensors[i].y, // Y
          points:            sensors[i].points, // точки графика t
          humidityPoints:    sensors[i].humidityPoints, // точки графика h
          controlUnitId:     sensors[i].controlUnitId, // ЦБУ id
          internalId:        sensors[i].internalId, // internal id
          alarmDelaySeconds: sensors[i].alarmDelaySeconds, // задержка тревоги
          // FIX: поле называется power_status, значения "mains"/"battery"
          powerStatus:       unit['power_status'] as String?, // сеть/аккум
          batteryLevel:      batteryLevel, // %
          simBalance:        (unit['sim_balance']  as num?)?.toDouble(), // баланс SIM
          gsmSignal:         (unit['gsm_signal']   as num?)?.toInt(), // уровень GSM
          isOnline:          sensors[i].isOnline, // онлайн
          lastSeen:          sensors[i].lastSeen, // last seen
        )
          ..warningMinTemp = sensors[i].warningMinTemp // копируем пороги
          ..warningMaxTemp = sensors[i].warningMaxTemp
          ..alarmMinTemp   = sensors[i].alarmMinTemp
          ..alarmMaxTemp   = sensors[i].alarmMaxTemp
          ..warningMinHum  = sensors[i].warningMinHum
          ..warningMaxHum  = sensors[i].warningMaxHum
          ..alarmMinHum    = sensors[i].alarmMinHum
          ..alarmMaxHum    = sensors[i].alarmMaxHum; // конец каскадных присваиваний
      }
    }

    await loadSubordinates(); // подчинённые пользователи (admin/editor)
    await loadAuditLog(); // журнал аудита
    return null; // успех без сообщения
  }

  // ── GET /locations/{group_id}/details (только admin) ─────────────────────
  /// Возвращает локацию + пользователей + audit_logs одним запросом.
  Future<LocationDetailsResult> loadLocationDetails( // детали локации (пользователи, аудит)
    int locationId, { // id локации
    int usersLimit = 100, // лимит пользователей в ответе
    int logsLimit  = 200, // лимит записей аудита
  }) async {
    try { // сетевые ошибки ловим здесь
      final r = await get( // GET агрегированный эндпоинт
        '/locations/$locationId/details?users_limit=$usersLimit&logs_limit=$logsLimit', // query limits
      );
      if (r.statusCode == 200) { // OK
        final json = jsonDecode(r.body) as Map<String, dynamic>; // тело JSON
        return LocationDetailsResult(data: LocationDetails.fromJson(json)); // успешный результат
      }
      final msg = parseError(r.body) ?? // сообщение с сервера
          (r.statusCode == 404 ? 'Локация не найдена' : 'Ошибка ${r.statusCode}'); // fallback по коду
      return LocationDetailsResult(error: msg); // обёртка с ошибкой
    } catch (e) { // сеть/парсинг
      return LocationDetailsResult(error: 'Сервер недоступен: $e'); // текст для UI
    }
  }

  Future<void> loadSubordinates() async { // список подчинённых по роли
    subordinateUsers = []; // сброс перед загрузкой
    if (role == UserRole.admin) { // админ видит редакторов и читателей
      final r = await get('/users/?skip=0&limit=200'); // полный список пользователей (ограниченный)
      if (r.statusCode == 200) { // успех
        subordinateUsers = _extractDataList(r.body) // массив пользователей
            .map((e) => userFromJson(e as Map<String, dynamic>)) // парсинг UserModel
            .where((u) => u.role == 'editor' || u.role == 'viewer') // только не-admin
            .toList(); // итоговый список
      }
    } else if (role == UserRole.editor) { // редактор видит только viewers своей зоны
      final r = await get('/users/by-role/viewer?skip=0&limit=200'); // узкий эндпоинт
      if (r.statusCode == 200) { // успех
        subordinateUsers = _extractDataList(r.body) // массив
            .map((e) => userFromJson(e as Map<String, dynamic>)) // парсинг
            .toList(); // список viewers
      }
    }
  }

  // ── Телеметрия ────────────────────────────────────────────────────────────
  // GET /api/v1/telemetry/{sensor_id}/latest   — последнее измерение
  // GET /api/v1/telemetry/{sensor_id}/history?limit=N — история

  Future<void> loadHistory(int sensorId, String period) async { // загрузка истории для графика по периоду UI
    // FIX: по документации API эндпоинты:
    //   /telemetry/{sensor_id}/latest           — одно последнее
    //   /telemetry/{sensor_id}/history?limit=N  — история (N точек)
    // День → 100 точек, Неделя → 300, Месяц → 600
    final int limit; // число точек history
    switch (period) { // метка периода с экрана дашборда
      case 'День':
        limit = 100; // компактная история за день
      case 'Неделя':
        limit = 300; // средняя плотность
      default: // Месяц
        limit = 600; // длинная история
    }
    final endpoint = '/telemetry/$sensorId/history?limit=$limit'; // путь с лимитом

    final r = await get(endpoint); // GET JSON измерений
    if (r.statusCode != 200) return; // при ошибке молча выходим (график пустой)

    List<dynamic> measurements = []; // сырые точки
    dynamic decoded; // корень JSON (список или объект)
    try {
      decoded = jsonDecode(r.body); // парсинг тела ответа
      if (decoded is List) { // иногда API отдаёт массив напрямую
        measurements = decoded; // все элементы — измерения
      } else if (decoded is Map<String, dynamic>) { // обёртка с полями
        measurements = (decoded['measurements'] as List<dynamic>?) ?? []; // массив измерений
        if (measurements.isEmpty && decoded['latest'] != null) { // fallback одной точкой
          measurements = [decoded['latest']]; // последнее как единственная точка
        }
      }
    } catch (_) { return; } // битый JSON — выход

    // FIX: Парсим все три поля вместе, чтобы индексы points/timestamps
    // всегда были синхронизированы. Точки с отсутствующими полями пропускаем.
    final tempPoints  = <double>[]; // серии температуры
    final humPoints   = <double>[]; // серии влажности
    final tsPoints    = <DateTime>[]; // метки времени
    for (final raw in measurements) { // каждая запись
      final m    = raw as Map<String, dynamic>; // поля измерения
      final temp = (m['temperature'] as num?)?.toDouble(); // t
      final hum  = (m['humidity']    as num?)?.toDouble(); // h
      final tsRaw = m['timestamp']  as String?; // ISO время
      if (temp == null || hum == null || tsRaw == null) continue; // неполная запись — skip
      DateTime? dt; // распарсенное время
      try { dt = DateTime.parse(tsRaw); } catch (_) { continue; } // невалидная дата — skip
      tempPoints.add(temp); // добавляем в серию t
      humPoints.add(hum); // добавляем в серию h
      tsPoints.add(dt); // добавляем время
    }

    final i = sensors.indexWhere((e) => e.id == sensorId); // индекс датчика в кеше
    if (i >= 0) { // датчик найден
      if (tempPoints.isNotEmpty) sensors[i].points         = tempPoints; // обновляем график t
      if (humPoints.isNotEmpty)  sensors[i].humidityPoints = humPoints; // обновляем график h
      if (tsPoints.isNotEmpty)   sensors[i].timestamps     = tsPoints; // ось времени

      // Обновляем текущие показания из последнего измерения
      try {
        final latestRaw = decoded is Map<String, dynamic> ? decoded['latest'] : null; // блок latest если есть
        final last = latestRaw ?? (measurements.isNotEmpty ? measurements.last : null); // последняя точка
        if (last != null) { // есть что применить
          final lastMap = last as Map<String, dynamic>; // карта последнего замера
          sensors[i] = SensorModel( // пересобираем модель с актуальными t/h
            id:                sensors[i].id, // id
            name:              sensors[i].name, // имя
            groupId:           sensors[i].groupId, // группа
            location:          sensors[i].location, // локация
            temperature:       (lastMap['temperature'] as num?)?.toDouble() ?? sensors[i].temperature, // t из last
            humidity:          (lastMap['humidity']    as num?)?.toDouble() ?? sensors[i].humidity, // h из last
            state:             sensors[i].state, // состояние не пересчитываем здесь
            x:                 sensors[i].x, // координата
            y:                 sensors[i].y, // координата
            points:            sensors[i].points, // уже обновлённые серии
            humidityPoints:    sensors[i].humidityPoints, // серии h
            timestamps:        sensors[i].timestamps, // времена
            controlUnitId:     sensors[i].controlUnitId, // ЦБУ
            internalId:        sensors[i].internalId, // internal
            alarmDelaySeconds: sensors[i].alarmDelaySeconds, // задержка
            powerStatus:       sensors[i].powerStatus, // питание
            batteryLevel:      sensors[i].batteryLevel, // батарея
            simBalance:        sensors[i].simBalance, // SIM
            gsmSignal:         sensors[i].gsmSignal, // GSM
            isOnline:          sensors[i].isOnline, // онлайн
            lastSeen:          sensors[i].lastSeen, // last seen
          )
            ..warningMinTemp = sensors[i].warningMinTemp // пороги копируем
            ..warningMaxTemp = sensors[i].warningMaxTemp
            ..alarmMinTemp   = sensors[i].alarmMinTemp
            ..alarmMaxTemp   = sensors[i].alarmMaxTemp
            ..warningMinHum  = sensors[i].warningMinHum
            ..warningMaxHum  = sensors[i].warningMaxHum
            ..alarmMinHum    = sensors[i].alarmMinHum
            ..alarmMaxHum    = sensors[i].alarmMaxHum; // конец
        }
      } catch (_) {} // игнорируем сбой обновления last
    }
  }

  /// GET /api/v1/telemetry/{sensor_id}/latest — одно последнее измерение
  Future<SensorLiveData?> getLatestTelemetry(int sensorId) async { // мгновенный снимок с датчика
    try {
      final res = await get('/telemetry/$sensorId/latest'); // GET одной записи
      if (res.statusCode == 200) { // успех
        final data = jsonDecode(res.body); // dynamic JSON
        // FIX: SensorLiveData.fromJson теперь защищён от null-полей
        return SensorLiveData.fromJson(data as Map<String, dynamic>); // типизированная модель
      }
      return null; // не 200 — нет данных
    } catch (e) {
      debugPrint('Ошибка получения latest telemetry: $e'); // лог для отладки
      return null; // ошибка сети/парсинга
    }
  }

  // ── WebSocket: real-time обновления ──────────────────────────────────────
  // URL: ws://157.90.127.202:8000/ws/alarms
  // Событие: { "type": "new_measurement", "sensor_id": N, "temp": N, "hum": N, "is_alarm": bool }

  WebSocket? _wsChannel; // активное WS-соединение
  void Function(int sensorId, double temp, double hum, bool isAlarm)? _wsCallback; // колбэк в UI
  bool _wsReconnecting = false; // флаг чтобы не планировать несколько реконнектов

  /// Подключает WebSocket для получения live-данных без polling.
  /// [onData] вызывается при каждом новом измерении — используйте для setState().
  void connectWebSocket( // публичный вход подключения WS
    void Function(int sensorId, double temp, double hum, bool isAlarm) onData, // слушатель событий
  ) {
    _wsCallback = onData; // сохраняем колбэк
    _wsReconnecting = false; // сбрасываем флаг перед коннектом
    _wsConnect(); // стартуем соединение
  }

  void _wsConnect() { // внутреннее подключение к каналу alarms
    WebSocket.connect('ws://157.90.127.202:8000/ws/alarms').then((ws) { // асинхронный коннект
      _wsChannel = ws; // сохраняем сокет
      debugPrint('[WS] Подключён к ws/alarms'); // лог
      ws.listen( // подписка на поток сообщений
        _wsOnData, // обработчик строки JSON
        onError: (_) => _wsScheduleReconnect(), // при ошибке — реконнект
        onDone:  ()  => _wsScheduleReconnect(), // при закрытии — реконнект
        cancelOnError: true, // отмена подписки при ошибке
      );
    }).catchError((e) { // ошибка TCP/TLS/handshake
      debugPrint('[WS] Ошибка подключения: $e'); // лог
      _wsScheduleReconnect(); // пробуем позже
    });
  }

  void _wsOnData(dynamic raw) { // приходит String из WebSocket
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>; // парсинг события
      if (j['type'] != 'new_measurement') return; // интересует только новое измерение

      final sensorId = (j['sensor_id'] as num).toInt(); // id датчика
      final temp     = (j['temp']      as num).toDouble(); // температура
      final hum      = (j['hum']       as num).toDouble(); // влажность
      final isAlarm  = j['is_alarm']   as bool? ?? false; // флаг тревоги с сервера
      // FIX: используем серверный timestamp если есть, иначе текущее время
      DateTime eventTime = DateTime.now(); // fallback время события
      try {
        final tsRaw = j['timestamp'] as String?; // ISO с сервера
        if (tsRaw != null) eventTime = DateTime.parse(tsRaw); // предпочитаем серверное
      } catch (_) {} // игнор кривого timestamp

      // Обновляем датчик в локальном списке
      final i = sensors.indexWhere((s) => s.id == sensorId); // позиция в кеше
      if (i >= 0) { // найден
        final s = sensors[i]; // старая модель (короче писать)
        sensors[i] = SensorModel( // новая модель с обновлёнными полями и буферами
          id:                s.id, // id
          name:              s.name, // имя
          groupId:           s.groupId, // группа
          location:          s.location, // локация
          temperature:       temp, // live t
          humidity:          hum, // live h
          state:             isAlarm ? SensorState.critical : SensorState.normal, // цвет/статус по тревоге
          x:                 s.x, // позиция на плане
          y:                 s.y, // позиция на плане
          points:            [ // буфер температур (скользящее окно)
            ...(s.points.length >= 600 ? s.points.sublist(s.points.length - 599) : s.points), // обрезка хвоста
            temp, // новая точка
          ],
          humidityPoints:    [ // буфер влажности
            ...(s.humidityPoints.length >= 600 ? s.humidityPoints.sublist(s.humidityPoints.length - 599) : s.humidityPoints),
            hum, // новая точка h
          ],
          timestamps:        [ // синхронные метки времени
            ...(s.timestamps.length >= 600 ? s.timestamps.sublist(s.timestamps.length - 599) : s.timestamps),
            eventTime, // FIX: серверное время вместо DateTime.now()
          ],
          controlUnitId:     s.controlUnitId, // ЦБУ
          internalId:        s.internalId, // internal
          alarmDelaySeconds: s.alarmDelaySeconds, // задержка
          powerStatus:       s.powerStatus, // питание
          batteryLevel:      s.batteryLevel, // батарея
          simBalance:        s.simBalance, // SIM
          gsmSignal:         s.gsmSignal, // GSM
          isOnline:          true, // live-событие ⇒ считаем онлайн
          lastSeen:          s.lastSeen, // last seen не трогаем здесь
        )
          ..warningMinTemp = s.warningMinTemp // пороги
          ..warningMaxTemp = s.warningMaxTemp
          ..alarmMinTemp   = s.alarmMinTemp
          ..alarmMaxTemp   = s.alarmMaxTemp
          ..warningMinHum  = s.warningMinHum
          ..warningMaxHum  = s.warningMaxHum
          ..alarmMinHum    = s.alarmMinHum
          ..alarmMaxHum    = s.alarmMaxHum; // конец
      }

      _wsCallback?.call(sensorId, temp, hum, isAlarm); // уведомляем UI
    } catch (e) {
      debugPrint('[WS] Ошибка парсинга: $e'); // битый JSON
    }
  }

  void _wsScheduleReconnect() { // отложенное переподключение
    if (_wsReconnecting || _wsCallback == null) return; // уже ждём или отключились полностью
    _wsReconnecting = true; // блокируем дубли
    debugPrint('[WS] Реконнект через 5 сек...'); // лог
    Future.delayed(const Duration(seconds: 5), () { // таймер
      if (_wsCallback != null) { // колбэк ещё актуален
        _wsReconnecting = false; // снимаем блок до нового коннекта
        _wsConnect(); // новая попытка
      }
    });
  }

  void disconnectWebSocket() { // явное отключение (logout и т.д.)
    _wsCallback = null; // больше не уведомляем UI
    _wsReconnecting = false; // не реконнектимся
    _wsChannel?.close(); // закрываем сокет
    _wsChannel = null; // обнуляем ссылку
    debugPrint('[WS] Отключён'); // лог
  }

  // ── Тревоги ───────────────────────────────────────────────────────────────
  // PATCH /alarms/{id}  { "status": "...", "user_comment": "..." }
  // Статусы: "new" | "in_progress" | "resolved"

  Future<String?> updateAlarm(int alarmId, String status, String comment) async { // PATCH статуса/комментария тревоги
    final body = <String, dynamic>{'status': status}; // обязательное поле статус API
    if (comment.trim().isNotEmpty) body['user_comment'] = comment.trim(); // опциональный комментарий оператора

    debugPrint('[alarm PATCH] body=$body'); // отладочный лог тела
    final r = await patch('/alarms/$alarmId', body); // PATCH на сервер
    debugPrint('[alarm PATCH] status=${r.statusCode} body=${r.body}'); // ответ сервера

    if (r.statusCode == 200) { // успех
      final data    = jsonDecode(r.body) as Map<String, dynamic>; // обновлённый объект
      final updated = alarmFromJson(data); // парсинг AlarmModel
      final idx     = alarms.indexWhere((a) => a.id == alarmId); // позиция в локальном списке
      if (idx >= 0) alarms[idx] = updated; // заменяем элемент кеша
      return null; // без ошибки
    }
    return parseError(r.body) ?? 'Ошибка изменения тревоги (${r.statusCode})'; // текст ошибки
  }

  // ── Датчики ───────────────────────────────────────────────────────────────
  // POST /sensors/create_sensor
  // PATCH /sensors/{id}/thresholds  — пороги устанавливаются отдельно

  Future<String?> createSensor({ // POST создание датчика на сервере
    required String name, // отображаемое имя
    required int    locationId, // group_id / локация
    int?    controlUnitId, // опциональная привязка к ЦБУ
    String? internalId, // строковый id на шине устройства
    double? warningMinTemp, double? warningMaxTemp, // пороги предупреждения t
    double? alarmMinTemp,   double? alarmMaxTemp, // пороги аварии t
    double? warningMinHum,  double? warningMaxHum, // пороги предупреждения h
    double? alarmMinHum,    double? alarmMaxHum, // пороги аварии h
    int     alarmDelaySeconds = 0, // задержка перед созданием тревоги
  }) async {
    final createBody = <String, dynamic>{ // тело POST (только заданные поля)
      'name':     name, // имя датчика
      'group_id': locationId, // id локации в API
      if (controlUnitId      != null) 'control_unit_id':     controlUnitId, // ЦБУ
      if (internalId         != null) 'internal_id':         internalId, // internal
      if (warningMinTemp     != null) 'warning_min_temp':    warningMinTemp, // пороги t
      if (warningMaxTemp     != null) 'warning_max_temp':    warningMaxTemp,
      if (alarmMinTemp       != null) 'alarm_min_temp':      alarmMinTemp,
      if (alarmMaxTemp       != null) 'alarm_max_temp':      alarmMaxTemp,
      if (warningMinHum      != null) 'warning_min_hum':     warningMinHum, // пороги h
      if (warningMaxHum      != null) 'warning_max_hum':     warningMaxHum,
      if (alarmMinHum        != null) 'alarm_min_hum':       alarmMinHum,
      if (alarmMaxHum        != null) 'alarm_max_hum':       alarmMaxHum,
      'alarm_delay_seconds': alarmDelaySeconds, // задержка
    };
    final r = await post('/sensors/create_sensor', createBody); // создаём ресурс

    if (r.statusCode != 200 && r.statusCode != 201) { // неуспех
      return parseError(r.body) ?? 'Не удалось добавить датчик (${r.statusCode})'; // сообщение
    }
    return null; // ОК — список sensors обновят при следующем loadAll
  }

  Future<String?> updateSensorPosition({ // сохранить координаты на плане (нормализованные)
    required int sensorId, required double posX, required double posY, // id и позиция 0–1
  }) async {
    final r = await patch('/sensors/$sensorId', {'pos_x': posX, 'pos_y': posY}); // PATCH позиции
    if (r.statusCode != 200) return parseError(r.body) ?? 'Не удалось сохранить позицию'; // ошибка HTTP
    final i = sensors.indexWhere((e) => e.id == sensorId); // локальный индекс
    if (i >= 0) { sensors[i].x = posX; sensors[i].y = posY; } // синхронизируем кеш
    return null; // успех
  }

  Future<String?> updateSensorThresholds({ // PATCH порогов t/h
    required int sensorId, // id датчика
    required double warningMinTemp, required double warningMaxTemp, // предупреждение t
    required double alarmMinTemp,   required double alarmMaxTemp, // авария t
    double? warningMinHum, double? warningMaxHum, // предупреждение h (опц.)
    double? alarmMinHum,   double? alarmMaxHum, // авария h (опц.)
  }) async {
    final idx = sensors.indexWhere((e) => e.id == sensorId); // индекс в кеше
    if (idx < 0) return 'Датчик не найден'; // нет такого id локально
    final body = <String, dynamic>{ // JSON для thresholds
      'warning_min_temp': warningMinTemp, 'warning_max_temp': warningMaxTemp, // t warn
      'alarm_min_temp':   alarmMinTemp,   'alarm_max_temp':   alarmMaxTemp, // t alarm
      if (warningMinHum != null) 'warning_min_hum': warningMinHum, // h warn
      if (warningMaxHum != null) 'warning_max_hum': warningMaxHum,
      if (alarmMinHum   != null) 'alarm_min_hum':   alarmMinHum, // h alarm
      if (alarmMaxHum   != null) 'alarm_max_hum':   alarmMaxHum,
    };
    final r = await patch('/sensors/$sensorId/thresholds', body); // отдельный эндпоинт порогов
    if (r.statusCode != 200) return parseError(r.body) ?? 'Не удалось сохранить пороги (${r.statusCode})'; // ошибка
    sensors[idx] // обновляем локальные mutable поля порогов
      ..warningMinTemp = warningMinTemp ..warningMaxTemp = warningMaxTemp // каскад присваиваний
      ..alarmMinTemp   = alarmMinTemp   ..alarmMaxTemp   = alarmMaxTemp
      ..warningMinHum  = warningMinHum  ..warningMaxHum  = warningMaxHum
      ..alarmMinHum    = alarmMinHum    ..alarmMaxHum    = alarmMaxHum;
    return null; // успех
  }

  /// POST /control-units/register — регистрация ЦБУ/AlertBox
  Future<({String? error, String? ingestionToken})> createControlUnit({ // регистрация ЦБУ на сервере
    required String name, // человекочитаемое имя блока
    required int    locationId, // привязка к группе/локации
    required String serialNumber, // серийник железа
    String? devEui, // LoRaWAN DevEUI опционально
    String? appKey, // ключ приложения LoRa опционально
  }) async {
    final body = <String, dynamic>{ // тело register
      'name':          name, // имя
      'group_id':      locationId, // локация
      'serial_number': serialNumber, // SN
      if (devEui != null && devEui.isNotEmpty) 'dev_eui': devEui, // только если задан
      if (appKey != null && appKey.isNotEmpty) 'app_key': appKey, // только если задан
    };
    final r = await post('/control-units/register', body); // создаём ЦБУ
    if (r.statusCode == 200 || r.statusCode == 201) { // успех
      String? ingestionToken; // токен для прошивки (не показываем в UI обычно)
      try {
        final data = jsonDecode(r.body) as Map<String, dynamic>; // ответ сервера
        ingestionToken = data['ingestion_token'] as String?; // извлекаем токен
        final cuList = await get('/control-units/'); // обновляем список ЦБУ
        if (cuList.statusCode == 200) { // OK
          controlUnits = _extractDataList(cuList.body).cast<Map<String, dynamic>>().toList(); // кеш ЦБУ
        }
      } catch (_) {} // игнорируем сбой доброса списка
      return (error: null, ingestionToken: ingestionToken); // успех + токен вызывающему коду
    }
    return ( // ошибка создания
      error: parseError(r.body) ?? 'Не удалось создать блок управления (${r.statusCode})', // текст
      ingestionToken: null, // токена нет
    );
  }

  /// POST /control-units/heartbeat — периодическая отправка heartbeat от ЦБУ.
  Future<void> sendHeartbeat({ // имитация «живости» ЦБУ с клиента (демо/обход)
    required String serialNumber, // SN устройства
    required String ingestionToken, // секрет для heartbeat
    int?    batteryLevel, // опционально уровень %
    String? powerStatus, // mains/battery
    int?    gsmSignal, // уровень сигнала
  }) async {
    try {
      final body = <String, dynamic>{ // JSON для heartbeat
        'serial_number': serialNumber, // идентификация железа
        'token':         ingestionToken, // авторизация heartbeat
        if (batteryLevel != null) 'battery_level': batteryLevel, // заряд
        if (powerStatus  != null) 'power_status':  powerStatus, // источник питания
        if (gsmSignal    != null) 'gsm_signal':     gsmSignal, // gsm
      };
      await http.post( // отдельный http.post (не patch/get helper)
        Uri.parse('$baseUrl/control-units/heartbeat'), // URL heartbeat
        headers: {
          'Authorization': 'Bearer $token', // JWT пользователя приложения
          'Content-Type': 'application/json', // JSON тело
        },
        body: jsonEncode(body), // сериализация
      ).timeout(const Duration(seconds: 10)); // защита от зависания
    } catch (e) {
      debugPrint('[heartbeat] Ошибка: $e'); // не роняем приложение
    }
  }

  void startHeartbeatLoop() { // запуск периодической отправки heartbeat по всем ЦБУ
    _stopHeartbeatLoop(); // сбрасываем предыдущий таймер если был
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async { // каждые 30 с
      for (final unit in controlUnits) { // каждый блок из кеша
        final serialNumber    = unit['serial_number'] as String?; // SN
        final ingestionToken  = unit['ingestion_token'] as String?; // токен
        if (serialNumber == null || ingestionToken == null) continue; // неполные данные — skip
        await sendHeartbeat( // шлём статус «как на сервере в loadAll»
          serialNumber:   serialNumber, // SN
          ingestionToken: ingestionToken, // token
          batteryLevel:   (unit['battery_level'] as num?)?.toInt(), // из кеша ЦБУ
          powerStatus:    unit['power_status']  as String?, // из кеша
          gsmSignal:      (unit['gsm_signal']   as num?)?.toInt(), // из кеша
        );
      }
    });
  }

  void _stopHeartbeatLoop() { // остановка таймера heartbeat
    _heartbeatTimer?.cancel(); // отмена periodic
    _heartbeatTimer = null; // обнуляем ссылку
  }

  Timer? _heartbeatTimer; // handle периодического таймера

  void stopHeartbeatLoop() => _stopHeartbeatLoop(); // публичная обёртка (logout и т.д.)

  /// POST /api/v1/sensors/{sensor_id}/set-medication?drug_name=...
  /// ИИ автоматически устанавливает пороги по названию препарата
  Future<String?> setSensorMedication({ // ИИ-подбор порогов по названию лекарства
    required int sensorId, // id датчика
    required String drugName, // строка запроса к ИИ
  }) async {
    final uri = Uri.parse('$baseUrl/sensors/$sensorId/set-medication') // базовый путь
        .replace(queryParameters: {'drug_name': drugName}); // query drug_name
    final r = await http.post(uri, // POST без JSON тела — только query
        headers: {'Authorization': 'Bearer $token'}).timeout(_kTimeout); // JWT
    if (r.statusCode == 200) { // пороги применены на сервере и в теле ответа
      try {
        final data = jsonDecode(r.body) as Map<String, dynamic>; // распарсенные пороги
        final idx  = sensors.indexWhere((e) => e.id == sensorId); // локальный датчик
        if (idx >= 0) { // найден
          sensors[idx].warningMinTemp = _thresh(data['warning_min_temp']); // обновляем поля
          sensors[idx].warningMaxTemp = _thresh(data['warning_max_temp']);
          sensors[idx].alarmMinTemp   = _thresh(data['alarm_min_temp']);
          sensors[idx].alarmMaxTemp   = _thresh(data['alarm_max_temp']);
          sensors[idx].alarmMinHum    = _thresh(data['alarm_min_hum']);
          sensors[idx].alarmMaxHum    = _thresh(data['alarm_max_hum']);
        }
      } catch (_) {} // игнорируем кривой JSON
      return null; // успех без сообщения
    }
    if (r.statusCode == 503) return 'ИИ-сервис временно недоступен. Попробуйте позже.'; // специфичная ошибка
    return parseError(r.body) ?? 'Ошибка настройки порогов (${r.statusCode})'; // прочие ошибки
  }

  // ── Локации ───────────────────────────────────────────────────────────────

  Future<String?> createLocation({required String name}) async { // создать локацию (компанию) только именем
    try {
      // FIX: сервер ожидает multipart/form-data, а не JSON.
      // Используем MultipartRequest чтобы передать поле name как form-поле.
      final uri     = Uri.parse('$baseUrl/locations/'); // POST /locations/
      final request = http.MultipartRequest('POST', uri) // multipart вместо JSON
        ..headers['Authorization'] = 'Bearer $token' // JWT
        ..fields['name'] = name; // поле формы name
      final response = await http.Response.fromStream( // читаем поток ответа
        await request.send().timeout(_kTimeout), // отправка с таймаутом
      );
      if (response.statusCode == 200 || response.statusCode == 201) { // создано
        // Добавляем новую локацию в локальный список сразу, без лишнего reload
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>; // тело ответа
          final id   = (data['id'] as num?)?.toInt(); // id новой локации
          final nm   = data['name'] as String? ?? name; // имя из ответа или запроса
          if (id != null) {
            locations.add(LocationModel(id: id, name: nm)); // дописываем в кеш
          }
        } catch (_) {} // игнорируем битый JSON
        return null; // успех
      }
      return parseError(response.body) ?? 'Не удалось добавить локацию (${response.statusCode})'; // ошибка API
    } catch (e) {
      return 'Ошибка создания локации: $e'; // сеть/таймаут
    }
  }

  Future<String?> uploadLocationPlan({ // загрузить изображение плана для локации
    required int locationId, // id локации
    required Uint8List fileBytes, // байты файла
    required String mimeType, // MIME типа image/jpeg и т.д.
    String? fileName, // имя файла для multipart
  }) async {
    try {
      final uri     = Uri.parse('$baseUrl/locations/$locationId/upload-plan'); // POST upload
      final request = http.MultipartRequest('POST', uri) // multipart запрос
        ..headers['Authorization'] = 'Bearer $token' // JWT
        ..files.add(http.MultipartFile.fromBytes( // один файл в форме
          'file', // имя поля на сервере
          fileBytes, // содержимое
          filename: fileName ?? 'plan', // имя файла
          contentType: MediaType.parse(mimeType), // Content-Type части
        ));
      final response = await http.Response.fromStream(await request.send()); // ответ
      if (response.statusCode == 200 || response.statusCode == 201) { // ОК
        final newUrl = (jsonDecode(response.body) as Map<String, dynamic>)['image_url'] as String?; // URL картинки
        final idx    = locations.indexWhere((l) => l.id == locationId); // позиция локации в кеше
        if (idx >= 0 && newUrl != null) {
          locations[idx] = LocationModel(id: locations[idx].id, name: locations[idx].name, imageUrl: newUrl); // обновляем imageUrl
        }
        return null; // успех
      }
      return parseError(response.body) ?? 'Не удалось загрузить план'; // ошибка сервера
    } catch (e) { return 'Ошибка загрузки файла: $e'; } // клиентская ошибка
  }

  // ── Отчёты ────────────────────────────────────────────────────────────────

  Future<List<int>?> downloadReportByPeriod({ // скачать файл отчёта по одному датчику
    required int sensorId, required String period, required String format, // id, период API, xlsx/pdf...
    DateTime? startDate, DateTime? endDate, // для custom периода
  }) async {
    final params = <String, String>{'period': period, 'format': format}; // query базовый
    if (period == 'custom' && startDate != null && endDate != null) { // пользовательский диапазон
      params['start_date'] = _fmtDate(startDate); // yyyy-MM-dd
      params['end_date']   = _fmtDate(endDate); // yyyy-MM-dd
    }
    final uri = Uri.parse('$baseUrl/reports/download-period/$sensorId').replace(queryParameters: params); // полный URL
    final r   = await http.get(uri, headers: {'Authorization': 'Bearer $token'}); // GET бинарника
    return r.statusCode == 200 ? r.bodyBytes : null; // байты файла или null
  }

  Future<List<int>?> downloadLocationReportByPeriod({ // отчёт по всей локации (агрегация на сервере)
    required int locationId, required String period, required String format, // id локации и параметры
    DateTime? startDate, DateTime? endDate, // custom диапазон
  }) async {
    final params = <String, String>{'period': period, 'format': format}; // query
    if (period == 'custom' && startDate != null && endDate != null) { // даты
      params['start_date'] = _fmtDate(startDate); // от
      params['end_date']   = _fmtDate(endDate); // до
    }
    final uri = Uri.parse('$baseUrl/reports/download-period-location/$locationId').replace(queryParameters: params); // endpoint локации
    final r   = await http.get(uri, headers: {'Authorization': 'Bearer $token'}); // GET
    return r.statusCode == 200 ? r.bodyBytes : null; // файл или null
  }

  String _fmtDate(DateTime d) => // формат даты для query API
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'; // yyyy-MM-dd

  /// Смена пароля текущего пользователя.
  Future<String?> changePassword({ // PATCH пароля в профиле
    required String oldPassword, // старый пароль
    required String newPassword, // новый пароль
  }) async {
    if (currentUserId == null) return 'Не удалось определить пользователя'; // нет id — нельзя PATCH
    final r = await patch('/users/${currentUserId!}', { // обновление пользователя
      'old_password': oldPassword, // проверка старого
      'new_password': newPassword, // новое значение
    });
    if (r.statusCode == 200) return null; // успех
    return parseError(r.body) ?? 'Не удалось сменить пароль (${r.statusCode})'; // ошибка API
  }

  /// GET /users/audit-logs — журнал действий
  Future<void> loadAuditLog() async { // загрузка аудита и маппинг на AuditEntry
    final r = await get('/users/audit-logs?skip=0&limit=100'); // последние записи
    if (r.statusCode != 200) return; // при ошибке оставляем старый audit

    // Кешируем имена пользователей: user_id -> отображаемое имя
    final userNames = <int, String>{}; // словарь имён для подстановки в строки
    if (currentUserId != null) { // текущий пользователь
      final displayName = (currentUserFullName?.isNotEmpty == true)
          ? currentUserFullName! // предпочитаем ФИО
          : (currentUser ?? ''); // иначе логин
      if (displayName.isNotEmpty) userNames[currentUserId!] = displayName; // запись в карту
    }
    for (final u in subordinateUsers) { // подчинённые из репозитория
      userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username; // ФИО или логин
    }

    audit = _extractDataList(r.body).map((e) { // каждая строка журнала
      final j     = e as Map<String, dynamic>; // поля записи
      final uid   = (j['user_id'] as num?)?.toInt() ?? 0; // кто совершил действие
      final tsRaw = j['timestamp'] as String? ?? ''; // сырое время ISO

      // Форматируем timestamp в локальное время
      String timeFormatted = tsRaw; // по умолчанию как пришло
      try {
        final dt    = DateTime.parse(tsRaw).toLocal(); // локаль пользователя
        final h     = dt.hour  .toString().padLeft(2, '0'); // часы
        final mn    = dt.minute.toString().padLeft(2, '0'); // минуты
        final day   = dt.day   .toString().padLeft(2, '0'); // день
        final month = dt.month .toString().padLeft(2, '0'); // месяц
        timeFormatted = '$day.$month.${dt.year}  $h:$mn'; // человекочитаемая строка
      } catch (_) {} // если парсинг не удался — остаётся tsRaw

      return AuditEntry(
        user:   userNames[uid] ?? 'ID:$uid', // имя или заглушка
        action: j['action'] as String? ?? '', // тип действия
        time:   timeFormatted, // время для списка UI
      );
    }).toList(); // новый список audit
  }

  // ── Пользователи ──────────────────────────────────────────────────────────

  Future<String?> createUser({ // регистрация сотрудника админом/по API
    required String username, required String password, // учётные данные
    required String fullName, required String roleName, // ФИО и роль строкой
    required int? locationId, String? email, // привязка к локации и почта
  }) async {
    final r = await post('/users/register', { // POST создание пользователя
      'username': username, 'password': password, // логин/пароль
      'full_name': fullName, 'role': roleName, // профиль
      'location_id': locationId, // может быть null для admin глобально
      if (email != null) 'email': email, // опционально
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null; // успех
    return parseError(r.body) ?? 'Не удалось создать сотрудника'; // ошибка
  }

  // ── Парсеры ───────────────────────────────────────────────────────────────

  SensorModel sensorFromJson(Map<String, dynamic> j) { // JSON датчика → модель (до обогащения в loadAll)
    final id       = (j['id'] as num?)?.toInt() ?? 0; // id записи
    final isOnline = j['is_online'] != false; // по умолчанию онлайн если поле отсутствует
    final state    = isOnline ? SensorState.normal : SensorState.critical; // базовое состояние по связи

    final sensor = SensorModel(
      id:                  id, // id
      name:                j['name']      as String? ?? 'Датчик', // имя или дефолт
      groupId:             (j['group_id'] as num?)?.toInt() ?? 0, // локация
      // Временное значение — будет перезаписано реальным именем в loadAll()
      // после загрузки локаций из /locations/
      location:            'Локация #${(j['group_id'] as num?)?.toInt() ?? 0}', // заглушка до merge с locations
      temperature:         0.0, // позже подтянется телеметрией
      humidity:            0.0, // позже подтянется телеметрией
      state:               state, // normal/critical по онлайну
      x:                   _normalizePos((j['pos_x'] as num?)?.toDouble() ?? 0.1), // позиция на плане
      y:                   _normalizePos((j['pos_y'] as num?)?.toDouble() ?? 0.1), // позиция на плане
      points:              [], // история для графика заполнится loadHistory
      humidityPoints:      [], // история влажности
      controlUnitId:       (j['control_unit_id']     as num?)?.toInt(), // ЦБУ
      internalId:          j['internal_id']           as String?, // строковый id
      alarmDelaySeconds:   (j['alarm_delay_seconds'] as num?)?.toInt() ?? 0, // задержка тревоги
      isOnline:            isOnline, // флаг связи
      lastSeen:            j['last_seen']     as String?, // время последней связи
    );

    sensor.warningMinTemp = _thresh(j['warning_min_temp']); // пороги из JSON
    sensor.warningMaxTemp = _thresh(j['warning_max_temp']);
    sensor.alarmMinTemp   = _thresh(j['alarm_min_temp']);
    sensor.alarmMaxTemp   = _thresh(j['alarm_max_temp']);
    sensor.warningMinHum  = _thresh(j['warning_min_hum']);
    sensor.warningMaxHum  = _thresh(j['warning_max_hum']);
    sensor.alarmMinHum    = _thresh(j['alarm_min_hum']);
    sensor.alarmMaxHum    = _thresh(j['alarm_max_hum']);
    return sensor; // готовая модель (mutable пороги установлены)
  }

  /// Нормализует позицию датчика в диапазон 0.0–1.0.
  /// Если значение > 1.0 — это устаревшее абсолютное значение в пикселях,
  /// которое зажимаем до 0.5 (центр), чтобы датчик был виден.
  double _normalizePos(double v) => v <= 1.0 ? v.clamp(0.0, 1.0) : 0.5; // относительные координаты или центр

  /// Парсит порог из JSON.
  /// null → не задан. Любое число включая 0.0 → валидное значение.
  double? _thresh(dynamic v) { // унифицированное чтение double?
    if (v == null) return null; // отсутствие в JSON
    return (v as num).toDouble(); // числовое значение
  }

  AlarmModel alarmFromJson(Map<String, dynamic> j) { // парсинг тревоги с API
    final st = switch (j['status'] as String? ?? '') { // строка статуса → enum
      'acknowledged' => AlarmStatus.acknowledged, // в работе
      'resolved'     => AlarmStatus.resolved, // закрыто
      _              => AlarmStatus.newAlarm, // новое/прочее
    };
    final sev = switch (j['severity'] as String? ?? '') { // серьёзность
      'critical' => AlarmSeverity.critical,
      'info'     => AlarmSeverity.info,
      _          => AlarmSeverity.warning,
    };

    final alarmType = j['alarm_type'] as String?; // машинный тип события
    final title = switch (alarmType) { // человекочитаемый заголовок по типу
      'temperature'     => 'Температура вне нормы',
      'humidity'        => 'Влажность вне нормы',
      'connection_lost' => 'Потеря связи',
      'low_battery'     => 'Низкий заряд батареи',
      _                 => alarmType ?? (j['severity'] as String?) ?? 'Событие', // fallback
    };

    return AlarmModel(
      id:            (j['id']   as num?)?.toInt()    ?? 0, // id тревоги
      title:         title, // заголовок для UI
      description:   (j['description']  as String?)  ?? '', // текст описания
      status:        st, // enum статуса
      sensorId:      (j['sensor_id']    as num?)?.toInt(), // привязка к датчику
      severity:      sev, // уровень важности
      alarmType:     alarmType, // сырой тип
      timestamp:     j['timestamp']     as String?, // время события
      comment:       (j['user_comment'] as String?)  ?? (j['comment'] as String?), // комментарий оператора
      resolvedAt:    j['resolved_at']   as String?, // когда закрыто
      resolvedById:  (j['resolved_by_id'] as num?)?.toInt(), // кто закрыл
    );
  }

  UserModel userFromJson(Map<String, dynamic> j) => UserModel( // парсинг пользователя API
        id:       (j['id'] as num?)?.toInt() ?? 0, // id
        username: j['username']  as String? ?? '', // логин
        fullName: j['full_name'] as String? ?? '', // ФИО
        role:     j['role']      as String? ?? 'viewer', // роль строкой
        email:    j['email']     as String?, // email опционально
      );

  String? parseError(String body) { // достать detail из типичного FastAPI ответа
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>; // JSON объект ошибки
      return decoded['detail'] as String?; // строка для пользователя
    } catch (_) { return null; } // не JSON — без detail
  }

  // ── HTTP хелперы ──────────────────────────────────────────────────────────

  static const _kTimeout = Duration(seconds: 12); // таймаут всех HTTP вызовов репозитория

  Future<http.Response> get(String path) => // GET с Bearer
      http.get(Uri.parse('$baseUrl$path'), // полный URL
          headers: {'Authorization': 'Bearer $token'}).timeout(_kTimeout); // JWT и таймаут

  Future<http.Response> post(String path, Map<String, dynamic> body) => // POST JSON
      http.post(Uri.parse('$baseUrl$path'), // URL
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, // заголовки
          body: jsonEncode(body)).timeout(_kTimeout); // сериализация тела

  Future<http.Response> patch(String path, Map<String, dynamic> body) => // PATCH JSON
      http.patch(Uri.parse('$baseUrl$path'), // URL
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, // заголовки
          body: jsonEncode(body)).timeout(_kTimeout); // тело
}