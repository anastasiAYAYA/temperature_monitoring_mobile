part of '../app_repository.dart';

extension AppRepositoryUsersAudit on AppRepository {
  Future<String?> changePassword({
    // PATCH пароля в профиле
    required String oldPassword, // старый пароль
    required String newPassword, // новый пароль
  }) async {
    if (currentUserId == null)
      return 'Не удалось определить пользователя'; // нет id — нельзя PATCH
    final r = await patch('/users/${currentUserId!}', {
      // обновление пользователя
      'old_password': oldPassword, // проверка старого
      'new_password': newPassword, // новое значение
    });
    if (r.statusCode == 200) return null; // успех
    return parseError(r.body) ??
        'Не удалось сменить пароль (${r.statusCode})'; // ошибка API
  }

  /// GET /users/audit-logs — журнал действий
  Future<void> loadAuditLog() async {
    // загрузка аудита и маппинг на AuditEntry
    final r = await get(
      '/users/audit-logs?skip=0&limit=100',
    ); // последние записи
    if (r.statusCode != 200) return; // при ошибке оставляем старый audit

    // Кешируем имена пользователей: user_id -> отображаемое имя
    final userNames = <int, String>{}; // словарь имён для подстановки в строки
    if (currentUserId != null) {
      // текущий пользователь
      final displayName = (currentUserFullName?.isNotEmpty == true)
          ? currentUserFullName! // предпочитаем ФИО
          : (currentUser ?? ''); // иначе логин
      if (displayName.isNotEmpty)
        userNames[currentUserId!] = displayName; // запись в карту
    }
    for (final u in subordinateUsers) {
      // подчинённые из репозитория
      if (u.role == 'admin')
        continue; // admin никогда не попадает в журнал для editor/viewer
      userNames[u.id] = u.fullName.isNotEmpty
          ? u.fullName
          : u.username; // ФИО или логин
    }

    final rawList = _extractDataList(r.body); // сырые записи
    audit = rawList
        .map((e) {
          // каждая строка журнала
          final j = e as Map<String, dynamic>; // поля записи
          final uid =
              (j['user_id'] as num?)?.toInt() ?? 0; // кто совершил действие
          if (!userNames.containsKey(uid))
            return null; // исключаем admin и чужих локаций
          final tsRaw = j['timestamp'] as String? ?? ''; // сырое время ISO

          // Форматируем timestamp в локальное время
          String timeFormatted = tsRaw; // по умолчанию как пришло
          try {
            final dt = DateTime.parse(tsRaw).toLocal(); // локаль пользователя
            final h = dt.hour.toString().padLeft(2, '0'); // часы
            final mn = dt.minute.toString().padLeft(2, '0'); // минуты
            final day = dt.day.toString().padLeft(2, '0'); // день
            final month = dt.month.toString().padLeft(2, '0'); // месяц
            timeFormatted =
                '$day.$month.${dt.year}  $h:$mn'; // человекочитаемая строка
          } catch (_) {} // если парсинг не удался — остаётся tsRaw

          return AuditEntry(
            user:
                userNames[uid]!, // имя сотрудника (не admin — гарантировано предыдущим containsKey)
            action: j['action'] as String? ?? '', // тип действия
            time: timeFormatted, // время для списка UI
          );
        })
        .whereType<AuditEntry>()
        .toList(); // фильтруем null (записи админа и чужих локаций)
  }

  // ── Пользователи ──────────────────────────────────────────────────────────

  Future<String?> createUser({
    // регистрация сотрудника админом/по API
    required String username,
    required String password, // учётные данные
    required String fullName,
    required String roleName, // ФИО и роль строкой
    required int? locationId,
    String? email, // привязка к локации и почта
  }) async {
    final r = await post('/users/register', {
      // POST создание пользователя
      'username': username, 'password': password, // логин/пароль
      'full_name': fullName, 'role': roleName, // профиль
      'location_id': locationId, // может быть null для admin глобально
      if (email != null) 'email': email, // опционально
    });
    if (r.statusCode == 200 || r.statusCode == 201) return null; // успех
    return parseError(r.body) ?? 'Не удалось создать сотрудника'; // ошибка
  }

  // ── Парсеры ───────────────────────────────────────────────────────────────

  SensorModel sensorFromJson(Map<String, dynamic> j) {
    // JSON датчика → модель (до обогащения в loadAll)
    final id = (j['id'] as num?)?.toInt() ?? 0; // id записи
    final isOnline =
        j['is_online'] != false; // по умолчанию онлайн если поле отсутствует
    final state = isOnline
        ? SensorState.normal
        : SensorState.critical; // базовое состояние по связи

    final sensor = SensorModel(
      id: id, // id
      name: j['name'] as String? ?? 'Датчик', // имя или дефолт
      groupId: (j['group_id'] as num?)?.toInt() ?? 0, // локация
      // Временное значение — будет перезаписано реальным именем в loadAll()
      // после загрузки локаций из /locations/
      location:
          'Локация #${(j['group_id'] as num?)?.toInt() ?? 0}', // заглушка до merge с locations
      temperature: 0.0, // позже подтянется телеметрией
      humidity: 0.0, // позже подтянется телеметрией
      state: state, // normal/critical по онлайну
      x: _normalizePos(
        (j['pos_x'] as num?)?.toDouble() ?? 0.1,
      ), // позиция на плане
      y: _normalizePos(
        (j['pos_y'] as num?)?.toDouble() ?? 0.1,
      ), // позиция на плане
      points: [], // история для графика заполнится loadHistory
      humidityPoints: [], // история влажности
      controlUnitId: (j['control_unit_id'] as num?)?.toInt(), // ЦБУ
      internalId: j['internal_id'] as String?, // строковый id
      alarmDelaySeconds:
          (j['alarm_delay_seconds'] as num?)?.toInt() ?? 0, // задержка тревоги
      isOnline: isOnline, // флаг связи
      lastSeen: j['last_seen'] as String?, // время последней связи
    );

    sensor.warningMinTemp = _thresh(j['warning_min_temp']); // пороги из JSON
    sensor.warningMaxTemp = _thresh(j['warning_max_temp']);
    sensor.alarmMinTemp = _thresh(j['alarm_min_temp']);
    sensor.alarmMaxTemp = _thresh(j['alarm_max_temp']);
    sensor.warningMinHum = _thresh(j['warning_min_hum']);
    sensor.warningMaxHum = _thresh(j['warning_max_hum']);
    sensor.alarmMinHum = _thresh(j['alarm_min_hum']);
    sensor.alarmMaxHum = _thresh(j['alarm_max_hum']);
    return sensor; // готовая модель (mutable пороги установлены)
  }

  /// Нормализует позицию датчика в диапазон 0.0–1.0.
  /// Если значение > 1.0 — это устаревшее абсолютное значение в пикселях,
  /// которое зажимаем до 0.5 (центр), чтобы датчик был виден.
}
