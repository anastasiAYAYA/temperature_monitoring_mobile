part of '../app_repository.dart';

extension AppRepositoryWebSocket on AppRepository {
  void connectWebSocket(
    // публичный вход подключения WS
    void Function(int sensorId, double temp, double hum, bool isAlarm)
    onData, // слушатель событий
  ) {
    _wsCallback = onData; // сохраняем колбэк
    _wsReconnecting = false; // сбрасываем флаг перед коннектом
    _wsConnect(); // стартуем соединение
  }

  /// Регистрирует колбэк для live-обновлений позиции датчиков с мнемосхемы.
  /// Вызывайте из DashboardScreen.initState / при открытии схемы.
  void setPositionCallback(
    void Function(int sensorId, double posX, double posY, int? groupId) cb,
  ) {
    _wsPosCallback = cb;
  }

  /// Снимает колбэк позиции (вызывать из dispose экрана схемы).
  void clearPositionCallback() {
    _wsPosCallback = null;
  }

  void _wsConnect() {
    // внутреннее подключение к каналу alarms
    WebSocket.connect('ws://157.90.127.202:8000/ws/alarms')
        .then((ws) {
          // асинхронный коннект
          _wsChannel = ws; // сохраняем сокет
          debugPrint('[WS] Подключён к ws/alarms'); // лог
          ws.listen(
            // подписка на поток сообщений
            _wsOnData, // обработчик строки JSON
            onError: (_) => _wsScheduleReconnect(), // при ошибке — реконнект
            onDone: () => _wsScheduleReconnect(), // при закрытии — реконнект
            cancelOnError: true, // отмена подписки при ошибке
          );
        })
        .catchError((e) {
          // ошибка TCP/TLS/handshake
          debugPrint('[WS] Ошибка подключения: $e'); // лог
          _wsScheduleReconnect(); // пробуем позже
        });
  }

  void _wsOnData(dynamic raw) {
    // приходит String из WebSocket
    try {
      final j =
          jsonDecode(raw as String) as Map<String, dynamic>; // парсинг события

      // ── Синхронизация позиций датчиков на мнемосхеме ─────────────────────
      // Когда другой клиент (React или другой Flutter) сохраняет позицию,
      // сервер рассылает этот тип всем подключённым по WS клиентам.
      // Обновляем локальный кеш сразу — без лишнего HTTP-запроса.
      // Тип события по API-документации: "sensor_position"
      // (поля: sensor_id, pos_x, pos_y, group_id).
      // Также поддерживается устаревший тип "sensor_position_updated" для
      // обратной совместимости с предыдущей версией бэкенда.
      if (j['type'] == 'sensor_position' ||
          j['type'] == 'sensor_position_updated') {
        final sensorId = (j['sensor_id'] as num).toInt(); // id датчика
        final posX = (j['pos_x'] as num).toDouble(); // новая X (0…1)
        final posY = (j['pos_y'] as num).toDouble(); // новая Y (0…1)
        final groupId = (j['group_id'] as num?)
            ?.toInt(); // id локации (фильтр в UI)
        final i = sensors.indexWhere((s) => s.id == sensorId); // ищем в кеше
        if (i >= 0) {
          sensors[i].x = posX; // обновляем координату X
          sensors[i].y = posY; // обновляем координату Y
          // Уведомляем экран мнемосхемы — перерисовать маркер без полного рефетча
          _wsPosCallback?.call(sensorId, posX, posY, groupId);
          _wsCallback?.call(
            sensorId,
            sensors[i].temperature,
            sensors[i].humidity,
            false,
          ); // общий UI
        }
        return; // больше ничего не делаем для этого типа
      }

      if (j['type'] != 'new_measurement')
        return; // интересует только новое измерение

      final sensorId = (j['sensor_id'] as num).toInt(); // id датчика
      final temp = (j['temp'] as num).toDouble(); // температура
      final hum = (j['hum'] as num).toDouble(); // влажность
      final isAlarm = j['is_alarm'] as bool? ?? false; // флаг тревоги с сервера
      // FIX: используем серверный timestamp если есть, иначе текущее время
      DateTime eventTime = DateTime.now(); // fallback время события
      try {
        final tsRaw = j['timestamp'] as String?; // ISO с сервера
        if (tsRaw != null)
          eventTime = DateTime.parse(tsRaw); // предпочитаем серверное
      } catch (_) {} // игнор кривого timestamp

      // Обновляем датчик в локальном списке
      final i = sensors.indexWhere((s) => s.id == sensorId); // позиция в кеше
      if (i >= 0) {
        // найден
        final s = sensors[i]; // старая модель (короче писать)
        sensors[i] =
            SensorModel(
                // новая модель с обновлёнными полями и буферами
                id: s.id, // id
                name: s.name, // имя
                groupId: s.groupId, // группа
                location: s.location, // локация
                temperature: temp, // live t
                humidity: hum, // live h
                // FIX: состояние из WS-события учитывает isAlarm (critical/normal),
                // но не знает о уже существующих warning-тревогах на этом датчике.
                // После обновления кеша _applySensorAlarmStates скорректирует state.
                state: isAlarm
                    ? SensorState.critical
                    : SensorState.normal, // предварительный цвет по событию
                x: s.x, // позиция на плане
                y: s.y, // позиция на плане
                points: [
                  // буфер температур (скользящее окно)
                  ...(s.points.length >= 600
                      ? s.points.sublist(s.points.length - 599)
                      : s.points), // обрезка хвоста
                  temp, // новая точка
                ],
                humidityPoints: [
                  // буфер влажности
                  ...(s.humidityPoints.length >= 600
                      ? s.humidityPoints.sublist(s.humidityPoints.length - 599)
                      : s.humidityPoints),
                  hum, // новая точка h
                ],
                timestamps: [
                  // синхронные метки времени
                  ...(s.timestamps.length >= 600
                      ? s.timestamps.sublist(s.timestamps.length - 599)
                      : s.timestamps),
                  eventTime, // FIX: серверное время вместо DateTime.now()
                ],
                controlUnitId: s.controlUnitId, // ЦБУ
                internalId: s.internalId, // internal
                alarmDelaySeconds: s.alarmDelaySeconds, // задержка
                powerStatus: s.powerStatus, // питание
                batteryLevel: s.batteryLevel, // батарея
                simBalance: s.simBalance, // SIM
                gsmSignal: s.gsmSignal, // GSM
                isOnline: true, // live-событие ⇒ считаем онлайн
                lastSeen: s.lastSeen, // last seen не трогаем здесь
              )
              ..warningMinTemp = s
                  .warningMinTemp // пороги
              ..warningMaxTemp = s.warningMaxTemp
              ..alarmMinTemp = s.alarmMinTemp
              ..alarmMaxTemp = s.alarmMaxTemp
              ..warningMinHum = s.warningMinHum
              ..warningMaxHum = s.warningMaxHum
              ..alarmMinHum = s.alarmMinHum
              ..alarmMaxHum = s.alarmMaxHum; // конец
      }

      // Пересчитываем цвета всех датчиков с учётом существующих тревог.
      // Это исправляет кейс: датчик был warning (жёлтый), пришёл новый normal-пакет →
      // без _applySensorAlarmStates он стал бы зелёным, хотя warning-тревога ещё активна.
      _applySensorAlarmStates();
      _wsCallback?.call(sensorId, temp, hum, isAlarm); // уведомляем UI
    } catch (e) {
      debugPrint('[WS] Ошибка парсинга: $e'); // битый JSON
    }
  }

  void _wsScheduleReconnect() {
    // отложенное переподключение
    if (_wsReconnecting || _wsCallback == null)
      return; // уже ждём или отключились полностью
    _wsReconnecting = true; // блокируем дубли
    debugPrint('[WS] Реконнект через 5 сек...'); // лог
    Future.delayed(const Duration(seconds: 5), () {
      // таймер
      if (_wsCallback != null) {
        // колбэк ещё актуален
        _wsReconnecting = false; // снимаем блок до нового коннекта
        _wsConnect(); // новая попытка
      }
    });
  }

  void disconnectWebSocket() {
    // явное отключение (logout и т.д.)
    _wsCallback = null; // больше не уведомляем UI
    _wsReconnecting = false; // не реконнектимся
    _wsChannel?.close(); // закрываем сокет
    _wsChannel = null; // обнуляем ссылку
    debugPrint('[WS] Отключён'); // лог
  }

  // ── Тревоги ───────────────────────────────────────────────────────────────
  // PATCH /alarms/{id}  { "status": "...", "user_comment": "..." }
  // Статусы: "new" | "in_progress" | "resolved"
}
