part of '../app_repository.dart';

extension AppRepositoryLoaders on AppRepository {
  Future<String?> loadAll() async {
    // загрузка датчиков, тревог, локаций, ЦБУ, подчинённых, аудита
    if (token == null)
      return 'Нет токена'; // без авторизации запросы бессмысленны

    final s = await get('/sensors/'); // GET список датчиков
    if (s.statusCode != 200)
      return parseError(s.body) ?? 'Не удалось получить датчики'; // ошибка HTTP
    final previousSensors = {for (final sensor in sensors) sensor.id: sensor};
    sensors =
        _extractDataList(s.body) // парсим массив из JSON
            .map(
              (e) => sensorFromJson(e as Map<String, dynamic>),
            ) // каждый элемент → SensorModel
            .map((sensor) {
              final previous = previousSensors[sensor.id];
              return previous == null
                  ? sensor
                  : _mergeSensorHistory(sensor, previous);
            })
            .toList(); // материализуем список

    final a = await get('/alarms/'); // GET список тревог
    if (a.statusCode == 200) {
      // успешный ответ
      final newAlarms =
          _extractDataList(a.body) // список из тела ответа
              .map(
                (e) => alarmFromJson(e as Map<String, dynamic>),
              ) // парсинг AlarmModel
              .toList(); // новый список тревог с сервера
      for (int i = 0; i < newAlarms.length; i++) {
        // проходим по каждой новой тревоге
        final old = alarms
            .where((o) => o.id == newAlarms[i].id)
            .firstOrNull; // старая версия по id
        if (old != null &&
            newAlarms[i].comment == null &&
            old.comment != null) {
          // сохраняем локальный комментарий
          newAlarms[i] = AlarmModel(
            // пересобираем модель с сохранённым comment
            id: newAlarms[i].id,
            title: newAlarms[i].title, // id и заголовок с сервера
            description: newAlarms[i].description, // описание с сервера
            status: newAlarms[i].status,
            sensorId: newAlarms[i].sensorId,
            severity: newAlarms[i].severity,
            alarmType: newAlarms[i].alarmType,
            timestamp: newAlarms[i].timestamp,
            resolvedAt: newAlarms[i].resolvedAt,
            resolvedById: newAlarms[i].resolvedById,
            comment: old.comment, // статус новый, комментарий старый
          );
        }
      }
      alarms = newAlarms; // заменяем кеш тревог
    }
    // Пересчитаем цвета датчиков по тревогам сразу как загрузили тревоги.
    // Повторный вызов ниже (после ЦБУ) финально расставит приоритеты.
    _applySensorAlarmStates();

    final loc = await get('/locations/'); // GET список локаций (компаний)
    if (loc.statusCode == 200) {
      // API вернул список
      locations = _extractDataList(loc.body)
          .map(
            (e) => LocationModel(
              // парсим локации
              id:
                  ((e as Map<String, dynamic>)['id'] as num?)?.toInt() ??
                  0, // id группы
              name: e['name'] as String? ?? '', // отображаемое имя
              imageUrl:
                  e['image_url'] as String?, // URL плана этажа (если есть)
            ),
          )
          .toList(); // список LocationModel
    } else {
      // локации недоступны — синтетический список из строк sensor.location
      final m = <String, int>{}; // имя локации → синтетический id
      for (final sensor in sensors) {
        // для каждого датчика
        m.putIfAbsent(
          sensor.location,
          () => m.length + 1,
        ); // уникальный номер для каждой строки
      }
      locations = m.entries
          .map((e) => LocationModel(id: e.value, name: e.key))
          .toList(); // псевдо-локации
    }

    // FIX: Обогащаем датчики реальными именами локаций из /locations/
    // sensorFromJson делает location = 'Локация #N', здесь заменяем на настоящее имя
    sensors = sensors.map((s) {
      // пересобираем каждый датчик
      final loc = locations
          .where((l) => l.id == s.groupId)
          .firstOrNull; // локация по groupId
      if (loc == null) return s; // не нашли — оставляем как есть
      return SensorModel(
          // копия с исправленным полем location
          id: s.id, // id датчика
          name: s.name, // имя
          groupId: s.groupId, // id группы
          location: loc.name, // реальное имя вместо "Локация #N"
          temperature: s.temperature, // текущая температура
          humidity: s.humidity, // текущая влажность
          state: s.state, // агрегированное состояние
          x: s.x, // позиция X на плане (0–1)
          y: s.y, // позиция Y на плане (0–1)
          points: s.points, // история температуры для графика
          humidityPoints: s.humidityPoints, // история влажности
          timestamps: s.timestamps,
          controlUnitId: s.controlUnitId, // привязка к ЦБУ
          internalId: s.internalId, // внутренний id на устройстве
          alarmDelaySeconds: s.alarmDelaySeconds, // задержка перед тревогой
          isOnline: s.isOnline, // признак онлайн
          lastSeen: s.lastSeen, // время последней связи
        )
        ..warningMinTemp = s
            .warningMinTemp // порог предупреждения мин t
        ..warningMaxTemp = s
            .warningMaxTemp // порог предупреждения макс t
        ..alarmMinTemp = s
            .alarmMinTemp // порог аварии мин t
        ..alarmMaxTemp = s
            .alarmMaxTemp // порог аварии макс t
        ..warningMinHum = s
            .warningMinHum // порог предупреждения мин влажность
        ..warningMaxHum = s
            .warningMaxHum // порог предупреждения макс влажность
        ..alarmMinHum = s
            .alarmMinHum // порог аварии мин влажность
        ..alarmMaxHum = s.alarmMaxHum; // порог аварии макс влажность
    }).toList(); // обновлённый список датчиков

    // ── Блоки управления ─────────────────────────────────────────────────
    final cu = await get('/control-units/'); // GET все ЦБУ
    if (cu.statusCode == 200) {
      // успех
      controlUnits =
          _extractDataList(cu.body) // массив объектов ЦБУ
              .cast<Map<String, dynamic>>() // приводим к типу карты
              .toList(); // сохраняем в репозитории

      // Запускаем периодический heartbeat для всех ЦБУ
      controlUnits = controlUnits.map((unit) {
        final id = (unit['id'] as num?)?.toInt();
        final count =
            (unit['sensors_count'] as num?)?.toInt() ??
            sensors.where((s) => s.controlUnitId == id).length;
        return {...unit, 'sensors_count': count};
      }).toList();

      startHeartbeatLoop(); // таймер раз в 30 с шлёт heartbeat

      // Обогащаем датчики техническими данными из ControlUnit
      // FIX: power_status из API приходит как "mains" или "battery"
      // (не "power"), sensor_model.dart уже исправлен под "mains"
      for (int i = 0; i < sensors.length; i++) {
        // каждый датчик
        final cuId = sensors[i].controlUnitId; // id блока управления
        if (cuId == null) continue; // без ЦБУ — пропуск
        final unit = controlUnits
            .where((u) => (u['id'] as num?)?.toInt() == cuId)
            .firstOrNull; // найти ЦБУ
        if (unit == null) continue; // не найден — пропуск
        final batteryLevel =
            (unit['battery_level'] as num?)?.toInt() ??
            100; // уровень батареи %
        final isOnline = sensors[i].isOnline; // онлайн датчика
        final state =
            !isOnline // состояние для UI
            ? SensorState
                  .critical // офлайн — критично
            : (batteryLevel < 25
                  ? SensorState.warning
                  : SensorState.normal); // низкий заряд — предупреждение
        sensors[i] =
            SensorModel(
                // пересобираем датчик с полями из ЦБУ
                id: sensors[i].id, // id
                name: sensors[i].name, // имя
                groupId: sensors[i].groupId, // группа
                location: sensors[i].location, // локация
                temperature: sensors[i].temperature, // температура
                humidity: sensors[i].humidity, // влажность
                state: state, // вычисленное состояние
                x: sensors[i].x, // X
                y: sensors[i].y, // Y
                points: sensors[i].points, // точки графика t
                humidityPoints: sensors[i].humidityPoints, // точки графика h
                timestamps: sensors[i].timestamps,
                controlUnitId: sensors[i].controlUnitId, // ЦБУ id
                internalId: sensors[i].internalId, // internal id
                alarmDelaySeconds:
                    sensors[i].alarmDelaySeconds, // задержка тревоги
                // FIX: поле называется power_status, значения "mains"/"battery"
                powerStatus: unit['power_status'] as String?, // сеть/аккум
                batteryLevel: batteryLevel, // %
                simBalance: (unit['sim_balance'] as num?)
                    ?.toDouble(), // баланс SIM
                gsmSignal: (unit['gsm_signal'] as num?)?.toInt(), // уровень GSM
                isOnline: sensors[i].isOnline, // онлайн
                lastSeen: sensors[i].lastSeen, // last seen
              )
              ..warningMinTemp = sensors[i]
                  .warningMinTemp // копируем пороги
              ..warningMaxTemp = sensors[i].warningMaxTemp
              ..alarmMinTemp = sensors[i].alarmMinTemp
              ..alarmMaxTemp = sensors[i].alarmMaxTemp
              ..warningMinHum = sensors[i].warningMinHum
              ..warningMaxHum = sensors[i].warningMaxHum
              ..alarmMinHum = sensors[i].alarmMinHum
              ..alarmMaxHum =
                  sensors[i].alarmMaxHum; // конец каскадных присваиваний
      }
    }

    await refreshLatestTelemetry();
    await loadNotificationDevices();
    await loadSubordinates(); // подчинённые пользователи (admin/editor)
    await loadAuditLog(); // журнал аудита
    // Финальный пересчёт состояний датчиков по тревогам:
    // после обогащения ЦБУ (isOnline) и тревог — все данные актуальны.
    _applySensorAlarmStates();
    return null; // успех без сообщения
  }

  // ── GET /locations/{group_id}/details (только admin) ─────────────────────
  /// Возвращает локацию + пользователей + audit_logs одним запросом.
  Future<LocationDetailsResult> loadLocationDetails(
    // детали локации (пользователи, аудит)
    int locationId, { // id локации
    int usersLimit = 100, // лимит пользователей в ответе
    int logsLimit = 200, // лимит записей аудита
  }) async {
    try {
      // сетевые ошибки ловим здесь
      final r = await get(
        // GET агрегированный эндпоинт
        '/locations/$locationId/details?users_limit=$usersLimit&logs_limit=$logsLimit', // query limits
      );
      if (r.statusCode == 200) {
        // OK
        final json = jsonDecode(r.body) as Map<String, dynamic>; // тело JSON
        return LocationDetailsResult(
          data: LocationDetails.fromJson(json),
        ); // успешный результат
      }
      final msg =
          parseError(r.body) ?? // сообщение с сервера
          (r.statusCode == 404
              ? 'Локация не найдена'
              : 'Ошибка ${r.statusCode}'); // fallback по коду
      return LocationDetailsResult(error: msg); // обёртка с ошибкой
    } catch (e) {
      // сеть/парсинг
      return LocationDetailsResult(
        error: 'Сервер недоступен: $e',
      ); // текст для UI
    }
  }

  Future<void> loadSubordinates() async {
    // список подчинённых по роли
    subordinateUsers = []; // сброс перед загрузкой
    if (role == UserRole.admin) {
      // админ видит редакторов и читателей
      final r = await get(
        '/users/?skip=0&limit=200',
      ); // полный список пользователей (ограниченный)
      if (r.statusCode == 200) {
        // успех
        subordinateUsers =
            _extractDataList(r.body) // массив пользователей
                .map(
                  (e) => userFromJson(e as Map<String, dynamic>),
                ) // парсинг UserModel
                .where(
                  (u) => u.role == 'editor' || u.role == 'viewer',
                ) // только не-admin
                .toList(); // итоговый список
      }
    } else if (role == UserRole.editor || role == UserRole.viewer) {
      // FIX: для editor и viewer используем GET /users/my-location — эндпоинт
      // возвращает всех пользователей текущей локации без admin.
      // Если my-location недоступен (403/404), пробуем by-role/editor + by-role/viewer
      // и объединяем результаты с дедупликацией по id.
      // Документация: чеклист для мобильного клиента (пункт 3).
      final myLoc = await get(
        '/users/my-location',
      ); // предпочтительный эндпоинт
      if (myLoc.statusCode == 200) {
        // Успех: эндпоинт поддерживается бэкендом
        final all = _extractDataList(myLoc.body)
            .map((e) => userFromJson(e as Map<String, dynamic>))
            .where(
              (u) => u.role != 'admin' && u.id != currentUserId,
            ) // без admin и без себя
            .toList();
        subordinateUsers = all;
      } else {
        // Fallback: GET /users/by-role/editor + GET /users/by-role/viewer
        // (на некоторых версиях бэкенда эти эндпоинты разрешены для editor/viewer)
        final editorR = await get('/users/by-role/editor'); // список редакторов
        final viewerR = await get('/users/by-role/viewer'); // список читателей
        final seenIds = <int>{}; // дедупликация по id
        final combined = <UserModel>[];
        for (final r in [editorR, viewerR]) {
          if (r.statusCode == 200) {
            final list = _extractDataList(r.body)
                .map((e) => userFromJson(e as Map<String, dynamic>))
                .where(
                  (u) => u.role != 'admin' && u.id != currentUserId,
                ) // без admin и без себя
                .toList();
            for (final u in list) {
              if (seenIds.add(u.id))
                combined.add(u); // add возвращает false при дубле
            }
          }
        }
        subordinateUsers = combined;
      }
    }
  }

  // ── Телеметрия ────────────────────────────────────────────────────────────
  // GET /api/v1/telemetry/{sensor_id}/latest   — последнее измерение
  // GET /api/v1/telemetry/{sensor_id}/history?limit=N — история

  Future<void> loadHistory(int sensorId, String period) async {
    // загрузка истории для графика по периоду UI
    // FIX: по документации API эндпоинты:
    //   /telemetry/{sensor_id}/latest           — одно последнее
    //   /telemetry/{sensor_id}/history?limit=N  — история (N точек)
    // День → 100 точек, Неделя → 300, Месяц → 600
    final int limit; // число точек history
    switch (period) {
      // метка периода с экрана дашборда
      case 'День':
        limit = 100; // компактная история за день
      case 'Неделя':
        limit = 300; // средняя плотность
      default: // Месяц
        limit = 600; // длинная история
    }
    final endpoint =
        '/telemetry/$sensorId/history?limit=$limit'; // путь с лимитом

    final r = await get(endpoint); // GET JSON измерений
    if (r.statusCode != 200) return; // при ошибке молча выходим (график пустой)

    List<dynamic> measurements = []; // сырые точки
    dynamic decoded; // корень JSON (список или объект)
    try {
      decoded = jsonDecode(r.body); // парсинг тела ответа
      if (decoded is List) {
        // иногда API отдаёт массив напрямую
        measurements = decoded; // все элементы — измерения
      } else if (decoded is Map<String, dynamic>) {
        // обёртка с полями
        measurements =
            (decoded['measurements'] as List<dynamic>?) ??
            []; // массив измерений
        if (measurements.isEmpty && decoded['latest'] != null) {
          // fallback одной точкой
          measurements = [
            decoded['latest'],
          ]; // последнее как единственная точка
        }
      }
    } catch (_) {
      return;
    } // битый JSON — выход

    // FIX: Парсим все три поля вместе, чтобы индексы points/timestamps
    // всегда были синхронизированы. Точки с отсутствующими полями пропускаем.
    final tempPoints = <double>[]; // серии температуры
    final humPoints = <double>[]; // серии влажности
    final tsPoints = <DateTime>[]; // метки времени
    for (final raw in measurements) {
      // каждая запись
      final m = raw as Map<String, dynamic>; // поля измерения
      final temp = (m['temperature'] as num?)?.toDouble(); // t
      final hum = (m['humidity'] as num?)?.toDouble(); // h
      final tsRaw = m['timestamp'] as String?; // ISO время
      if (temp == null || hum == null || tsRaw == null)
        continue; // неполная запись — skip
      DateTime? dt; // распарсенное время
      try {
        dt = DateTime.parse(tsRaw);
      } catch (_) {
        continue;
      } // невалидная дата — skip
      tempPoints.add(temp); // добавляем в серию t
      humPoints.add(hum); // добавляем в серию h
      tsPoints.add(dt); // добавляем время
    }

    final i = sensors.indexWhere(
      (e) => e.id == sensorId,
    ); // индекс датчика в кеше
    if (i >= 0) {
      // датчик найден
      if (tempPoints.length > 1)
        sensors[i].points = tempPoints; // обновляем график t
      if (humPoints.length > 1)
        sensors[i].humidityPoints = humPoints; // обновляем график h
      if (tsPoints.length > 1) sensors[i].timestamps = tsPoints; // ось времени

      // Обновляем текущие показания из последнего измерения
      try {
        final latestRaw = decoded is Map<String, dynamic>
            ? decoded['latest']
            : null; // блок latest если есть
        final last =
            latestRaw ??
            (measurements.isNotEmpty
                ? measurements.last
                : null); // последняя точка
        if (last != null) {
          // есть что применить
          final lastMap =
              last as Map<String, dynamic>; // карта последнего замера
          sensors[i] =
              SensorModel(
                  // пересобираем модель с актуальными t/h
                  id: sensors[i].id, // id
                  name: sensors[i].name, // имя
                  groupId: sensors[i].groupId, // группа
                  location: sensors[i].location, // локация
                  temperature:
                      (lastMap['temperature'] as num?)?.toDouble() ??
                      sensors[i].temperature, // t из last
                  humidity:
                      (lastMap['humidity'] as num?)?.toDouble() ??
                      sensors[i].humidity, // h из last
                  state: sensors[i].state, // состояние не пересчитываем здесь
                  x: sensors[i].x, // координата
                  y: sensors[i].y, // координата
                  points: sensors[i].points, // уже обновлённые серии
                  humidityPoints: sensors[i].humidityPoints, // серии h
                  timestamps: sensors[i].timestamps, // времена
                  controlUnitId: sensors[i].controlUnitId, // ЦБУ
                  internalId: sensors[i].internalId, // internal
                  alarmDelaySeconds: sensors[i].alarmDelaySeconds, // задержка
                  powerStatus: sensors[i].powerStatus, // питание
                  batteryLevel: sensors[i].batteryLevel, // батарея
                  simBalance: sensors[i].simBalance, // SIM
                  gsmSignal: sensors[i].gsmSignal, // GSM
                  isOnline: sensors[i].isOnline, // онлайн
                  lastSeen: sensors[i].lastSeen, // last seen
                )
                ..warningMinTemp = sensors[i]
                    .warningMinTemp // пороги копируем
                ..warningMaxTemp = sensors[i].warningMaxTemp
                ..alarmMinTemp = sensors[i].alarmMinTemp
                ..alarmMaxTemp = sensors[i].alarmMaxTemp
                ..warningMinHum = sensors[i].warningMinHum
                ..warningMaxHum = sensors[i].warningMaxHum
                ..alarmMinHum = sensors[i].alarmMinHum
                ..alarmMaxHum = sensors[i].alarmMaxHum; // конец
        }
      } catch (_) {} // игнорируем сбой обновления last
    }
  }

  /// GET /api/v1/telemetry/{sensor_id}/latest — одно последнее измерение
  Future<void> refreshLatestTelemetry() async {
    if (sensors.isEmpty) return;

    final ids = sensors.map((s) => s.id).toList();
    final latest = await Future.wait(
      ids.map((id) async {
        try {
          return MapEntry(
            id,
            await getLatestTelemetry(id).timeout(const Duration(seconds: 4)),
          );
        } catch (_) {
          return MapEntry<int, SensorLiveData?>(id, null);
        }
      }),
    );

    final byId = Map<int, SensorLiveData?>.fromEntries(latest);
    sensors = sensors.map((s) {
      final live = byId[s.id];
      if (live == null) return s;

      final lastTimestamp = s.timestamps.isNotEmpty ? s.timestamps.last : null;
      final shouldAppend =
          lastTimestamp == null || live.timestamp.isAfter(lastTimestamp);
      final points = shouldAppend
          ? [
              ...(s.points.length >= 600
                  ? s.points.sublist(s.points.length - 599)
                  : s.points),
              live.temperature,
            ]
          : List<double>.of(s.points);
      final humidityPoints = shouldAppend
          ? [
              ...(s.humidityPoints.length >= 600
                  ? s.humidityPoints.sublist(s.humidityPoints.length - 599)
                  : s.humidityPoints),
              live.humidity,
            ]
          : List<double>.of(s.humidityPoints);
      final timestamps = shouldAppend
          ? [
              ...(s.timestamps.length >= 600
                  ? s.timestamps.sublist(s.timestamps.length - 599)
                  : s.timestamps),
              live.timestamp,
            ]
          : List<DateTime>.of(s.timestamps);

      return SensorModel(
          id: s.id,
          name: s.name,
          groupId: s.groupId,
          location: s.location,
          temperature: live.temperature,
          humidity: live.humidity,
          state: s.state,
          x: s.x,
          y: s.y,
          points: points,
          humidityPoints: humidityPoints,
          timestamps: timestamps,
          controlUnitId: s.controlUnitId,
          internalId: s.internalId,
          alarmDelaySeconds: s.alarmDelaySeconds,
          powerStatus: s.powerStatus,
          batteryLevel: s.batteryLevel,
          simBalance: s.simBalance,
          gsmSignal: s.gsmSignal,
          isOnline: true,
          lastSeen: live.timestamp.toIso8601String(),
        )
        ..warningMinTemp = s.warningMinTemp
        ..warningMaxTemp = s.warningMaxTemp
        ..alarmMinTemp = s.alarmMinTemp
        ..alarmMaxTemp = s.alarmMaxTemp
        ..warningMinHum = s.warningMinHum
        ..warningMaxHum = s.warningMaxHum
        ..alarmMinHum = s.alarmMinHum
        ..alarmMaxHum = s.alarmMaxHum;
    }).toList();

    _applySensorAlarmStates();
  }

  /// GET /api/v1/telemetry/{sensor_id}/latest — одно последнее измерение
  Future<SensorLiveData?> getLatestTelemetry(int sensorId) async {
    // мгновенный снимок с датчика
    try {
      final res = await get('/telemetry/$sensorId/latest'); // GET одной записи
      if (res.statusCode == 200) {
        // успех
        final data = jsonDecode(res.body); // dynamic JSON
        // FIX: SensorLiveData.fromJson теперь защищён от null-полей
        return SensorLiveData.fromJson(
          data as Map<String, dynamic>,
        ); // типизированная модель
      }
      return null; // не 200 — нет данных
    } catch (e) {
      debugPrint('Ошибка получения latest telemetry: $e'); // лог для отладки
      return null; // ошибка сети/парсинга
    }
  }
}
