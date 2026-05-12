part of '../app_repository.dart';

extension AppRepositoryLocationsReports on AppRepository {
  Future<String?> createLocation({required String name}) async {
    // создать локацию (компанию) только именем
    try {
      // FIX: сервер ожидает multipart/form-data, а не JSON.
      // Используем MultipartRequest чтобы передать поле name как form-поле.
      final uri = Uri.parse('$baseUrl/locations/'); // POST /locations/
      final request =
          http.MultipartRequest('POST', uri) // multipart вместо JSON
            ..headers['Authorization'] =
                'Bearer $token' // JWT
            ..fields['name'] = name; // поле формы name
      final response = await http.Response.fromStream(
        // читаем поток ответа
        await request.send().timeout(_kTimeout), // отправка с таймаутом
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // создано
        // Добавляем новую локацию в локальный список сразу, без лишнего reload
        try {
          final data =
              jsonDecode(response.body) as Map<String, dynamic>; // тело ответа
          final id = (data['id'] as num?)?.toInt(); // id новой локации
          final nm =
              data['name'] as String? ?? name; // имя из ответа или запроса
          if (id != null) {
            locations.add(LocationModel(id: id, name: nm)); // дописываем в кеш
          }
        } catch (_) {} // игнорируем битый JSON
        return null; // успех
      }
      return parseError(response.body) ??
          'Не удалось добавить локацию (${response.statusCode})'; // ошибка API
    } catch (e) {
      return 'Ошибка создания локации: $e'; // сеть/таймаут
    }
  }

  Future<String?> uploadLocationPlan({
    // загрузить изображение плана для локации
    required int locationId, // id локации
    required Uint8List fileBytes, // байты файла
    required String mimeType, // MIME типа image/jpeg и т.д.
    String? fileName, // имя файла для multipart
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/locations/$locationId/upload-plan',
      ); // POST upload
      final request =
          http.MultipartRequest('POST', uri) // multipart запрос
            ..headers['Authorization'] =
                'Bearer $token' // JWT
            ..files.add(
              http.MultipartFile.fromBytes(
                // один файл в форме
                'file', // имя поля на сервере
                fileBytes, // содержимое
                filename: fileName ?? 'plan', // имя файла
                contentType: MediaType.parse(mimeType), // Content-Type части
              ),
            );
      final response = await http.Response.fromStream(
        await request.send(),
      ); // ответ
      if (response.statusCode == 200 || response.statusCode == 201) {
        // ОК
        final newUrl =
            (jsonDecode(response.body) as Map<String, dynamic>)['image_url']
                as String?; // URL картинки
        final idx = locations.indexWhere(
          (l) => l.id == locationId,
        ); // позиция локации в кеше
        if (idx >= 0 && newUrl != null) {
          locations[idx] = LocationModel(
            id: locations[idx].id,
            name: locations[idx].name,
            imageUrl: newUrl,
          ); // обновляем imageUrl
        }
        return null; // успех
      }
      return parseError(response.body) ??
          'Не удалось загрузить план'; // ошибка сервера
    } catch (e) {
      return 'Ошибка загрузки файла: $e';
    } // клиентская ошибка
  }

  Future<String?> renameLocation({
    required int locationId,
    required String name,
  }) async {
    // PATCH имени локации, если backend поддерживает endpoint
    final cleanName = name.trim(); // имя обязательно
    if (cleanName.isEmpty) return 'Введите название локации';
    final r = await patch('/locations/$locationId', {
      'name': cleanName,
    }); // ожидаемый REST endpoint для редактирования LocationGroup
    if (r.statusCode != 200 && r.statusCode != 201) {
      return parseError(r.body) ??
          'Редактирование локации недоступно на сервере (${r.statusCode})';
    }
    return null; // список обновится через loadAll
  }

  Future<String?> deleteLocation(int locationId) async {
    // DELETE локации, если backend поддерживает endpoint
    final r = await delete(
      '/locations/$locationId',
    ); // в API-документации endpoint может отсутствовать
    if (r.statusCode != 200 && r.statusCode != 204) {
      return parseError(r.body) ??
          'Удаление локации недоступно на сервере (${r.statusCode})';
    }
    return null; // список обновится через loadAll
  }

  // ── Отчёты ────────────────────────────────────────────────────────────────

  // Полный отчёт по сенсору: KPI, графики мониторинга и журнал событий.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadReportByPeriod({
    // скачать файл отчёта по одному датчику
    required int sensorId,
    required String period,
    required String format, // id, период API, xlsx/pdf
    DateTime? startDate,
    DateTime? endDate, // для custom периода
  }) async {
    final params = <String, String>{
      'period': period,
      'format': format,
    }; // query: period + format
    if (period == 'custom' && startDate != null && endDate != null) {
      // пользовательский диапазон
      params['start_date'] = _fmtDate(startDate); // yyyy-MM-dd
      params['end_date'] = _fmtDate(endDate); // yyyy-MM-dd
    }
    final uri = Uri.parse('$baseUrl/reports/download-period/$sensorId').replace(
      queryParameters: params,
    ); // download-period-* нужен для полного отчёта
    final r = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ); // GET бинарника
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    final fileName = _extractFileName(
      r.headers,
      'sensor_${sensorId}_${period}.$format',
    ); // имя из Content-Disposition или fallback
    return (bytes: r.bodyBytes, fileName: fileName, error: null); // успех
  }

  // Полный сводный отчёт по локации.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadLocationReportByPeriod({
    // отчёт по всей локации (агрегация на сервере)
    required int locationId,
    required String period,
    required String format, // id локации и параметры
    DateTime? startDate,
    DateTime? endDate, // custom диапазон
  }) async {
    final params = <String, String>{
      'period': period,
      'format': format,
    }; // query: period + format
    if (period == 'custom' && startDate != null && endDate != null) {
      // даты
      params['start_date'] = _fmtDate(startDate); // от
      params['end_date'] = _fmtDate(endDate); // до
    }
    final uri =
        Uri.parse(
          '$baseUrl/reports/download-period-location/$locationId',
        ).replace(
          queryParameters: params,
        ); // download-period-* нужен для полного отчёта
    final r = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ); // GET
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    final fileName = _extractFileName(
      r.headers,
      'location_${locationId}_${period}.$format',
    ); // имя из Content-Disposition или fallback
    return (bytes: r.bodyBytes, fileName: fileName, error: null); // успех
  }

  // Полный отчёт по центральному блоку и привязанным сенсорам.
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadControlUnitReportByPeriod({
    // отчёт по блоку управления (ЦБУ)
    required int controlUnitId,
    required String period,
    required String format, // id ЦБУ, период, формат
    DateTime? startDate,
    DateTime? endDate, // custom диапазон
  }) async {
    final params = <String, String>{
      'period': period,
      'format': format,
    }; // query: period + format
    if (period == 'custom' && startDate != null && endDate != null) {
      // пользовательский диапазон
      params['start_date'] = _fmtDate(startDate); // yyyy-MM-dd
      params['end_date'] = _fmtDate(endDate); // yyyy-MM-dd
    }
    final uri =
        Uri.parse(
          '$baseUrl/reports/download-period-control-unit/$controlUnitId',
        ).replace(
          queryParameters: params,
        ); // download-period-* нужен для полного отчёта
    final r = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ); // GET бинарника
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    final fileName = _extractFileName(
      r.headers,
      'control_unit_${controlUnitId}_${period}.$format',
    ); // имя из Content-Disposition или fallback
    return (bytes: r.bodyBytes, fileName: fileName, error: null); // успех
  }

  // FIX: endpoint download-events-location уже правильный; добавлена обработка 403 и Content-Disposition
  // format не передаём — сервер всегда отдаёт PDF для отчёта уведомлений
  Future<({List<int>? bytes, String? fileName, String? error})>
  downloadLocationAlarmsReport({
    // отчёт уведомлений по локации (всегда PDF)
    required int locationId,
    required String period, // id локации и период
    required String format, // pdf/xlsx
    DateTime? startDate,
    DateTime? endDate, // custom диапазон
  }) async {
    final params = <String, String>{
      'period': period,
      'format': format,
    }; // format не передаём — сервер всегда отдаёт PDF
    if (period == 'custom' && startDate != null && endDate != null) {
      // даты
      params['start_date'] = _fmtDate(startDate); // от
      params['end_date'] = _fmtDate(endDate); // до
    }
    final uri = Uri.parse(
      '$baseUrl/reports/download-events-location/$locationId',
    ).replace(queryParameters: params); // правильный endpoint
    final r = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ); // GET
    final err = _validateReportResponse(r, format);
    if (err != null) return (bytes: null, fileName: null, error: err);
    final fileName = _extractFileName(
      r.headers,
      'alarms_location_${locationId}_$period.$format',
    ); // имя из Content-Disposition или fallback
    return (
      bytes: r.bodyBytes,
      fileName: fileName,
      error: null,
    ); // файл или ошибка
  }

  String? _validateReportResponse(http.Response r, String format) {
    // Не сохраняем body как файл, пока не проверены HTTP status и Content-Type.
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
    // Ошибки отчётов/удаления могут прийти JSON-ом или обычным текстом.
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

  /// Извлекает имя файла из заголовка Content-Disposition ответа.
  /// Если заголовок отсутствует или не содержит filename — возвращает fallback.
  String _extractFileName(Map<String, String> headers, String fallback) {
    // имя файла из ответа сервера
    final cd =
        headers['content-disposition'] ??
        headers['Content-Disposition']; // регистронезависимый поиск
    if (cd != null) {
      // заголовок присутствует
      // Ищем filename="value" или filename=value (без кавычек).
      // Разбиваем на два отдельных RegExp чтобы избежать одинарных кавычек в raw-строке.
      final matchQuoted = RegExp(r'filename\s*=\s*"([^"]+)"').firstMatch(cd);
      final matchUnquoted = RegExp(r'filename\s*=\s*([^;\s"]+)').firstMatch(cd);
      final match = matchQuoted ?? matchUnquoted; // предпочитаем кавычки
      final name = match
          ?.group(1)
          ?.trim(); // извлекаем значение (группа 1 в обоих regex)
      if (name != null && name.isNotEmpty)
        return name; // возвращаем серверное имя
    }
    return fallback; // заголовка нет или пустой — используем fallback
  }

  String _fmtDate(DateTime d) => // формат даты для query API
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'; // yyyy-MM-dd

  /// Смена пароля текущего пользователя.
}
