import 'dart:convert';
import 'dart:io'; // Работа с файловой системой на мобильном

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';     // Открытие файла сторонним приложением
import 'package:path_provider/path_provider.dart'; // Получение пути временного каталога

import '../models/sensor_model.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';

// ── Точка телеметрии ──────────────────────────────────────────────────────────

class _TelemetryPoint {
  const _TelemetryPoint({required this.temperature, required this.humidity, this.timestamp});
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
  'last_24_hours': 288,    // ~5 мин между точками за 24 ч
  'last_week':     336,    // ~30 мин между точками за 7 дней
  'last_month':    480,    // ~90 мин между точками за 30 дней
  'last_2_months': 720,
  'last_3_months': 900,
  'last_6_months': 1000,
  'last_year':     1000,
};

enum _ReportTarget { sensor, location }

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
  int? _selectedSensorId;
  int? _selectedLocationId;
  _Period _period = _kPeriods[0];
  DateTime? _startDate;
  DateTime? _endDate;
  String _format = 'xlsx';
  List<_TelemetryPoint> _chartPoints = [];
  bool _chartLoading = false;
  String? _chartError;
  bool _reportLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedSensorId =
        widget.repo.sensors.isNotEmpty ? widget.repo.sensors.first.id : null;
    _selectedLocationId =
        widget.repo.locations.isNotEmpty ? widget.repo.locations.first.id : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChart());
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
      } else {
        await _loadLocationChart(_selectedLocationId);
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
      setState(() { _chartError = 'Датчик не выбран'; _chartLoading = false; });
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
      setState(() { _chartError = 'Локация не выбрана'; _chartLoading = false; });
      return;
    }
    final sensorIds = widget.repo.sensors
        .where((s) => s.groupId == locationId)
        .map((s) => s.id)
        .toList();
    if (sensorIds.isEmpty) {
      setState(() { _chartError = 'В локации нет датчиков'; _chartLoading = false; });
      return;
    }
    final results = await Future.wait(sensorIds.map(_fetchSensorPoints));
    if (!mounted) return;
    final nonEmpty = results.where((r) => r.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      setState(() { _chartError = 'Нет данных по датчикам локации'; _chartLoading = false; });
      return;
    }
    final minLen = nonEmpty.map((r) => r.length).reduce((a, b) => a < b ? a : b);
    final averaged = List.generate(minLen, (i) {
      final avgTemp = nonEmpty.map((r) => r[i].temperature).reduce((a, b) => a + b) / nonEmpty.length;
      final avgHum  = nonEmpty.map((r) => r[i].humidity).reduce((a, b) => a + b) / nonEmpty.length;
      // Берём timestamp из первого датчика — время измерения одинаково для всех
      return _TelemetryPoint(temperature: avgTemp, humidity: avgHum, timestamp: nonEmpty.first[i].timestamp);
    });
    setState(() { _chartPoints = averaged; _chartError = null; _chartLoading = false; });
  }

  Future<List<_TelemetryPoint>> _fetchSensorPoints(int sensorId) async {
    // По спецификации единственный параметр — limit.
    // Сервер возвращает последние N измерений, отсортированных по времени.
    final limit = _kHistoryLimit[_period.apiValue] ?? 480;
    final r = await widget.repo.get('/telemetry/$sensorId/history?limit=$limit');
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
    } catch (_) { return []; }

    // Парсим все три поля вместе — индексы points и timestamps всегда в синхроне
    final result = <_TelemetryPoint>[];
    for (final raw in measurements) {
      final m    = raw as Map<String, dynamic>;
      final temp = (m['temperature'] as num?)?.toDouble();
      final hum  = (m['humidity']    as num?)?.toDouble();
      if (temp == null || hum == null) continue;
      DateTime? ts;
      try {
        final tsRaw = m['timestamp'] as String?;
        if (tsRaw != null) ts = DateTime.parse(tsRaw); // UTC → будет toLocal() в графике
      } catch (_) {}
      result.add(_TelemetryPoint(temperature: temp, humidity: hum, timestamp: ts));
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
    setState(() { isStart ? _startDate = picked : _endDate = picked; });
  }

  // ── Скачивание отчёта ─────────────────────────────────────────────────────

  Future<void> _downloadReport() async {
    if (_period.apiValue == 'custom') {
      if (_startDate == null || _endDate == null) { _snack('Выберите начальную и конечную даты'); return; }
      if (_endDate!.isBefore(_startDate!)) { _snack('Конечная дата не может быть раньше начальной'); return; }
    }
    setState(() => _reportLoading = true);
    try {
      List<int>? bytes;
      String fileName = '';
      if (_target == _ReportTarget.sensor && _selectedSensorId != null) {
        bytes = await widget.repo.downloadReportByPeriod(
          sensorId: _selectedSensorId!, period: _period.apiValue,
          format: _format, startDate: _startDate, endDate: _endDate,
        );
        fileName = 'sensor_${_selectedSensorId}_${_period.apiValue}.$_format';
      } else if (_target == _ReportTarget.location && _selectedLocationId != null) {
        bytes = await widget.repo.downloadLocationReportByPeriod(
          locationId: _selectedLocationId!, period: _period.apiValue,
          format: _format, startDate: _startDate, endDate: _endDate,
        );
        fileName = 'location_${_selectedLocationId}_${_period.apiValue}.$_format';
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) { _snack('Ошибка: сервер вернул пустой файл'); return; }
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
      case 'last_24_hours': return 'День';
      case 'last_week':     return 'Неделя';
      default:              return 'Месяц'; // месяц и длиннее — показываем дд.мм
    }
  }

  String get _targetLabel {
    if (_target == _ReportTarget.sensor) return _currentSensor?.name ?? '—';
    return widget.repo.locations
            .where((l) => l.id == _selectedLocationId)
            .firstOrNull?.name ?? '—';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sensors   = widget.repo.sensors;
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
                Row(
                  children: [
                    _ToggleTab(
                      label: 'По датчику',
                      selected: _target == _ReportTarget.sensor,
                      onTap: () {
                        setState(() { _target = _ReportTarget.sensor; _chartPoints = []; });
                        _loadChart();
                      },
                    ),
                    const SizedBox(width: 8),
                    _ToggleTab(
                      label: 'По локации',
                      selected: _target == _ReportTarget.location,
                      onTap: () {
                        setState(() { _target = _ReportTarget.location; _chartPoints = []; });
                        _loadChart();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Дропдаун датчика / локации
                if (_target == _ReportTarget.sensor && sensors.isNotEmpty)
                  _StyledDropdown<int>(
                    label: 'Датчик',
                    value: _selectedSensorId,
                    items: sensors.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedSensorId = v; _chartPoints = []; });
                      _loadChart();
                    },
                  ),

                if (_target == _ReportTarget.location && locations.isNotEmpty)
                  _StyledDropdown<int>(
                    label: 'Локация',
                    value: _selectedLocationId,
                    items: locations.map((l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedLocationId = v; _chartPoints = []; });
                      _loadChart();
                    },
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
                        setState(() { _period = p; _chartPoints = []; });
                        if (p.apiValue != 'custom') _loadChart();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.of(context).yellowBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? AppColors.of(context).accent.withOpacity(0.7) : AppColors.of(context).border,
                          ),
                        ),
                        child: Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? AppColors.of(context).accent : AppColors.of(context).textDim,
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
                          label: _startDate != null ? 'С: ${_fmt(_startDate!)}' : 'Начало',
                          onTap: () => _pickDate(isStart: true),
                          active: _startDate != null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DateButton(
                          label: _endDate != null ? 'По: ${_fmt(_endDate!)}' : 'Конец',
                          onTap: () => _pickDate(isStart: false),
                          active: _endDate != null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: (_startDate != null && _endDate != null) ? _loadChart : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    if (_target == _ReportTarget.location &&
                        !_chartLoading &&
                        _chartPoints.isNotEmpty)
                      Text(
                        'Среднее по локации',
                        style: TextStyle(fontSize: 10, color: AppColors.of(context).textDim),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Температура
                _ChartBlock(
                  label: 'Температура',
                  unit: '°C',
                  color: AppColors.of(context).accent,
                  points: _chartPoints.map((p) => p.temperature).toList(),
                  timestamps: _chartPoints.map((p) => p.timestamp).whereType<DateTime>().toList(),
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
                  timestamps: _chartPoints.map((p) => p.timestamp).whereType<DateTime>().toList(),
                  period: _chartPeriod,
                  loading: _chartLoading,
                  error: _chartError,
                ),
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

                // Формат
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
                ),

                const SizedBox(height: 12),

                // Сводка
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.of(context).border),
                  ),
                  child: Text(
                    () {
                      final periodStr = _period.apiValue == 'custom' &&
                              _startDate != null && _endDate != null
                          ? '${_fmt(_startDate!)} — ${_fmt(_endDate!)}'
                          : _period.label;
                      return '$_targetLabel  ·  $periodStr  ·  ${_format.toUpperCase()}';
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
                        border: Border.all(color: AppColors.of(context).accent.withOpacity(0.6)),
                      ),
                      alignment: Alignment.center,
                      child: _reportLoading
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.of(context).accent),
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

/// Карточка-секция с общим фоном и бордером
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: child,
    );
  }
}

/// Подзаголовок секции
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).textDim,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Таб-переключатель (датчик / локация)
class _ToggleTab extends StatelessWidget {
  const _ToggleTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).cyan.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.of(context).cyan.withOpacity(0.6) : AppColors.of(context).border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? AppColors.of(context).cyan : AppColors.of(context).textDim,
          ),
        ),
      ),
    );
  }
}

/// Стилизованный дропдаун
class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(color: c.textMain, fontSize: 13),
      iconEnabledColor: c.textDim,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textDim, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: c.cyan),
        ),
        filled: true,
        fillColor: c.card2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Кнопка выбора даты
class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap, required this.active});
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.of(context).border.withOpacity(0.8) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.of(context).cyan.withOpacity(0.4) : AppColors.of(context).border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? AppColors.of(context).cyan : AppColors.of(context).textDim,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Кнопка выбора формата (xlsx / pdf)
class _FormatButton extends StatelessWidget {
  const _FormatButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).border : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.of(context).cyan.withOpacity(0.5) : AppColors.of(context).border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.of(context).cyan : AppColors.of(context).textDim,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Блок графика с заголовком и статистикой
class _ChartBlock extends StatelessWidget {
  const _ChartBlock({
    required this.label,
    required this.unit,
    required this.color,
    required this.points,
    required this.loading,
    this.timestamps,
    this.period = 'День',
    this.error,
  });
  final String label;
  final String unit;
  final Color color;
  final List<double> points;
  final bool loading;
  final List<DateTime>? timestamps;
  final String period;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок с цветной полоской
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (loading)
          SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.of(context).cyan, strokeWidth: 2),
            ),
          )
        else if (error != null)
          SizedBox(
            height: 70,
            child: Center(
              child: Text(
                error!,
                style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (points.isEmpty)
          SizedBox(
            height: 70,
            child: Center(
              child: Text(
                'Нет данных за выбранный период',
                style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12),
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 110,
            child: LineChartWidget(
                points: points,
                color: color,
                timestamps: timestamps,
                period: period,
              ),
          ),
          const SizedBox(height: 8),
          // Статистика
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.of(context).card2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  label: 'Мин',
                  value: '${points.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).cyan,
                ),
                _Divider(),
                _StatCell(
                  label: 'Среднее',
                  value: '${(points.reduce((a, b) => a + b) / points.length).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).textMain,
                ),
                _Divider(),
                _StatCell(
                  label: 'Макс',
                  value: '${points.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).accent,
                ),
                _Divider(),
                _StatCell(
                  label: 'Точек',
                  value: '${points.length}',
                  color: AppColors.of(context).textDim,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: AppColors.of(context).textDim, letterSpacing: 0.4)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppColors.of(context).border);
  }
}