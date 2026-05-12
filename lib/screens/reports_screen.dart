import 'dart:convert';
import 'dart:io'; // Работа с файловой системой на мобильном

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart'; // Открытие файла сторонним приложением
import 'package:path_provider/path_provider.dart'; // Получение пути временного каталога

import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';

// ── Точка телеметрии ──────────────────────────────────────────────────────────

part 'reports/report_filters.dart';
part 'reports/report_form_widgets.dart';
part 'reports/report_chart_widgets.dart';

class _TelemetryPoint {
  const _TelemetryPoint({
    required this.temperature,
    required this.humidity,
    this.timestamp,
  });
  final double temperature;
  final double humidity;
  final DateTime? timestamp;
}

// ── Период ────────────────────────────────────────────────────────────────────

class _Period {
  const _Period(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

const List<_Period> _kPeriods = [
  _Period('24 часа', 'last_24_hours'),
  _Period('Неделя', 'last_week'),
  _Period('Месяц', 'last_month'),
  _Period('2 месяца', 'last_2_months'),
  _Period('3 месяца', 'last_3_months'),
  _Period('6 месяцев', 'last_6_months'),
  _Period('Год', 'last_year'),
  _Period('Произвольный', 'custom'),
];

// Количество точек для каждого периода.
// API принимает только limit — сервер сам выбирает последние N записей.
// Чем длиннее период — тем больше точек запрашиваем.
const Map<String, int> _kHistoryLimit = {
  'last_24_hours': 288, // ~5 мин между точками за 24 ч
  'last_week': 336, // ~30 мин между точками за 7 дней
  'last_month': 480, // ~90 мин между точками за 30 дней
  'last_2_months': 720,
  'last_3_months': 900,
  'last_6_months': 1000,
  'last_year': 1000,
};

enum _ReportTarget { sensor, location, controlUnit, locationAlarms }

/// Отчёты и превью: история через `GET .../telemetry/{id}/history?limit=...` (см. [_fetchSensorPoints]),
/// файл — `downloadReportByPeriod` / `downloadLocationReportByPeriod`. На мобильном файл сохраняется
/// во временный каталог через `path_provider` и открывается через `open_file`.
///
/// Режим «локация»: для каждого датчика группы запрашивается история, затем покомпонентное усреднение
/// по минимальной длине рядов ([_loadLocationChart]) — упрощённая агрегация для дипломного прототипа.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repo});

  final AppRepository repo;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportTarget _target = _ReportTarget.sensor;

  // ── Выбранные ID ───────────────────────────────────────────────────────────
  int? _selectedSensorId; // для режима sensor
  int?
  _selectedLocationId; // для режимов location / locationAlarms / фильтр sensor+CU
  int? _selectedControlUnitId; // для режима controlUnit / фильтр sensor

  // ── Поиск / фильтр ─────────────────────────────────────────────────────────
  // Общий поиск по компаниям (используется во всех режимах для фильтра locationId)
  final TextEditingController _locationSearchController =
      TextEditingController();
  String _locationSearchQuery = '';

  // Для датчиков: дополнительный фильтр по ЦБУ внутри выбранной компании
  // null = показывать все датчики компании
  int? _filterControlUnitId;

  // ── Период / формат ─────────────────────────────────────────────────────────
  _Period _period = _kPeriods[0];
  DateTime? _startDate;
  DateTime? _endDate;
  String _format = 'xlsx';

  // ── График ──────────────────────────────────────────────────────────────────
  List<_TelemetryPoint> _chartPoints = [];
  bool _chartLoading = false;
  String? _chartError;
  bool _reportLoading = false;

  // ── Геттеры отфильтрованных списков ────────────────────────────────────────

  /// Локации, отфильтрованные по строке поиска
  List<LocationModel> get _filteredLocations {
    final q = _locationSearchQuery;
    if (q.isEmpty) return widget.repo.locations;
    return widget.repo.locations
        .where((l) => l.name.toLowerCase().contains(q))
        .toList();
  }

  /// ЦБУ текущей выбранной компании (для фильтра датчиков и режима ЦБУ)
  List<Map<String, dynamic>> get _locationControlUnits {
    if (_selectedLocationId == null) return widget.repo.controlUnits;
    return widget.repo.controlUnits
        .where((u) => (u['group_id'] as num?)?.toInt() == _selectedLocationId)
        .toList();
  }

  /// Датчики выбранной компании, дополнительно отфильтрованные по ЦБУ
  List<SensorModel> get _filteredSensors {
    var list = widget.repo.sensors
        .where(
          (s) =>
              _selectedLocationId == null || s.groupId == _selectedLocationId,
        )
        .toList();
    if (_filterControlUnitId != null) {
      list = list
          .where((s) => s.controlUnitId == _filterControlUnitId)
          .toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    // Инициализируем выбор первыми значениями из списков
    _selectedLocationId = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;
    _selectedControlUnitId = widget.repo.controlUnits.isNotEmpty
        ? (widget.repo.controlUnits.first['id'] as num?)?.toInt()
        : null;
    // Датчик — первый в текущей компании
    final initSensors = _selectedLocationId == null
        ? widget.repo.sensors
        : widget.repo.sensors
              .where((s) => s.groupId == _selectedLocationId)
              .toList();
    _selectedSensorId = initSensors.isNotEmpty ? initSensors.first.id : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChart());
  }

  @override
  void dispose() {
    _locationSearchController.dispose();
    super.dispose();
  }

  /// При смене компании — сбрасываем зависимые выборы и перезагружаем
  void _onLocationChanged(int? locationId) {
    final cus = widget.repo.controlUnits
        .where((u) => (u['group_id'] as num?)?.toInt() == locationId)
        .toList();
    final newCuId = cus.isNotEmpty ? (cus.first['id'] as num?)?.toInt() : null;
    final sens = widget.repo.sensors
        .where((s) => s.groupId == locationId)
        .toList();
    final newSensorId = sens.isNotEmpty ? sens.first.id : null;
    setState(() {
      _selectedLocationId = locationId;
      _selectedControlUnitId = newCuId;
      _filterControlUnitId = null; // сбрасываем фильтр по ЦБУ
      _selectedSensorId = newSensorId;
      _chartPoints = [];
    });
    _loadChart();
  }

  /// При смене фильтра ЦБУ для датчиков — выбираем первый подходящий датчик
  void _onFilterCuChanged(int? cuId) {
    final sens = widget.repo.sensors
        .where(
          (s) =>
              s.groupId == _selectedLocationId &&
              (cuId == null || s.controlUnitId == cuId),
        )
        .toList();
    setState(() {
      _filterControlUnitId = cuId;
      _selectedSensorId = sens.isNotEmpty ? sens.first.id : null;
      _chartPoints = [];
    });
    _loadChart();
  }

  // ── Загрузка графика ──────────────────────────────────────────────────────

  Future<void> _loadChart() async {
    setState(() {
      _chartLoading = true;
      _chartError = null;
      _chartPoints = [];
    });
    try {
      if (_target == _ReportTarget.sensor) {
        await _loadSensorChart(_selectedSensorId);
      } else if (_target == _ReportTarget.location) {
        await _loadLocationChart(_selectedLocationId);
      } else if (_target == _ReportTarget.controlUnit) {
        await _loadControlUnitChart(_selectedControlUnitId);
      } else {
        // locationAlarms — нет графика телеметрии, просто сброс
        setState(() {
          _chartPoints = [];
          _chartLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chartError = 'Ошибка загрузки: $e';
          _chartLoading = false;
        });
      }
    }
  }

  Future<void> _loadSensorChart(int? sensorId) async {
    if (sensorId == null) {
      setState(() {
        _chartError = 'Датчик не выбран';
        _chartLoading = false;
      });
      return;
    }
    final points = await _fetchSensorPoints(sensorId);
    if (!mounted) return;
    setState(() {
      _chartPoints = points;
      _chartError = points.isEmpty ? 'Нет данных за выбранный период' : null;
      _chartLoading = false;
    });
  }

  Future<void> _loadLocationChart(int? locationId) async {
    if (locationId == null) {
      setState(() {
        _chartError = 'Локация не выбрана';
        _chartLoading = false;
      });
      return;
    }
    final sensorIds = widget.repo.sensors
        .where((s) => s.groupId == locationId)
        .map((s) => s.id)
        .toList();
    if (sensorIds.isEmpty) {
      setState(() {
        _chartError = 'В локации нет датчиков';
        _chartLoading = false;
      });
      return;
    }
    final results = await Future.wait(sensorIds.map(_fetchSensorPoints));
    if (!mounted) return;
    final nonEmpty = results.where((r) => r.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      setState(() {
        _chartError = 'Нет данных по датчикам локации';
        _chartLoading = false;
      });
      return;
    }
    final minLen = nonEmpty
        .map((r) => r.length)
        .reduce((a, b) => a < b ? a : b);
    final averaged = List.generate(minLen, (i) {
      final avgTemp =
          nonEmpty.map((r) => r[i].temperature).reduce((a, b) => a + b) /
          nonEmpty.length;
      final avgHum =
          nonEmpty.map((r) => r[i].humidity).reduce((a, b) => a + b) /
          nonEmpty.length;
      // Берём timestamp из первого датчика — время измерения одинаково для всех
      return _TelemetryPoint(
        temperature: avgTemp,
        humidity: avgHum,
        timestamp: nonEmpty.first[i].timestamp,
      );
    });
    setState(() {
      _chartPoints = averaged;
      _chartError = null;
      _chartLoading = false;
    });
  }

  Future<void> _loadControlUnitChart(int? controlUnitId) async {
    if (controlUnitId == null) {
      setState(() {
        _chartError = 'Блок управления не выбран';
        _chartLoading = false;
      });
      return;
    }
    // Собираем все датчики этого ЦБУ
    final sensorIds = widget.repo.sensors
        .where((s) => s.controlUnitId == controlUnitId)
        .map((s) => s.id)
        .toList();
    if (sensorIds.isEmpty) {
      setState(() {
        _chartError = 'К блоку не привязаны датчики';
        _chartLoading = false;
      });
      return;
    }
    final results = await Future.wait(sensorIds.map(_fetchSensorPoints));
    if (!mounted) return;
    final nonEmpty = results.where((r) => r.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      setState(() {
        _chartError = 'Нет данных по датчикам блока';
        _chartLoading = false;
      });
      return;
    }
    final minLen = nonEmpty
        .map((r) => r.length)
        .reduce((a, b) => a < b ? a : b);
    final averaged = List.generate(minLen, (i) {
      final avgTemp =
          nonEmpty.map((r) => r[i].temperature).reduce((a, b) => a + b) /
          nonEmpty.length;
      final avgHum =
          nonEmpty.map((r) => r[i].humidity).reduce((a, b) => a + b) /
          nonEmpty.length;
      return _TelemetryPoint(
        temperature: avgTemp,
        humidity: avgHum,
        timestamp: nonEmpty.first[i].timestamp,
      );
    });
    setState(() {
      _chartPoints = averaged;
      _chartError = null;
      _chartLoading = false;
    });
  }

  Future<List<_TelemetryPoint>> _fetchSensorPoints(int sensorId) async {
    // По спецификации единственный параметр — limit.
    // Сервер возвращает последние N измерений, отсортированных по времени.
    final limit = _kHistoryLimit[_period.apiValue] ?? 480;
    final r = await widget.repo.get(
      '/telemetry/$sensorId/history?limit=$limit',
    );
    if (r.statusCode != 200) return [];

    List<dynamic> measurements = [];
    try {
      final body = jsonDecode(r.body);
      if (body is List) {
        measurements = body;
      } else if (body is Map<String, dynamic>) {
        measurements = (body['measurements'] as List<dynamic>?) ?? [];
        // Если measurements пуст, но есть latest — показываем хотя бы его
        if (measurements.isEmpty && body['latest'] != null) {
          measurements = [body['latest']];
        }
      }
    } catch (_) {
      return [];
    }

    // Парсим все три поля вместе — индексы points и timestamps всегда в синхроне
    final result = <_TelemetryPoint>[];
    for (final raw in measurements) {
      final m = raw as Map<String, dynamic>;
      final temp = (m['temperature'] as num?)?.toDouble();
      final hum = (m['humidity'] as num?)?.toDouble();
      if (temp == null || hum == null) continue;
      DateTime? ts;
      try {
        final tsRaw = m['timestamp'] as String?;
        if (tsRaw != null)
          ts = DateTime.parse(tsRaw); // UTC → будет toLocal() в графике
      } catch (_) {}
      result.add(
        _TelemetryPoint(temperature: temp, humidity: hum, timestamp: ts),
      );
    }
    return result;
  }

  // ── Дата-пикер ────────────────────────────────────────────────────────────

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now().subtract(const Duration(days: 30)))
        : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: isStart ? 'Начало периода' : 'Конец периода',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.of(context).cyan,
            surface: Theme.of(context).colorScheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      isStart ? _startDate = picked : _endDate = picked;
    });
  }

  // ── Скачивание отчёта ─────────────────────────────────────────────────────

  Future<void> _downloadReport() async {
    if (_period.apiValue == 'custom') {
      if (_startDate == null || _endDate == null) {
        _snack('Выберите начальную и конечную даты');
        return;
      }
      if (_endDate!.isBefore(_startDate!)) {
        _snack('Конечная дата не может быть раньше начальной');
        return;
      }
    }
    setState(() => _reportLoading = true);
    try {
      // Все методы репозитория возвращают record ({bytes, fileName, error}).
      List<int>? bytes;
      String fileName = '';

      if (_target == _ReportTarget.sensor && _selectedSensorId != null) {
        final r = await widget.repo.downloadReportByPeriod(
          sensorId: _selectedSensorId!,
          period: _period.apiValue,
          format: _format,
          startDate: _startDate,
          endDate: _endDate,
        );
        if (r.error != null) {
          _snack(r.error!);
          return;
        }
        bytes = r.bytes;
        fileName =
            r.fileName ??
            'sensor_${_selectedSensorId}_${_period.apiValue}.$_format';
      } else if (_target == _ReportTarget.location &&
          _selectedLocationId != null) {
        final r = await widget.repo.downloadLocationReportByPeriod(
          locationId: _selectedLocationId!,
          period: _period.apiValue,
          format: _format,
          startDate: _startDate,
          endDate: _endDate,
        );
        if (r.error != null) {
          _snack(r.error!);
          return;
        }
        bytes = r.bytes;
        fileName =
            r.fileName ??
            'location_${_selectedLocationId}_${_period.apiValue}.$_format';
      } else if (_target == _ReportTarget.controlUnit &&
          _selectedControlUnitId != null) {
        final r = await widget.repo.downloadControlUnitReportByPeriod(
          controlUnitId: _selectedControlUnitId!,
          period: _period.apiValue,
          format: _format,
          startDate: _startDate,
          endDate: _endDate,
        );
        if (r.error != null) {
          _snack(r.error!);
          return;
        }
        bytes = r.bytes;
        fileName =
            r.fileName ??
            'control_unit_${_selectedControlUnitId}_${_period.apiValue}.$_format';
      } else if (_target == _ReportTarget.locationAlarms &&
          _selectedLocationId != null) {
        final r = await widget.repo.downloadLocationAlarmsReport(
          locationId: _selectedLocationId!,
          period: _period.apiValue,
          format: _format,
          startDate: _startDate,
          endDate: _endDate,
        );
        if (r.error != null) {
          _snack(r.error!);
          return;
        }
        bytes = r.bytes;
        fileName =
            r.fileName ??
            'alarms_location_${_selectedLocationId}_${_period.apiValue}.$_format';
      }

      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _snack('Ошибка: сервер вернул пустой файл');
        return;
      }
      await _saveAndOpen(bytes, fileName);
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  Future<void> _saveAndOpen(List<int> bytes, String fileName) async {
    try {
      // Сохраняем файл во временный каталог приложения и открываем его
      // сторонним приложением (просмотрщик PDF, Excel, и т.д.)
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        _snack('Не удалось открыть файл: ${result.message}');
      } else {
        _snack('Файл сохранён: $fileName');
      }
    } catch (e) {
      if (mounted) _snack('Ошибка сохранения: $e');
    }
  }

  // ── Вспомогательные ──────────────────────────────────────────────────────

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  SensorModel? get _currentSensor =>
      widget.repo.sensors.where((s) => s.id == _selectedSensorId).firstOrNull;

  /// Переводит apiValue → строку периода для LineChartWidget (формат меток оси X)
  String get _chartPeriod {
    switch (_period.apiValue) {
      case 'last_24_hours':
        return 'День';
      case 'last_week':
        return 'Неделя';
      default:
        return 'Месяц'; // месяц и длиннее — показываем дд.мм
    }
  }

  String get _targetLabel {
    if (_target == _ReportTarget.sensor) return _currentSensor?.name ?? '—';
    if (_target == _ReportTarget.controlUnit) {
      final unit = widget.repo.controlUnits
          .where((u) => (u['id'] as num?)?.toInt() == _selectedControlUnitId)
          .firstOrNull;
      return unit?['name'] as String? ?? '—';
    }
    // location и locationAlarms — показываем название локации
    return widget.repo.locations
            .where((l) => l.id == _selectedLocationId)
            .firstOrNull
            ?.name ??
        '—';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sensors = widget.repo.sensors;
    final locations = widget.repo.locations;

    return Container(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          // ── Заголовок ────────────────────────────────────────────────────────
          Text(
            'Аналитика и архив',
            style: TextStyle(
              color: c.textMain,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 16),

          // ── Переключатель режима ─────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Источник данных'),
                const SizedBox(height: 10),

                // Табы режима
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ToggleTab(
                      label: 'По датчику',
                      selected: _target == _ReportTarget.sensor,
                      onTap: () {
                        setState(() {
                          _target = _ReportTarget.sensor;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                    _ToggleTab(
                      label: 'По локации',
                      selected: _target == _ReportTarget.location,
                      onTap: () {
                        setState(() {
                          _target = _ReportTarget.location;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                    _ToggleTab(
                      label: 'По ЦБУ',
                      selected: _target == _ReportTarget.controlUnit,
                      onTap: () {
                        setState(() {
                          _target = _ReportTarget.controlUnit;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                    _ToggleTab(
                      label: 'Уведомления',
                      selected: _target == _ReportTarget.locationAlarms,
                      onTap: () {
                        setState(() {
                          _target = _ReportTarget.locationAlarms;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Шаг 1 для всех режимов: выбор компании (с поиском) ──────────
                _CompanyFilterBlock(
                  searchController: _locationSearchController,
                  searchQuery: _locationSearchQuery,
                  filteredLocations: _filteredLocations,
                  selectedLocationId: _selectedLocationId,
                  labelSuffix: _target == _ReportTarget.locationAlarms
                      ? ' (уведомления)'
                      : '',
                  onSearchChanged: (v) => setState(
                    () => _locationSearchQuery = v.trim().toLowerCase(),
                  ),
                  onSearchCleared: () {
                    _locationSearchController.clear();
                    setState(() => _locationSearchQuery = '');
                  },
                  onLocationChanged: _onLocationChanged,
                ),

                // ── Шаг 2а: режим «По датчику» — фильтр ЦБУ → датчик ─────────
                if (_target == _ReportTarget.sensor) ...[
                  const SizedBox(height: 10),
                  // Суб-фильтр по ЦБУ (необязательный)
                  _StyledDropdown<int?>(
                    label: 'Фильтр по ЦБУ (необязательно)',
                    value: _filterControlUnitId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'Все ЦБУ компании',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._locationControlUnits.map((u) {
                        final id = (u['id'] as num?)?.toInt() ?? 0;
                        final name = u['name'] as String? ?? 'ЦБУ #$id';
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: _onFilterCuChanged,
                  ),
                  const SizedBox(height: 10),
                  // Итоговый список датчиков после фильтрации
                  if (_filteredSensors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Нет датчиков по выбранным фильтрам',
                        style: TextStyle(color: c.textDim, fontSize: 12),
                      ),
                    )
                  else
                    _StyledDropdown<int>(
                      label: 'Датчик',
                      value:
                          _filteredSensors.any((s) => s.id == _selectedSensorId)
                          ? _selectedSensorId
                          : _filteredSensors.first.id,
                      items: _filteredSensors
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedSensorId = v;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                ],

                // ── Шаг 2б: режим «По ЦБУ» — список ЦБУ компании ───────────
                if (_target == _ReportTarget.controlUnit) ...[
                  const SizedBox(height: 10),
                  if (_locationControlUnits.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'В выбранной компании нет блоков управления',
                        style: TextStyle(color: c.textDim, fontSize: 12),
                      ),
                    )
                  else
                    _StyledDropdown<int>(
                      label: 'Блок управления',
                      value:
                          _locationControlUnits.any(
                            (u) =>
                                (u['id'] as num?)?.toInt() ==
                                _selectedControlUnitId,
                          )
                          ? _selectedControlUnitId
                          : (_locationControlUnits.first['id'] as num?)
                                ?.toInt(),
                      items: _locationControlUnits.map((u) {
                        final id = (u['id'] as num?)?.toInt() ?? 0;
                        final name = u['name'] as String? ?? 'ЦБУ #$id';
                        return DropdownMenuItem(
                          value: id,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedControlUnitId = v;
                          _chartPoints = [];
                        });
                        _loadChart();
                      },
                    ),
                ],

                // режимы «По локации» и «Уведомления» — дополнительных шагов нет
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Период ───────────────────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Период'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _kPeriods.map((p) {
                    final selected = _period == p;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _period = p;
                          _chartPoints = [];
                        });
                        if (p.apiValue != 'custom') _loadChart();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.of(context).yellowBg
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? AppColors.of(context).accent.withOpacity(0.7)
                                : AppColors.of(context).border,
                          ),
                        ),
                        child: Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected
                                ? AppColors.of(context).accent
                                : AppColors.of(context).textDim,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Кастомные даты
                if (_period.apiValue == 'custom') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DateButton(
                          label: _startDate != null
                              ? 'С: ${_fmt(_startDate!)}'
                              : 'Начало',
                          onTap: () => _pickDate(isStart: true),
                          active: _startDate != null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DateButton(
                          label: _endDate != null
                              ? 'По: ${_fmt(_endDate!)}'
                              : 'Конец',
                          onTap: () => _pickDate(isStart: false),
                          active: _endDate != null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: (_startDate != null && _endDate != null)
                            ? _loadChart
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: (_startDate != null && _endDate != null)
                                ? AppColors.of(context).cyan.withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (_startDate != null && _endDate != null)
                                  ? AppColors.of(context).cyan.withOpacity(0.5)
                                  : AppColors.of(context).border,
                            ),
                          ),
                          child: Text(
                            '↻',
                            style: TextStyle(
                              fontSize: 16,
                              color: (_startDate != null && _endDate != null)
                                  ? AppColors.of(context).cyan
                                  : AppColors.of(context).textDim,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Графики ──────────────────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _SectionLabel('Графики'),
                    const Spacer(),
                    if ((_target == _ReportTarget.location ||
                            _target == _ReportTarget.controlUnit) &&
                        !_chartLoading &&
                        _chartPoints.isNotEmpty)
                      Text(
                        _target == _ReportTarget.controlUnit
                            ? 'Среднее по ЦБУ'
                            : 'Среднее по локации',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.of(context).textDim,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_target == _ReportTarget.locationAlarms) ...[
                  // Для режима уведомлений — нет телеметрии, показываем подсказку
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).card2,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.of(context).border),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: AppColors.of(context).textDim,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Отчёт уведомлений содержит историю тревог\n'
                          'по всем датчикам локации за выбранный период.',
                          style: TextStyle(
                            color: AppColors.of(context).textDim,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Температура
                  _ChartBlock(
                    label: 'Температура',
                    unit: '°C',
                    color: AppColors.of(context).accent,
                    points: _chartPoints.map((p) => p.temperature).toList(),
                    timestamps: _chartPoints
                        .map((p) => p.timestamp)
                        .whereType<DateTime>()
                        .toList(),
                    period: _chartPeriod,
                    loading: _chartLoading,
                    error: _chartError,
                  ),

                  const SizedBox(height: 2),
                  Divider(height: 20, color: AppColors.of(context).border),

                  // Влажность
                  _ChartBlock(
                    label: 'Влажность',
                    unit: '%',
                    color: AppColors.of(context).cyan,
                    points: _chartPoints.map((p) => p.humidity).toList(),
                    timestamps: _chartPoints
                        .map((p) => p.timestamp)
                        .whereType<DateTime>()
                        .toList(),
                    period: _chartPeriod,
                    loading: _chartLoading,
                    error: _chartError,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Скачать отчёт ────────────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Скачать отчёт'),
                const SizedBox(height: 10),

                // Формат (скрываем для уведомлений — они всегда PDF)
                if (_format == 'xlsx' || _format == 'pdf')
                  Row(
                    children: [
                      _FormatButton(
                        label: 'Excel (XLSX)',
                        selected: _format == 'xlsx',
                        onTap: () => setState(() => _format = 'xlsx'),
                      ),
                      const SizedBox(width: 8),
                      _FormatButton(
                        label: 'PDF',
                        selected: _format == 'pdf',
                        onTap: () => setState(() => _format = 'pdf'),
                      ),
                    ],
                  )
                else
                  // Уведомления — печатаем PDF-бедж
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).cyan.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: AppColors.of(context).cyan.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          color: AppColors.of(context).cyan,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Отчёт уведомлений всегда выгружается в формате PDF',
                          style: TextStyle(
                            color: AppColors.of(context).cyan,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Сводка
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.of(context).border),
                  ),
                  child: Text(
                    () {
                      final periodStr =
                          _period.apiValue == 'custom' &&
                              _startDate != null &&
                              _endDate != null
                          ? '${_fmt(_startDate!)} — ${_fmt(_endDate!)}'
                          : _period.label;
                      final formatStr = _format.toUpperCase();
                      final typeStr = _target == _ReportTarget.locationAlarms
                          ? 'Уведомления'
                          : 'Телеметрия';
                      return '$_targetLabel  ·  $periodStr  ·  $typeStr  ·  $formatStr';
                    }(),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.of(context).textDim,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Кнопка скачать
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _reportLoading ? null : _downloadReport,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _reportLoading
                            ? AppColors.of(context).accent.withOpacity(0.5)
                            : AppColors.of(context).yellowBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.of(context).accent.withOpacity(0.6),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _reportLoading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.of(context).accent,
                              ),
                            )
                          : Text(
                              'Скачать отчёт',
                              style: TextStyle(
                                color: AppColors.of(context).accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Виджеты-компоненты
// ─────────────────────────────────────────────────────────────────────────────

/// Блок выбора компании (поиск + дропдаун). Используется во всех четырёх режимах.
