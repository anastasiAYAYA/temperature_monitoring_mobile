part of '../app_repository.dart';

extension AppRepositoryParsing on AppRepository {
  double _normalizePos(double v) =>
      v <= 1.0 ? v.clamp(0.0, 1.0) : v; // относительные координаты или центр

  /// Парсит порог из JSON.
  /// null → не задан. Любое число включая 0.0 → валидное значение.
  double? _thresh(dynamic v) {
    // унифицированное чтение double?
    if (v == null) return null; // отсутствие в JSON
    return (v as num).toDouble(); // числовое значение
  }

  /// Пересчитывает [SensorModel.state] по активным тревогам из [alarms].
  ///
  /// Приоритеты (от высшего к низшему):
  ///   critical  → датчик офлайн ИЛИ активная тревога с severity == critical → красный (kRed)
  ///   warning   → активная тревога с severity == warning / info             → жёлтый (kAccent / kOrange)
  ///   normal    → нет активных тревог (resolved не считается)               → зелёный (kGreen)
  ///
  /// «Активная» тревога — статус newAlarm или acknowledged (не resolved).
  /// Вызывайте после любого изменения списка [alarms] (loadAll, updateAlarm, WS).
  /// SensorModel.state — final-поле: пересоздаём объект через _copyWithState.
  void _applySensorAlarmStates() {
    // Собираем множество sensor_id с критическими и warning тревогами
    final criticalIds = <int>{}; // датчики с critical-тревогой
    final warningIds = <int>{}; // датчики с warning-тревогой (но не critical)
    for (final alarm in alarms) {
      if (alarm.status == AlarmStatus.resolved)
        continue; // закрытые не влияют на цвет
      final sid = alarm.sensorId;
      if (sid == null) continue;
      if (alarm.severity == AlarmSeverity.critical) {
        criticalIds.add(sid); // critical → красный
      } else {
        warningIds.add(sid); // warning / info → жёлтый
      }
    }

    // Пересоздаём датчики с новым state (state — final, мутация через _copyWithState)
    for (int i = 0; i < sensors.length; i++) {
      final s = sensors[i];
      // Офлайн всегда critical — приоритет выше тревог (датчик недоступен)
      final newState = !s.isOnline
          ? SensorState.critical
          : criticalIds.contains(s.id)
          ? SensorState
                .critical // активная critical-тревога → красный
          : warningIds.contains(s.id)
          ? SensorState
                .warning // активная warning-тревога → жёлтый
          : SensorState.normal; // нет активных тревог → зелёный
      if (s.state == newState)
        continue; // не трогаем если уже верное — экономим аллокации
      sensors[i] = _copyWithState(s, newState); // пересоздаём с новым state
    }
  }

  /// Создаёт копию [SensorModel] с заменённым [state].
  /// Все остальные поля (включая mutable пороги) копируются.
  SensorModel _copyWithState(SensorModel s, SensorState state) {
    return SensorModel(
        id: s.id,
        name: s.name,
        groupId: s.groupId,
        location: s.location,
        temperature: s.temperature,
        humidity: s.humidity,
        state: state, // ← новое состояние (цвет маркера на схеме)
        x: s.x,
        y: s.y,
        points: s.points,
        humidityPoints: s.humidityPoints,
        timestamps: s.timestamps,
        controlUnitId: s.controlUnitId,
        internalId: s.internalId,
        alarmDelaySeconds: s.alarmDelaySeconds,
        powerStatus: s.powerStatus,
        batteryLevel: s.batteryLevel,
        simBalance: s.simBalance,
        gsmSignal: s.gsmSignal,
        isOnline: s.isOnline,
        lastSeen: s.lastSeen,
      )
      ..warningMinTemp = s.warningMinTemp
      ..warningMaxTemp = s.warningMaxTemp
      ..alarmMinTemp = s.alarmMinTemp
      ..alarmMaxTemp = s.alarmMaxTemp
      ..warningMinHum = s.warningMinHum
      ..warningMaxHum = s.warningMaxHum
      ..alarmMinHum = s.alarmMinHum
      ..alarmMaxHum = s.alarmMaxHum;
  }

  SensorModel _mergeSensorHistory(SensorModel sensor, SensorModel previous) {
    final points = sensor.points.isNotEmpty
        ? sensor.points
        : List<double>.of(previous.points);
    final humidityPoints = sensor.humidityPoints.isNotEmpty
        ? sensor.humidityPoints
        : List<double>.of(previous.humidityPoints);
    final timestamps = sensor.timestamps.isNotEmpty
        ? sensor.timestamps
        : List<DateTime>.of(previous.timestamps);

    return SensorModel(
        id: sensor.id,
        name: sensor.name,
        groupId: sensor.groupId,
        location: sensor.location,
        temperature: points.isNotEmpty
            ? previous.temperature
            : sensor.temperature,
        humidity: humidityPoints.isNotEmpty
            ? previous.humidity
            : sensor.humidity,
        state: sensor.state,
        x: sensor.x,
        y: sensor.y,
        points: points,
        humidityPoints: humidityPoints,
        timestamps: timestamps,
        controlUnitId: sensor.controlUnitId ?? previous.controlUnitId,
        internalId: sensor.internalId ?? previous.internalId,
        alarmDelaySeconds: sensor.alarmDelaySeconds,
        powerStatus: sensor.powerStatus ?? previous.powerStatus,
        batteryLevel: sensor.batteryLevel ?? previous.batteryLevel,
        simBalance: sensor.simBalance ?? previous.simBalance,
        gsmSignal: sensor.gsmSignal ?? previous.gsmSignal,
        isOnline: sensor.isOnline,
        lastSeen: sensor.lastSeen ?? previous.lastSeen,
      )
      ..warningMinTemp = sensor.warningMinTemp
      ..warningMaxTemp = sensor.warningMaxTemp
      ..alarmMinTemp = sensor.alarmMinTemp
      ..alarmMaxTemp = sensor.alarmMaxTemp
      ..warningMinHum = sensor.warningMinHum
      ..warningMaxHum = sensor.warningMaxHum
      ..alarmMinHum = sensor.alarmMinHum
      ..alarmMaxHum = sensor.alarmMaxHum;
  }

  AlarmModel alarmFromJson(Map<String, dynamic> j) {
    // парсинг тревоги с API
    final st = switch (j['status'] as String? ?? '') {
      // строка статуса → enum
      'acknowledged' => AlarmStatus.acknowledged, // в работе
      'resolved' => AlarmStatus.resolved, // закрыто
      _ => AlarmStatus.newAlarm, // новое/прочее
    };
    final sev = switch (j['severity'] as String? ?? '') {
      // серьёзность
      'critical' => AlarmSeverity.critical,
      'info' => AlarmSeverity.info,
      _ => AlarmSeverity.warning,
    };

    final alarmType = j['alarm_type'] as String?; // машинный тип события
    final title = switch (alarmType) {
      // человекочитаемый заголовок по типу
      'temperature' => 'Температура вне нормы',
      'humidity' => 'Влажность вне нормы',
      'connection_lost' => 'Потеря связи',
      'low_battery' => 'Низкий заряд батареи',
      _ => alarmType ?? (j['severity'] as String?) ?? 'Событие', // fallback
    };

    return AlarmModel(
      id: (j['id'] as num?)?.toInt() ?? 0, // id тревоги
      title: title, // заголовок для UI
      description: (j['description'] as String?) ?? '', // текст описания
      status: st, // enum статуса
      sensorId: (j['sensor_id'] as num?)?.toInt(), // привязка к датчику
      severity: sev, // уровень важности
      alarmType: alarmType, // сырой тип
      timestamp: j['timestamp'] as String?, // время события
      comment:
          (j['user_comment'] as String?) ??
          (j['comment'] as String?), // комментарий оператора
      resolvedAt: j['resolved_at'] as String?, // когда закрыто
      resolvedById: (j['resolved_by_id'] as num?)?.toInt(), // кто закрыл
    );
  }

  UserModel userFromJson(Map<String, dynamic> j) => UserModel(
    // парсинг пользователя API
    id: (j['id'] as num?)?.toInt() ?? 0, // id
    username: j['username'] as String? ?? '', // логин
    fullName: j['full_name'] as String? ?? '', // ФИО
    role: j['role'] as String? ?? 'viewer', // роль строкой
    email: j['email'] as String?, // email опционально
  );
}
