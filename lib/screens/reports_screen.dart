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

const Map<String, int> _kHistoryLimit = {
  'last_24_hours': 288,
  'last_week': 336,
  'last_month': 480,
  'last_2_months': 720,
  'last_3_months': 900,
  'last_6_months': 1000,
  'last_year': 1000,
};

/// Объект отчёта: датчик / ЦБУ / локация
enum _ReportTarget { sensor, controlUnit, location }

/// Тип отчёта: полный (телеметрия + тревоги) или только журнал событий
enum _ReportKind { telemetry, events }

/// Отчёты и превью: история через `GET .../telemetry/{id}/history?limit=...`,
/// файл — `downloadReportByPeriod` / `downloadLocationReportByPeriod`. На мобильном файл сохраняется
/// во временный каталог через `path_provider` и открывается через `open_file`.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repo});

  final AppRepository repo;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportTarget _target = _ReportTarget.sensor;
  _ReportKind _kind = _ReportKind.telemetry;

  // ── Выбранные ID ───────────────────────────────────────────────────────────
  int? _selectedSensorId;
  int? _selectedLocationId;
  int? _selectedControlUnitId;

  // ── Поиск / фильтр ─────────────────────────────────────────────────────────
  final TextEditingController _locationSearchController =
      TextEditingController();
  String _locationSearchQuery = '';
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

  // ── Геттеры ────────────────────────────────────────────────────────────────

  List<LocationModel> get _filteredLocations {
    final q = _locationSearchQuery;
    if (q.isEmpty) return widget.repo.locations;
    return widget.repo.locations
        .where((l) => l.name.toLowerCase().contains(q))
        .toList();
  }

  List<Map<String, dynamic>> get _locationControlUnits {
    if (_selectedLocationId == null) return widget.repo.controlUnits;
    return widget.repo.controlUnits
        .where((u) => (u['group_id'] as num?)?.toInt() == _selectedLocationId)
        .toList();
  }

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

  /// Events-отчёт поддерживает только pdf и xlsx
  bool get _isEventsMode => _kind == _ReportKind.events;

  @override
  void initState() {
    super.initState();
    _selectedLocationId = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;
    _selectedControlUnitId = widget.repo.controlUnits.isNotEmpty
        ? (widget.repo.controlUnits.first['id'] as num?)?.toInt()
        : null;
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
      _filterControlUnitId = null;
      _selectedSensorId = newSensorId;
      _chartPoints = [];
    });
    _loadChart();
  }

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
    // В режиме events графика нет
    if (_kind == _ReportKind.events) {
      setState(() {
        _chartPoints = [];
        _chartLoading = false;
        _chartError = null;
      });
      return;
    }

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
        if (measurements.isEmpty && body['latest'] != null) {
          measurements = [body['latest']];
        }
      }
    } catch (_) {
      return [];
    }

    final result = <_TelemetryPoint>[];
    for (final raw in measurements) {
      final m = raw as Map<String, dynamic>;
      final temp = (m['temperature'] as num?)?.toDouble();
      final hum = (m['humidity'] as num?)?.toDouble();
      if (temp == null || hum == null) continue;
      DateTime? ts;
      try {
        final tsRaw = m['timestamp'] as String?;
        if (tsRaw != null) ts = DateTime.parse(tsRaw);
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
      List<int>? bytes;
      String fileName = '';

      if (_kind == _ReportKind.telemetry) {
        // ── Полные отчёты (телеметрия + тревоги) ──────────────────────────
        if (_target == _ReportTarget.sensor && _selectedSensorId != null) {
          final r = await widget.repo.downloadReportByPeriod(
            sensorId: _selectedSensorId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'sensor_${_selectedSensorId}_${_period.apiValue}.$_format';
        } else if (_target == _ReportTarget.controlUnit &&
            _selectedControlUnitId != null) {
          final r = await widget.repo.downloadControlUnitReportByPeriod(
            controlUnitId: _selectedControlUnitId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'control_unit_${_selectedControlUnitId}_${_period.apiValue}.$_format';
        } else if (_target == _ReportTarget.location &&
            _selectedLocationId != null) {
          final r = await widget.repo.downloadLocationReportByPeriod(
            locationId: _selectedLocationId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'location_${_selectedLocationId}_${_period.apiValue}.$_format';
        }
      } else {
        // ── Отчёты только по событиям ──────────────────────────────────────
        if (_target == _ReportTarget.sensor && _selectedSensorId != null) {
          final r = await widget.repo.downloadSensorEventsReport(
            sensorId: _selectedSensorId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'events_sensor_${_selectedSensorId}_${_period.apiValue}.$_format';
        } else if (_target == _ReportTarget.controlUnit &&
            _selectedControlUnitId != null) {
          final r = await widget.repo.downloadControlUnitEventsReport(
            controlUnitId: _selectedControlUnitId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'events_cu_${_selectedControlUnitId}_${_period.apiValue}.$_format';
        } else if (_target == _ReportTarget.location &&
            _selectedLocationId != null) {
          final r = await widget.repo.downloadLocationAlarmsReport(
            locationId: _selectedLocationId!,
            period: _period.apiValue,
            format: _format,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (r.error != null) { _snack(r.error!); return; }
          bytes = r.bytes;
          fileName = r.fileName ??
              'events_location_${_selectedLocationId}_${_period.apiValue}.$_format';
        }
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

  String get _chartPeriod {
    switch (_period.apiValue) {
      case 'last_24_hours':
        return 'День';
      case 'last_week':
        return 'Неделя';
      default:
        return 'Месяц';
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

          // ── Источник данных ──────────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Источник данных'),
                const SizedBox(height: 10),

                // Табы объекта
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
                  ],
                ),
                const SizedBox(height: 12),

                // Выбор компании (поиск + дропдаун)
                _CompanyFilterBlock(
                  searchController: _locationSearchController,
                  searchQuery: _locationSearchQuery,
                  filteredLocations: _filteredLocations,
                  selectedLocationId: _selectedLocationId,
                  labelSuffix: '',
                  onSearchChanged: (v) => setState(
                    () => _locationSearchQuery = v.trim().toLowerCase(),
                  ),
                  onSearchCleared: () {
                    _locationSearchController.clear();
                    setState(() => _locationSearchQuery = '');
                  },
                  onLocationChanged: _onLocationChanged,
                ),

                // Фильтр ЦБУ + датчик (режим «По датчику»)
                if (_target == _ReportTarget.sensor) ...[
                  const SizedBox(height: 10),
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

                // Список ЦБУ (режим «По ЦБУ»)
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

                const SizedBox(height: 14),

                // ── Тип отчёта ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _KindTab(
                          icon: Icons.bar_chart_rounded,
                          label: 'Телеметрия',
                          sublabel: 'KPI + графики + тревоги',
                          selected: _kind == _ReportKind.telemetry,
                          onTap: () {
                            if (_kind == _ReportKind.telemetry) return;
                            setState(() {
                              _kind = _ReportKind.telemetry;
                              if (_format == 'csv') _format = 'xlsx';
                            });
                            _loadChart();
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: _KindTab(
                          icon: Icons.notifications_outlined,
                          label: 'События',
                          sublabel: 'Журнал тревог',
                          selected: _kind == _ReportKind.events,
                          onTap: () {
                            if (_kind == _ReportKind.events) return;
                            setState(() {
                              _kind = _ReportKind.events;
                              // CSV недоступен для events-отчётов
                              if (_format == 'csv') _format = 'xlsx';
                              _chartPoints = [];
                              _chartLoading = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
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

          // ── Графики (только для телеметрии) ─────────────────────────────────
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
                        _chartPoints.isNotEmpty &&
                        _kind == _ReportKind.telemetry)
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

                if (_kind == _ReportKind.events) ...[
                  // Заглушка для режима событий
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
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
                          'Журнал событий не содержит\nграфиков телеметрии.',
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

                // Формат — CSV только для телеметрии
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
                    if (_kind == _ReportKind.telemetry) ...[
                      const SizedBox(width: 8),
                      _FormatButton(
                        label: 'CSV',
                        selected: _format == 'csv',
                        onTap: () => setState(() => _format = 'csv'),
                      ),
                    ],
                  ],
                ),

                // Подсказка для events: доступны только PDF и XLSX
                if (_kind == _ReportKind.events) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 13,
                        color: AppColors.of(context).textDim,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Журнал событий: доступны PDF и XLSX',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.of(context).textDim,
                        ),
                      ),
                    ],
                  ),
                ],

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
                      final kindStr = _kind == _ReportKind.events
                          ? 'Журнал событий'
                          : 'Телеметрия';
                      return '$_targetLabel  ·  $periodStr  ·  $kindStr  ·  $formatStr';
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

// ── Таб типа отчёта (Телеметрия / События) ───────────────────────────────────

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = selected ? c.cyan : c.textDim;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.cyan.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? c.cyan.withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(fontSize: 10, color: c.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Виджеты-компоненты
// ─────────────────────────────────────────────────────────────────────────────