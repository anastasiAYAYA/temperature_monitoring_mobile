part of '../app_repository.dart';

extension AppRepositoryAlarmsSensors on AppRepository {
  Future<String?> updateAlarm(
    int alarmId,
    String status,
    String comment,
  ) async {
    // PATCH статуса/комментария тревоги
    final body = <String, dynamic>{
      'status': status,
    }; // обязательное поле статус API
    if (comment.trim().isNotEmpty)
      body['user_comment'] = comment
          .trim(); // опциональный комментарий оператора

    debugPrint('[alarm PATCH] body=$body'); // отладочный лог тела
    final r = await patch('/alarms/$alarmId', body); // PATCH на сервер
    debugPrint(
      '[alarm PATCH] status=${r.statusCode} body=${r.body}',
    ); // ответ сервера

    if (r.statusCode == 200) {
      // успех
      final data =
          jsonDecode(r.body) as Map<String, dynamic>; // обновлённый объект
      final updated = alarmFromJson(data); // парсинг AlarmModel
      final idx = alarms.indexWhere(
        (a) => a.id == alarmId,
      ); // позиция в локальном списке
      if (idx >= 0) alarms[idx] = updated; // заменяем элемент кеша
      // Пересчитываем цвета датчиков: статус тревоги изменился (напр. resolved → датчик зеленеет).
      _applySensorAlarmStates();
      return null; // без ошибки
    }
    return parseError(r.body) ??
        'Ошибка изменения тревоги (${r.statusCode})'; // текст ошибки
  }

  // ── Датчики ───────────────────────────────────────────────────────────────
  // POST /sensors/create_sensor
  // PATCH /sensors/{id}/thresholds  — пороги устанавливаются отдельно

  Future<String?> createSensor({
    // POST создание датчика на сервере
    required String name, // отображаемое имя
    required int locationId, // group_id / локация
    int? controlUnitId, // опциональная привязка к ЦБУ
    String? internalId, // строковый id на шине устройства
    double? warningMinTemp,
    double? warningMaxTemp, // пороги предупреждения t
    double? alarmMinTemp,
    double? alarmMaxTemp, // пороги аварии t
    double? warningMinHum,
    double? warningMaxHum, // пороги предупреждения h
    double? alarmMinHum,
    double? alarmMaxHum, // пороги аварии h
    int alarmDelaySeconds = 0, // задержка перед созданием тревоги
  }) async {
    final createBody = <String, dynamic>{
      // тело POST (только заданные поля)
      'name': name, // имя датчика
      'group_id': locationId, // id локации в API
      if (controlUnitId != null) 'control_unit_id': controlUnitId, // ЦБУ
      if (internalId != null) 'internal_id': internalId, // internal
      if (warningMinTemp != null)
        'warning_min_temp': warningMinTemp, // пороги t
      if (warningMaxTemp != null) 'warning_max_temp': warningMaxTemp,
      if (alarmMinTemp != null) 'alarm_min_temp': alarmMinTemp,
      if (alarmMaxTemp != null) 'alarm_max_temp': alarmMaxTemp,
      if (warningMinHum != null) 'warning_min_hum': warningMinHum, // пороги h
      if (warningMaxHum != null) 'warning_max_hum': warningMaxHum,
      if (alarmMinHum != null) 'alarm_min_hum': alarmMinHum,
      if (alarmMaxHum != null) 'alarm_max_hum': alarmMaxHum,
      'alarm_delay_seconds': alarmDelaySeconds, // задержка
    };
    final r = await post(
      '/sensors/create_sensor',
      createBody,
    ); // создаём ресурс

    if (r.statusCode != 200 && r.statusCode != 201) {
      // неуспех
      return parseError(r.body) ??
          'Не удалось добавить датчик (${r.statusCode})'; // сообщение
    }
    return null; // ОК — список sensors обновят при следующем loadAll
  }

  Future<String?> updateSensorPosition({
    // сохранить координаты на плане (нормализованные)
    required int sensorId,
    required double posX,
    required double posY, // id и позиция 0–1
  }) async {
    final r = await patch('/sensors/$sensorId/position', {
      'pos_x': posX,
      'pos_y': posY,
    }); // PATCH позиции
    if (r.statusCode != 200)
      return parseError(r.body) ??
          'Не удалось сохранить позицию'; // ошибка HTTP
    final i = sensors.indexWhere((e) => e.id == sensorId); // локальный индекс
    if (i >= 0) {
      sensors[i].x = posX;
      sensors[i].y = posY;
    } // синхронизируем кеш
    return null; // успех
  }

  Future<String?> renameSensor({
    required int sensorId,
    required String name,
  }) async {
    // PATCH имени датчика для админ-панели
    final cleanName = name.trim(); // не отправляем пустые/пробельные значения
    if (cleanName.isEmpty) return 'Введите название датчика';
    final r = await patch('/sensors/$sensorId', {
      'name': cleanName,
    }); // универсальный PATCH /sensors/{id}
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Не удалось переименовать датчик (${r.statusCode})';
    }
    return null; // локальный кеш обновит loadAll после успешного сохранения
  }

  Future<String?> deleteSensor(int sensorId) async {
    // DELETE датчика, если endpoint включён на backend
    final r = await delete(
      '/sensors/$sensorId',
    ); // в документации endpoint может отсутствовать на части backend-сборок
    if (r.statusCode != 200 && r.statusCode != 204) {
      return parseError(r.body) ??
          'Удаление датчика недоступно на сервере (${r.statusCode})';
    }
    return null; // список обновится через loadAll
  }

  Future<String?> updateSensorThresholds({
    // PATCH порогов t/h
    required int sensorId, // id датчика
    required double warningMinTemp,
    required double warningMaxTemp, // предупреждение t
    required double alarmMinTemp,
    required double alarmMaxTemp, // авария t
    double? warningMinHum,
    double? warningMaxHum, // предупреждение h (опц.)
    double? alarmMinHum,
    double? alarmMaxHum, // авария h (опц.)
  }) async {
    final idx = sensors.indexWhere((e) => e.id == sensorId); // индекс в кеше
    if (idx < 0) return 'Датчик не найден'; // нет такого id локально
    final body = <String, dynamic>{
      // JSON для thresholds
      'warning_min_temp': warningMinTemp,
      'warning_max_temp': warningMaxTemp, // t warn
      'alarm_min_temp': alarmMinTemp, 'alarm_max_temp': alarmMaxTemp, // t alarm
      if (warningMinHum != null) 'warning_min_hum': warningMinHum, // h warn
      if (warningMaxHum != null) 'warning_max_hum': warningMaxHum,
      if (alarmMinHum != null) 'alarm_min_hum': alarmMinHum, // h alarm
      if (alarmMaxHum != null) 'alarm_max_hum': alarmMaxHum,
    };
    final r = await patch(
      '/sensors/$sensorId/thresholds',
      body,
    ); // отдельный эндпоинт порогов
    if (r.statusCode != 200)
      return parseError(r.body) ??
          'Не удалось сохранить пороги (${r.statusCode})'; // ошибка
    sensors[idx] // обновляем локальные mutable поля порогов
      ..warningMinTemp = warningMinTemp
      ..warningMaxTemp =
          warningMaxTemp // каскад присваиваний
      ..alarmMinTemp = alarmMinTemp
      ..alarmMaxTemp = alarmMaxTemp
      ..warningMinHum = warningMinHum
      ..warningMaxHum = warningMaxHum
      ..alarmMinHum = alarmMinHum
      ..alarmMaxHum = alarmMaxHum;
    return null; // успех
  }

  /// POST /control-units/register — регистрация ЦБУ/AlertBox
}
