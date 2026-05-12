part of '../app_repository.dart';

extension AppRepositoryControlUnits on AppRepository {
  Future<({String? error, String? ingestionToken})> createControlUnit({
    // регистрация ЦБУ на сервере
    required String name, // человекочитаемое имя блока
    required int locationId, // привязка к группе/локации
    required String serialNumber, // серийник железа
    String? devEui, // LoRaWAN DevEUI опционально
    String? appKey, // ключ приложения LoRa опционально
  }) async {
    final body = <String, dynamic>{
      // тело register
      'name': name, // имя
      'group_id': locationId, // локация
      'serial_number': serialNumber, // SN
      if (devEui != null && devEui.isNotEmpty)
        'dev_eui': devEui, // только если задан
      if (appKey != null && appKey.isNotEmpty)
        'app_key': appKey, // только если задан
    };
    final r = await post('/control-units/register', body); // создаём ЦБУ
    if (r.statusCode == 200 || r.statusCode == 201) {
      // успех
      String? ingestionToken; // токен для прошивки (не показываем в UI обычно)
      try {
        final data =
            jsonDecode(r.body) as Map<String, dynamic>; // ответ сервера
        ingestionToken = data['ingestion_token'] as String?; // извлекаем токен
        final cuList = await get('/control-units/'); // обновляем список ЦБУ
        if (cuList.statusCode == 200) {
          // OK
          controlUnits = _extractDataList(
            cuList.body,
          ).cast<Map<String, dynamic>>().toList(); // кеш ЦБУ
        }
      } catch (_) {} // игнорируем сбой доброса списка
      return (
        error: null,
        ingestionToken: ingestionToken,
      ); // успех + токен вызывающему коду
    }
    return (
      // ошибка создания
      error:
          parseError(r.body) ??
          'Не удалось создать блок управления (${r.statusCode})', // текст
      ingestionToken: null, // токена нет
    );
  }

  Future<String?> renameControlUnit({
    required int unitId,
    required String name,
  }) async {
    // PATCH имени блока управления
    final cleanName = name.trim(); // имя обязательно
    if (cleanName.isEmpty) return 'Введите название блока';
    final r = await patch('/control-units/$unitId', {
      'name': cleanName,
    }); // PATCH /control-units/{id}
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Не удалось переименовать блок (${r.statusCode})';
    }
    return null; // кеш обновится через loadAll
  }

  Future<List<SensorModel>> loadControlUnitSensors(int unitId) async {
    // GET /control-units/{id}/sensors — фактический список привязанных датчиков.
    final r = await get('/control-units/$unitId/sensors');
    if (r.statusCode != 200) return const [];
    return _extractDataList(
      r.body,
    ).map((e) => sensorFromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String?> deleteControlUnit(
    int unitId, {
    bool detachSensors = false,
  }) async {
    // DELETE /control-units/{id}; detach_sensors=true оставляет датчики и очищает у них control_unit_id.
    final path = detachSensors
        ? '/control-units/$unitId?detach_sensors=true'
        : '/control-units/$unitId';
    final r = await delete(path);
    if (r.statusCode != 200 && r.statusCode != 204) {
      return _reportErrorMessage(r) ??
          'Не удалось удалить блок (${r.statusCode})';
    }
    return null; // кеш обновится через loadAll
  }

  /// POST /control-units/heartbeat — периодическая отправка heartbeat от ЦБУ.
  Future<void> sendHeartbeat({
    // имитация «живости» ЦБУ с клиента (демо/обход)
    required String serialNumber, // SN устройства
    required String ingestionToken, // секрет для heartbeat
    int? batteryLevel, // опционально уровень %
    String? powerStatus, // mains/battery
    int? gsmSignal, // уровень сигнала
  }) async {
    try {
      final body = <String, dynamic>{
        // JSON для heartbeat
        'serial_number': serialNumber, // идентификация железа
        'token': ingestionToken, // авторизация heartbeat
        if (batteryLevel != null) 'battery_level': batteryLevel, // заряд
        if (powerStatus != null)
          'power_status': powerStatus, // источник питания
        if (gsmSignal != null) 'gsm_signal': gsmSignal, // gsm
      };
      await http
          .post(
            // отдельный http.post (не patch/get helper)
            Uri.parse('$baseUrl/control-units/heartbeat'), // URL heartbeat
            headers: {
              'Authorization': 'Bearer $token', // JWT пользователя приложения
              'Content-Type': 'application/json', // JSON тело
            },
            body: jsonEncode(body), // сериализация
          )
          .timeout(const Duration(seconds: 10)); // защита от зависания
    } catch (e) {
      debugPrint('[heartbeat] Ошибка: $e'); // не роняем приложение
    }
  }

  void startHeartbeatLoop() {
    // запуск периодической отправки heartbeat по всем ЦБУ
    _stopHeartbeatLoop(); // сбрасываем предыдущий таймер если был
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // каждые 30 с
      for (final unit in controlUnits) {
        // каждый блок из кеша
        final serialNumber = unit['serial_number'] as String?; // SN
        final ingestionToken = unit['ingestion_token'] as String?; // токен
        if (serialNumber == null || ingestionToken == null)
          continue; // неполные данные — skip
        await sendHeartbeat(
          // шлём статус «как на сервере в loadAll»
          serialNumber: serialNumber, // SN
          ingestionToken: ingestionToken, // token
          batteryLevel: (unit['battery_level'] as num?)?.toInt(), // из кеша ЦБУ
          powerStatus: unit['power_status'] as String?, // из кеша
          gsmSignal: (unit['gsm_signal'] as num?)?.toInt(), // из кеша
        );
      }
    });
  }

  void _stopHeartbeatLoop() {
    // остановка таймера heartbeat
    _heartbeatTimer?.cancel(); // отмена periodic
    _heartbeatTimer = null; // обнуляем ссылку
  }

  void stopHeartbeatLoop() =>
      _stopHeartbeatLoop(); // публичная обёртка (logout и т.д.)

  /// POST /api/v1/sensors/{sensor_id}/set-medication?drug_name=...
  /// ИИ автоматически устанавливает пороги по названию препарата
  Future<String?> setSensorMedication({
    // ИИ-подбор порогов по названию лекарства
    required int sensorId, // id датчика
    required String drugName, // строка запроса к ИИ
  }) async {
    final uri =
        Uri.parse('$baseUrl/sensors/$sensorId/set-medication') // базовый путь
            .replace(
              queryParameters: {'drug_name': drugName},
            ); // query drug_name
    final r = await http
        .post(
          uri, // POST без JSON тела — только query
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_kTimeout); // JWT
    if (r.statusCode == 200) {
      // пороги применены на сервере и в теле ответа
      try {
        final data =
            jsonDecode(r.body) as Map<String, dynamic>; // распарсенные пороги
        final idx = sensors.indexWhere(
          (e) => e.id == sensorId,
        ); // локальный датчик
        if (idx >= 0) {
          // найден
          sensors[idx].warningMinTemp = _thresh(
            data['warning_min_temp'],
          ); // обновляем поля
          sensors[idx].warningMaxTemp = _thresh(data['warning_max_temp']);
          sensors[idx].alarmMinTemp = _thresh(data['alarm_min_temp']);
          sensors[idx].alarmMaxTemp = _thresh(data['alarm_max_temp']);
          sensors[idx].alarmMinHum = _thresh(data['alarm_min_hum']);
          sensors[idx].alarmMaxHum = _thresh(data['alarm_max_hum']);
        }
      } catch (_) {} // игнорируем кривой JSON
      return null; // успех без сообщения
    }
    if (r.statusCode == 503)
      return 'ИИ-сервис временно недоступен. Попробуйте позже.'; // специфичная ошибка
    return parseError(r.body) ??
        'Ошибка настройки порогов (${r.statusCode})'; // прочие ошибки
  }

  // ── Локации ───────────────────────────────────────────────────────────────
}
