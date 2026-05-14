part of '../app_repository.dart';

extension AppRepositoryLocationsReports on AppRepository {
  Future<String?> createLocation({required String name}) async {
    // создать локацию (компанию) только именем
    try {
      final uri = Uri.parse('$baseUrl/locations/');
      final request =
          http.MultipartRequest('POST', uri)
            ..headers['Authorization'] = 'Bearer $token'
            ..fields['name'] = name;
      final response = await http.Response.fromStream(
        await request.send().timeout(_kTimeout),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final id = (data['id'] as num?)?.toInt();
          final nm = data['name'] as String? ?? name;
          if (id != null) {
            locations.add(LocationModel(id: id, name: nm));
          }
        } catch (_) {}
        return null;
      }
      return parseError(response.body) ??
          'Не удалось добавить локацию (${response.statusCode})';
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
      final uri = Uri.parse('$baseUrl/locations/$locationId/upload-plan');
      final request =
          http.MultipartRequest('POST', uri)
            ..headers['Authorization'] = 'Bearer $token'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                fileBytes,
                filename: fileName ?? 'plan',
                contentType: MediaType.parse(mimeType),
              ),
            );
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200 || response.statusCode == 201) {
        final newUrl =
            (jsonDecode(response.body) as Map<String, dynamic>)['image_url']
                as String?;
        final idx = locations.indexWhere((l) => l.id == locationId);
        if (idx >= 0 && newUrl != null) {
          locations[idx] = LocationModel(
            id: locations[idx].id,
            name: locations[idx].name,
            imageUrl: newUrl,
            pushNotificationsEnabled: locations[idx].pushNotificationsEnabled,
            telegramNotificationsEnabled:
                locations[idx].telegramNotificationsEnabled,
          );
        }
        return null;
      }
      return parseError(response.body) ?? 'Не удалось загрузить план';
    } catch (e) {
      return 'Ошибка загрузки файла: $e';
    }
  }

  Future<String?> renameLocation({
    required int locationId,
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return 'Введите название локации';
    final r = await patch('/locations/$locationId', {'name': cleanName});
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Редактирование локации недоступно на сервере (${r.statusCode})';
    }
    return null;
  }

  Future<String?> deleteLocation(int locationId) async {
    final r = await delete('/locations/$locationId');
    if (r.statusCode != 200 && r.statusCode != 204) {
      return parseError(r.body) ??
          'Удаление локации недоступно на сервере (${r.statusCode})';
    }
    return null;
  }

  /// PATCH /notifications/location-preferences/{location_id}
  /// Обновляет push и/или telegram уведомления локации только для текущего пользователя.
  /// Другие пользователи этой локации продолжают получать свои уведомления независимо.
  /// Обновляет поля [pushNotificationsEnabled] и [telegramNotificationsEnabled]
  /// в локальном кеше из ответа сервера.
  Future<String?> updateLocationNotificationPreferences({
    required int locationId,
    required bool pushNotificationsEnabled,
    required bool telegramNotificationsEnabled,
  }) async {
    final r = await patch(
      '/notifications/location-preferences/$locationId',
      {
        'push_notifications_enabled': pushNotificationsEnabled,
        'telegram_notifications_enabled': telegramNotificationsEnabled,
      },
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Не удалось обновить настройки уведомлений (${r.statusCode})';
    }
    // Обновляем локальный кеш из ответа сервера
    try {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final push =
          data['push_notifications_enabled'] as bool? ??
          pushNotificationsEnabled;
      final telegram =
          data['telegram_notifications_enabled'] as bool? ??
          telegramNotificationsEnabled;
      final idx = locations.indexWhere((l) => l.id == locationId);
      if (idx >= 0) {
        locations[idx] = LocationModel(
          id: locations[idx].id,
          name: locations[idx].name,
          imageUrl: locations[idx].imageUrl,
          pushNotificationsEnabled: push,
          telegramNotificationsEnabled: telegram,
        );
      }
    } catch (_) {
      // Если парсинг ответа не удался — применяем переданные значения
      final idx = locations.indexWhere((l) => l.id == locationId);
      if (idx >= 0) {
        locations[idx] = LocationModel(
          id: locations[idx].id,
          name: locations[idx].name,
          imageUrl: locations[idx].imageUrl,
          pushNotificationsEnabled: pushNotificationsEnabled,
          telegramNotificationsEnabled: telegramNotificationsEnabled,
        );
      }
    }
    return null;
  }

  // ── Отчёты: полные (телеметрия + KPI + тревоги) ──────────────────────────

  /// GET /reports/download-period/{sensor_id}
  /// Полный отчёт по одному датчику: KPI, графики, журнал тревог.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadReportByPeriod({
    required int sensorId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-period/$sensorId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(r.headers, 'sensor_${sensorId}_$period.$format'),
      error: null,
    );
  }

  /// GET /reports/download-period-location/{location_id}
  /// Полный сводный отчёт по локации.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadLocationReportByPeriod({
    required int locationId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-period-location/$locationId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(r.headers, 'location_${locationId}_$period.$format'),
      error: null,
    );
  }

  /// GET /reports/download-period-control-unit/{control_unit_id}
  /// Полный отчёт по ЦБУ и всем привязанным датчикам.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadControlUnitReportByPeriod({
    required int controlUnitId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-period-control-unit/$controlUnitId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(
        r.headers,
        'control_unit_${controlUnitId}_$period.$format',
      ),
      error: null,
    );
  }

  // ── Отчёты: только журнал событий ────────────────────────────────────────

  /// GET /reports/download-events-sensor/{sensor_id}
  /// Только журнал тревог по одному датчику. Форматы: pdf, xlsx.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadSensorEventsReport({
    required int sensorId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-events-sensor/$sensorId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(
        r.headers,
        'events_sensor_${sensorId}_$period.$format',
      ),
      error: null,
    );
  }

  /// GET /reports/download-events-control-unit/{control_unit_id}
  /// Только журнал тревог по ЦБУ. Форматы: pdf, xlsx.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadControlUnitEventsReport({
    required int controlUnitId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-events-control-unit/$controlUnitId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(
        r.headers,
        'events_cu_${controlUnitId}_$period.$format',
      ),
      error: null,
    );
  }

  /// GET /reports/download-events-location/{location_id}
  /// Только журнал тревог по локации. Форматы: pdf, xlsx.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadLocationAlarmsReport({
    required int locationId,
    required String period,
    required String format,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, String>{'period': period, 'format': format};
    if (period == 'custom' && startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-events-location/$locationId',
    ).replace(queryParameters: params);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    return (
      bytes: r.bodyBytes,
      fileName: _extractFileName(
        r.headers,
        'events_location_${locationId}_$period.$format',
      ),
      error: null,
    );
  }

  // ── Внутренние хелперы ────────────────────────────────────────────────────

  String? _validateReportResponse(http.Response r, String format) {
    if (r.statusCode != 200) {
      return _reportErrorMessage(r) ?? 'Ошибка сервера (${r.statusCode})';
    }
    final contentType = (r.headers['content-type'] ?? '').toLowerCase();
    final expected = switch (format) {
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pdf' => 'application/pdf',
      'csv' => 'text/csv',
      _ => '',
    };
    if (expected.isNotEmpty && !contentType.contains(expected)) {
      final serverMessage = _reportErrorMessage(r);
      return serverMessage ??
          'Сервер вернул не $format-файл (${contentType.isEmpty ? 'без Content-Type' : contentType})';
    }
    return null;
  }

  String? _reportErrorMessage(http.Response r) {
    final bodyText = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    if (bodyText.isEmpty) {
      if (r.statusCode == 403) return 'Нет доступа к этой сущности';
      if (r.statusCode == 404) return 'Сущность не найдена';
      return null;
    }
    try {
      final decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List) return detail.join('\n');
        if (detail != null) return detail.toString();
      }
    } catch (_) {}
    return bodyText;
  }

  String _extractFileName(Map<String, String> headers, String fallback) {
    final cd =
        headers['content-disposition'] ?? headers['Content-Disposition'];
    if (cd != null) {
      final matchQuoted = RegExp(r'filename\s*=\s*"([^"]+)"').firstMatch(cd);
      final matchUnquoted =
          RegExp(r'filename\s*=\s*([^;\s"]+)').firstMatch(cd);
      final match = matchQuoted ?? matchUnquoted;
      final name = match?.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return fallback;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Смена пароля текущего пользователя.
}