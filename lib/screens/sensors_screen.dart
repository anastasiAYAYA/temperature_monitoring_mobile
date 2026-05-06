import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';

/// Каталог датчиков: история через `repo.loadHistory`, создание ЦБУ/датчика, пороги, опционально ИИ-пороги.
///
/// На защите: связь «локация → control unit → sensor», различие ролей ([UserRole]) для видимости кнопок.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  /// Период для `loadHistory` на карточках (согласован с [AppRepository.loadHistory]).
  String period = 'День';
  String search = '';

  AppScheme get c => AppColors.of(context);

  // ── Детали датчика ────────────────────────────────────────────────────────

  Future<void> _openSensorDetails(SensorModel sensor) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SensorDetailDialog(
        sensor: sensor,
        repo: widget.repo,
        onRefresh: widget.onRefresh,
      ),
    );
  }


  // ── Диалог создания датчика ───────────────────────────────────────────────

  Future<void> _showCreateControlUnitDialog() async {
    final nameCtrl         = TextEditingController();
    final serialNumberCtrl = TextEditingController();
    final devEuiCtrl       = TextEditingController();
    int? selectedLocationId =
        widget.repo.locations.isNotEmpty ? widget.repo.locations.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => _DarkDialog(
          title: 'Новый блок управления',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.accent.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: c.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Локация → Блок управления → Датчики',
                        style: TextStyle(color: c.accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              _DarkField(
                controller: nameCtrl,
                label: 'Название блока *',
                hint: 'Например: ЦБУ Склад-А',
              ),
              const SizedBox(height: 10),
              _DarkField(
                controller: serialNumberCtrl,
                label: 'Серийный номер *',
                hint: 'Например: SN-20240001-ABC',
              ),
              const SizedBox(height: 10),
              _DarkDropdown<int>(
                label: 'Локация *',
                value: selectedLocationId,
                items: widget.repo.locations
                    .map((e) => DropdownMenuItem<int>(
                          value: e.id,
                          child: Text(e.name),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => selectedLocationId = v),
              ),
              const SizedBox(height: 10),
              _DarkField(
                controller: devEuiCtrl,
                label: 'Dev EUI (LoRaWAN)',
                hint: 'A1B2C3D4E5F60708 — опционально',
              ),
            ],
          ),
          actions: [
            _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
            _DarkFilledButton(
              label: 'Создать',
              onTap: () async {
                final name         = nameCtrl.text.trim();
                final serialNumber = serialNumberCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Введите название блока')),
                  );
                  return;
                }
                if (serialNumber.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Введите серийный номер')),
                  );
                  return;
                }
                if (selectedLocationId == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Выберите локацию')),
                  );
                  return;
                }
                final devEui = devEuiCtrl.text.trim();
                final result = await widget.repo.createControlUnit(
                  name:         name,
                  locationId:   selectedLocationId!,
                  serialNumber: serialNumber,
                  devEui:       devEui.isEmpty ? null : devEui,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (result.error != null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(result.error!)),
                  );
                  return;
                }

                // Токен не показываем пользователю — он передаётся на устройство
                // через прошивку и не должен отображаться в интерфейсе.
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        Icon(Icons.check_circle, color: kGreen, size: 16),
                        const SizedBox(width: 8),
                        const Text('Блок управления успешно создан'),
                      ]),
                      backgroundColor: const Color(0xFF0D2B1F),
                    ),
                  );
                }
                await widget.onRefresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSensorDialog() async {
    final nameCtrl       = TextEditingController();
    final internalIdCtrl = TextEditingController();
    final delayCtrl      = TextEditingController(text: '0');

    int? selectedLocationId =
        widget.repo.locations.isNotEmpty ? widget.repo.locations.first.id : null;
    int? selectedControlUnitId; // null = не привязан к блоку

    final wMinTCtrl = TextEditingController();
    final wMaxTCtrl = TextEditingController();
    final aMinTCtrl = TextEditingController();
    final aMaxTCtrl = TextEditingController();
    final wMinHCtrl = TextEditingController();
    final wMaxHCtrl = TextEditingController();
    final aMinHCtrl = TextEditingController();
    final aMaxHCtrl = TextEditingController();

    bool thresholdsExpanded = false;

    // Фильтруем блоки по выбранной локации
    List<Map<String, dynamic>> _unitsForLocation(int? locId) {
      if (locId == null) return widget.repo.controlUnits;
      return widget.repo.controlUnits
          .where((u) => (u['group_id'] as num?)?.toInt() == locId)
          .toList();
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final units = _unitsForLocation(selectedLocationId);
          // Сбрасываем выбор блока если он не в текущей локации
          if (selectedControlUnitId != null &&
              !units.any((u) => (u['id'] as num?)?.toInt() == selectedControlUnitId)) {
            selectedControlUnitId = null;
          }

          return _DarkDialog(
            title: 'Новый датчик',
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Основные поля ────────────────────────────────────────
                  _DarkField(
                    controller: nameCtrl,
                    label: 'Название датчика *',
                    hint: 'Например: Датчик TH-01',
                  ),
                  const SizedBox(height: 10),

                  // Локация
                  _DarkDropdown<int>(
                    label: 'Локация *',
                    value: selectedLocationId,
                    items: widget.repo.locations
                        .map((e) => DropdownMenuItem<int>(
                              value: e.id,
                              child: Text(e.name),
                            ))
                        .toList(),
                    onChanged: (v) => setSt(() {
                      selectedLocationId    = v;
                      selectedControlUnitId = null;
                    }),
                  ),
                  const SizedBox(height: 10),

                  // Блок управления
                  _DarkDropdown<int>(
                    label: 'Блок управления',
                    value: selectedControlUnitId,
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('— Без блока —'),
                      ),
                      ...units.map((u) => DropdownMenuItem<int>(
                            value: (u['id'] as num?)?.toInt(),
                            child: Text(u['name'] as String? ?? '—'),
                          )),
                    ],
                    onChanged: (v) => setSt(() => selectedControlUnitId = v),
                  ),
                  const SizedBox(height: 10),

                  // Internal ID
                  _DarkField(
                    controller: internalIdCtrl,
                    label: 'Внутренний ID (Internal ID)',
                    hint: 'MAC, DevEUI или CU1_SENSOR3',
                  ),
                  const SizedBox(height: 10),

                  // Задержка тревоги
                  _DarkField(
                    controller: delayCtrl,
                    label: 'Задержка тревоги (секунды)',
                    hint: '0',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),

                  // ── Пороговые значения (сворачиваемые) ───────────────────
                  GestureDetector(
                    onTap: () => setSt(() => thresholdsExpanded = !thresholdsExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.card2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Пороговые значения',
                              style: TextStyle(
                                color: c.textMain,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            thresholdsExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: c.textDim,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!thresholdsExpanded) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        aMinTCtrl.text.isEmpty && aMaxTCtrl.text.isEmpty
                            ? 'Пороги не заданы'
                            : 'Т: ${aMinTCtrl.text}–${aMaxTCtrl.text} °C  •  '
                              'Вл: ${aMinHCtrl.text}–${aMaxHCtrl.text} %',
                        style: TextStyle(fontSize: 11, color: c.textDim),
                      ),
                    ),
                  ],
                  if (thresholdsExpanded) ...[
                    const SizedBox(height: 12),
                    _SectionLabel(text: 'ТЕМПЕРАТУРА (°C)'),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Внимание', color: kOrange,
                      minCtrl: wMinTCtrl, maxCtrl: wMaxTCtrl, signed: true,
                    ),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Тревога', color: kRed,
                      minCtrl: aMinTCtrl, maxCtrl: aMaxTCtrl, signed: true,
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel(text: 'ВЛАЖНОСТЬ (%)'),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Внимание', color: kOrange,
                      minCtrl: wMinHCtrl, maxCtrl: wMaxHCtrl,
                    ),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Тревога', color: kRed,
                      minCtrl: aMinHCtrl, maxCtrl: aMaxHCtrl,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kCyan.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kCyan.withOpacity(0.2)),
                      ),
                      child: const Text(
                        'Правило: Тревога min ≤ Внимание min < Внимание max ≤ Тревога max',
                        style: TextStyle(fontSize: 11, color: kCyan),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
              _DarkFilledButton(
                label: 'Создать',
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Введите название датчика')),
                    );
                    return;
                  }
                  if (selectedLocationId == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Выберите локацию')),
                    );
                    return;
                  }

                  final wMinT = double.tryParse(wMinTCtrl.text.trim());
                  final wMaxT = double.tryParse(wMaxTCtrl.text.trim());
                  final aMinT = double.tryParse(aMinTCtrl.text.trim());
                  final aMaxT = double.tryParse(aMaxTCtrl.text.trim());
                  final wMinH = double.tryParse(wMinHCtrl.text.trim());
                  final wMaxH = double.tryParse(wMaxHCtrl.text.trim());
                  final aMinH = double.tryParse(aMinHCtrl.text.trim());
                  final aMaxH = double.tryParse(aMaxHCtrl.text.trim());
                  final delay = int.tryParse(delayCtrl.text.trim()) ?? 0;

                  // Проверяем порядок порогов если заданы
                  if (aMinT != null && wMinT != null && wMaxT != null && aMaxT != null) {
                    if (!(aMinT <= wMinT && wMinT < wMaxT && wMaxT <= aMaxT)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text(
                          'Нарушен порядок порогов: '
                          'Тревога min ≤ Внимание min < Внимание max ≤ Тревога max',
                        )),
                      );
                      setSt(() => thresholdsExpanded = true);
                      return;
                    }
                  }

                  final internalId = internalIdCtrl.text.trim();

                  final err = await widget.repo.createSensor(
                    name:              name,
                    locationId:        selectedLocationId!,
                    controlUnitId:     selectedControlUnitId,
                    internalId:        internalId.isEmpty ? null : internalId,
                    alarmDelaySeconds: delay,
                    warningMinTemp:    wMinT,
                    warningMaxTemp:    wMaxT,
                    alarmMinTemp:      aMinT,
                    alarmMaxTemp:      aMaxT,
                    warningMinHum:     wMinH,
                    warningMaxHum:     wMaxH,
                    alarmMinHum:       aMinH,
                    alarmMaxHum:       aMaxH,
                  );

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(err ?? 'Датчик создан')),
                  );
                  if (err == null) await widget.onRefresh();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canManage = widget.repo.role == UserRole.admin ||
        widget.repo.role == UserRole.editor;

    final grouped = <LocationModel, List<SensorModel>>{};
    for (final location in widget.repo.locations) {
      final items =
          widget.repo.sensors.where((e) => e.groupId == location.id).toList();
      final hasUnits = widget.repo.controlUnits
          .any((u) => (u['group_id'] as num?)?.toInt() == location.id);
      if (items.isNotEmpty || hasUnits) grouped[location] = items;
      // Локации без датчиков и без блоков управления — не добавляем (не показываем)
    }

    final query = search.trim().toLowerCase();
    final filteredEntries = grouped.entries.where((entry) {
      if (query.isEmpty) return true;
      final locUnits = widget.repo.controlUnits
          .where((u) => (u['group_id'] as num?)?.toInt() == entry.key.id);
      return entry.key.name.toLowerCase().contains(query) ||
          entry.value.any((s) => s.name.toLowerCase().contains(query)) ||
          locUnits.any((u) => (u['name'] as String? ?? '').toLowerCase().contains(query));
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Поиск + кнопка добавить ──────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(color: c.textMain, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Поиск по локациям и датчикам',
                  hintStyle: TextStyle(color: c.textDim, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: c.textDim, size: 20),
                  filled: true,
                  fillColor: c.card,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: kCyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 8),
              // Кнопка добавить блок управления (только admin)
              if (widget.repo.role == UserRole.admin)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: _showCreateControlUnitDialog,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.accent.withOpacity(0.35)),
                      ),
                      child: Icon(Icons.router_outlined, color: c.accent, size: 20),
                    ),
                  ),
                ),
              // Кнопка добавить датчик (только admin)
              if (widget.repo.role == UserRole.admin)
                GestureDetector(
                  onTap: _showCreateSensorDialog,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kCyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kCyan.withOpacity(0.35)),
                    ),
                    child: const Icon(Icons.add, color: kCyan, size: 20),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── Список ──────────────────────────────────────────────────────
        if (filteredEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'Нет датчиков',
                style: TextStyle(color: c.textDim, fontSize: 14),
              ),
            ),
          )
        else
          ...filteredEntries.map(
            (entry) => _LocationGroup(
              location: entry.key,
              sensors: entry.value,
              controlUnits: widget.repo.controlUnits
                  .where((u) => (u['group_id'] as num?)?.toInt() == entry.key.id)
                  .toList(),
              onSensorTap: _openSensorDetails,
              repo: widget.repo,
            ),
          ),
      ],
    );
  }
}


// ── Диалог деталей датчика (отдельный StatefulWidget) ────────────────────────

class _SensorDetailDialog extends StatefulWidget {
  const _SensorDetailDialog({
    required this.sensor,
    required this.repo,
    required this.onRefresh,
  });
  final SensorModel sensor;
  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<_SensorDetailDialog> createState() => _SensorDetailDialogState();
}

class _SensorDetailDialogState extends State<_SensorDetailDialog> {
  bool _loading = true;
  bool _showTemperature = true;
  String _period = 'День';
  List<double> _tempPoints = [];
  List<double> _humPoints  = [];

  // ── Live-данные от /telemetry/{id}/latest ────────────────────────────────
  double? _liveTemp;
  double? _liveHum;
  DateTime? _liveTs;
  bool _liveLoading = true;
  Timer? _liveTimer;
  Timer? _historyTimer;

  late final TextEditingController _wMinTCtrl;
  late final TextEditingController _wMaxTCtrl;
  late final TextEditingController _aMinTCtrl;
  late final TextEditingController _aMaxTCtrl;
  late final TextEditingController _wMinHCtrl;
  late final TextEditingController _wMaxHCtrl;
  late final TextEditingController _aMinHCtrl;
  late final TextEditingController _aMaxHCtrl;

  /// Форматирует порог для отображения в поле ввода.
  /// null → пустая строка (не задан), любое число включая 0 → строка.
  String _fmt(double? v) => v != null ? v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1) : '';

  @override
  void initState() {
    super.initState();
    final s = widget.sensor;
    _wMinTCtrl = TextEditingController(text: _fmt(s.warningMinTemp));
    _wMaxTCtrl = TextEditingController(text: _fmt(s.warningMaxTemp));
    _aMinTCtrl = TextEditingController(text: _fmt(s.alarmMinTemp));
    _aMaxTCtrl = TextEditingController(text: _fmt(s.alarmMaxTemp));
    _wMinHCtrl = TextEditingController(text: _fmt(s.warningMinHum));
    _wMaxHCtrl = TextEditingController(text: _fmt(s.warningMaxHum));
    _aMinHCtrl = TextEditingController(text: _fmt(s.alarmMinHum));
    _aMaxHCtrl = TextEditingController(text: _fmt(s.alarmMaxHum));
    _loadHistory();
    _fetchLiveData();
    _fetchSensorThresholds(); // загружаем актуальные пороги с сервера
    _liveTimer    = Timer.periodic(const Duration(seconds: 10), (_) => _fetchLiveData());
    _historyTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadHistory());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _historyTimer?.cancel();
    _wMinTCtrl.dispose(); _wMaxTCtrl.dispose();
    _aMinTCtrl.dispose(); _aMaxTCtrl.dispose();
    _wMinHCtrl.dispose(); _wMaxHCtrl.dispose();
    _aMinHCtrl.dispose(); _aMaxHCtrl.dispose();
    super.dispose();
  }

  /// Запрашивает актуальные температуру и влажность из /telemetry/{id}/latest
  Future<void> _fetchLiveData() async {
    if (!mounted) return;
    try {
      final live = await widget.repo
          .getLatestTelemetry(widget.sensor.id)
          .timeout(const Duration(seconds: 8));
      if (mounted && live != null) {
        setState(() {
          _liveTemp    = live.temperature;
          _liveHum     = live.humidity;
          _liveTs      = live.timestamp;
          _liveLoading = false;
        });
      } else if (mounted) {
        setState(() => _liveLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _liveLoading = false);
    }
  }

  /// Загружает актуальные пороги датчика с сервера и обновляет поля ввода
  Future<void> _fetchSensorThresholds() async {
    try {
      final r = await widget.repo.get('/sensors/${widget.sensor.id}');
      if (!mounted || r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final thresh = (String key) {
        final v = j[key];
        if (v == null) return '';
        final d = (v as num).toDouble();
        return d.toStringAsFixed(d.truncateToDouble() == d ? 0 : 1);
      };
      setState(() {
        _wMinTCtrl.text = thresh('warning_min_temp');
        _wMaxTCtrl.text = thresh('warning_max_temp');
        _aMinTCtrl.text = thresh('alarm_min_temp');
        _aMaxTCtrl.text = thresh('alarm_max_temp');
        _wMinHCtrl.text = thresh('warning_min_hum');
        _wMaxHCtrl.text = thresh('warning_max_hum');
        _aMinHCtrl.text = thresh('alarm_min_hum');
        _aMaxHCtrl.text = thresh('alarm_max_hum');
      });
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      await widget.repo.loadHistory(widget.sensor.id, _period)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Таймаут или ошибка сети — показываем "нет данных", не зависаем
    }
    if (mounted) setState(() {
      _loading    = false;
      _tempPoints = List.of(widget.sensor.points);
      _humPoints  = List.of(widget.sensor.humidityPoints);
    });
  }

  Future<void> _changePeriod(String p) async {
    if (!mounted) return;
    setState(() { _period = p; _loading = true; });
    try {
      await widget.repo.loadHistory(widget.sensor.id, p)
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (mounted) setState(() {
      _loading    = false;
      _tempPoints = List.of(widget.sensor.points);
      _humPoints  = List.of(widget.sensor.humidityPoints);
    });
  }

  Widget _buildChart() {
    final s = widget.sensor;
    final points     = _showTemperature ? _tempPoints : _humPoints;
    final unit       = _showTemperature ? '°C' : '%';
    final label      = _showTemperature ? 'Температура' : 'Влажность';
    final color      = _showTemperature ? AppColors.of(context).accent : kCyan;
    final warningMin = _showTemperature ? s.warningMinTemp : s.warningMinHum;
    final warningMax = _showTemperature ? s.warningMaxTemp : s.warningMaxHum;
    final alarmMin   = _showTemperature ? s.alarmMinTemp   : s.alarmMinHum;
    final alarmMax   = _showTemperature ? s.alarmMaxTemp   : s.alarmMaxHum;

    if (points.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.of(context).card2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: Text('Нет данных ($label)',
            style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12)),
      );
    }

    final minVal = points.reduce((a, b) => a < b ? a : b);
    final maxVal = points.reduce((a, b) => a > b ? a : b);
    final avg    = points.reduce((a, b) => a + b) / points.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 3, height: 14,
              decoration: BoxDecoration(color: color,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600, color: color)),
        ]),
        const SizedBox(height: 8),
        LineChartWidget(
          points:     points,
          timestamps: widget.sensor.timestamps.isNotEmpty ? widget.sensor.timestamps : null,
          color:      color,
          unit:       unit,
          period:     _period,
          warningMin: warningMin,
          warningMax: warningMax,
          alarmMin:   alarmMin,
          alarmMax:   alarmMax,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.of(context).card2, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(label: 'МИН',
                  value: '${minVal.toStringAsFixed(1)}$unit', color: kCyan),
              _VertDivider(),
              _StatCell(label: 'СРЕДНЕЕ',
                  value: '${avg.toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).textMain),
              _VertDivider(),
              _StatCell(label: 'МАКС',
                  value: '${maxVal.toStringAsFixed(1)}$unit', color: color),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined, size: 11, color: AppColors.of(context).textDim),
            const SizedBox(width: 4),
            Text('Нажмите или проведите по графику',
                style: TextStyle(fontSize: 10, color: AppColors.of(context).textDim)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.repo.role == UserRole.admin ||
        widget.repo.role == UserRole.editor;

    return _DarkDialog(
      title: widget.sensor.name,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Live-показания (обновляются каждые 10 сек) ────────────────────
          _LiveReadingsCard(
            temp:      _liveTemp,
            hum:       _liveHum,
            timestamp: _liveTs,
            loading:   _liveLoading,
            isOnline:  widget.sensor.isOnline,
          ),
          const SizedBox(height: 12),
          _HardwareStatusCard(sensor: widget.sensor),
          const SizedBox(height: 16),
          const _SectionLabel(text: 'ПЕРИОД'),
          const SizedBox(height: 6),
          _PeriodTabs(selected: _period, onChanged: _changePeriod),
          const SizedBox(height: 12),
          Row(children: [
            _ChartToggleBtn(
              label: 'Температура', selected: _showTemperature,
              color: AppColors.of(context).accent,
              onTap: () => setState(() => _showTemperature = true),
            ),
            const SizedBox(width: 8),
            _ChartToggleBtn(
              label: 'Влажность', selected: !_showTemperature,
              color: kCyan,
              onTap: () => setState(() => _showTemperature = false),
            ),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(
                  color: kCyan, strokeWidth: 2)),
            )
          else
            _buildChart(),
          const SizedBox(height: 20),
          const _SectionLabel(text: 'ПОРОГИ ТЕМПЕРАТУРЫ (°C)'),
          const SizedBox(height: 8),
          _ThresholdRow(label: 'Внимание', color: kOrange,
              minCtrl: _wMinTCtrl, maxCtrl: _wMaxTCtrl, signed: true,
              readOnly: !canEdit),
          const SizedBox(height: 6),
          _ThresholdRow(label: 'Тревога', color: kRed,
              minCtrl: _aMinTCtrl, maxCtrl: _aMaxTCtrl, signed: true,
              readOnly: !canEdit),
          const SizedBox(height: 20),
          const _SectionLabel(text: 'ПОРОГИ ВЛАЖНОСТИ (%)'),
          const SizedBox(height: 8),
          _ThresholdRow(label: 'Внимание', color: kOrange,
              minCtrl: _wMinHCtrl, maxCtrl: _wMaxHCtrl,
              readOnly: !canEdit),
          const SizedBox(height: 6),
          _ThresholdRow(label: 'Тревога', color: kRed,
              minCtrl: _aMinHCtrl, maxCtrl: _aMaxHCtrl,
              readOnly: !canEdit),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        if (canEdit)
          _DarkFilledButton(
            label: 'Сохранить пороги',
            onTap: () async {
              final wMinT = double.tryParse(_wMinTCtrl.text.trim());
              final wMaxT = double.tryParse(_wMaxTCtrl.text.trim());
              final aMinT = double.tryParse(_aMinTCtrl.text.trim());
              final aMaxT = double.tryParse(_aMaxTCtrl.text.trim());
              final wMinH = double.tryParse(_wMinHCtrl.text.trim());
              final wMaxH = double.tryParse(_wMaxHCtrl.text.trim());
              final aMinH = double.tryParse(_aMinHCtrl.text.trim());
              final aMaxH = double.tryParse(_aMaxHCtrl.text.trim());

              if (wMinT == null || wMaxT == null || aMinT == null || aMaxT == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Введите корректные значения температуры')));
                return;
              }

              final err = await widget.repo.updateSensorThresholds(
                sensorId: widget.sensor.id,
                warningMinTemp: wMinT, warningMaxTemp: wMaxT,
                alarmMinTemp: aMinT,  alarmMaxTemp: aMaxT,
                warningMinHum: wMinH, warningMaxHum: wMaxH,
                alarmMinHum: aMinH,   alarmMaxHum: aMaxH,
              );

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err ?? 'Пороги сохранены')));
              if (err == null) {
                Navigator.pop(context);
                await widget.onRefresh();
              }
            },
          ),
      ],
    );
  }
}

// ── Группа локации ────────────────────────────────────────────────────────────

class _LocationGroup extends StatefulWidget {
  const _LocationGroup({
    required this.location,
    required this.sensors,
    required this.controlUnits,
    required this.onSensorTap,
    required this.repo,
  });
  final LocationModel location;
  final List<SensorModel> sensors;
  final List<Map<String, dynamic>> controlUnits;
  final void Function(SensorModel) onSensorTap;
  final AppRepository repo;

  @override
  State<_LocationGroup> createState() => _LocationGroupState();
}

class _LocationGroupState extends State<_LocationGroup> {
  // По умолчанию свёрнуто — датчики скрыты при входе на экран
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Датчики без блока управления
    final freesensors = widget.sensors
        .where((s) => s.controlUnitId == null)
        .toList();

    final totalCount = widget.sensors.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        children: [
          // ── Заголовок локации ────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: kCyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.location.name,
                      style: TextStyle(
                        color: AppColors.of(context).textMain,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '$totalCount датч.',
                    style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.of(context).textDim, size: 18,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Container(height: 1, color: AppColors.of(context).border),

            // ── Блоки управления со своими датчиками ─────────────────────
            ...widget.controlUnits.map((unit) {
              final unitId = (unit['id'] as num?)?.toInt();
              final unitSensors = widget.sensors
                  .where((s) => s.controlUnitId == unitId)
                  .toList();
              return _ControlUnitGroup(
                unit: unit,
                sensors: unitSensors,
                onSensorTap: widget.onSensorTap,
                repo: widget.repo,
              );
            }),

            // ── Датчики без блока управления (после блоков) ──────────────
            ...freesensors.mapIndexed((i, sensor) => _SensorRow(
              sensor: sensor,
              repo: widget.repo,
              onTap: () => widget.onSensorTap(sensor),
              isLast: i == freesensors.length - 1,
              indent: false,
            )),
          ],
        ],
      ),
    );
  }
}

// ── Группа блока управления ───────────────────────────────────────────────────

class _ControlUnitGroup extends StatefulWidget {
  const _ControlUnitGroup({
    required this.unit,
    required this.sensors,
    required this.onSensorTap,
    required this.repo,
  });
  final Map<String, dynamic> unit;
  final List<SensorModel> sensors;
  final void Function(SensorModel) onSensorTap;
  final AppRepository repo;

  @override
  State<_ControlUnitGroup> createState() => _ControlUnitGroupState();
}

class _ControlUnitGroupState extends State<_ControlUnitGroup> {
  bool _expanded = true;

  Color _gsmColor(AppScheme sch, int bars) => switch (bars) {
        5 => kGreen,
        4 => kGreen,
        3 => kGreen,
        2 => kOrange,
        1 => kRed,
        _ => sch.textDim,
      };

  Color _batteryColor(AppScheme sch, bool isAc, int? level) {
    if (isAc) return kGreen;
    if (level == null) return sch.textDim;
    if (level >= 50) return kGreen;
    if (level >= 25) return kOrange;
    return kRed;
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final isOnline = widget.unit['is_online'] as bool? ?? false;
    final unitName = widget.unit['name'] as String? ?? '—';

    // Берём технические данные из первого датчика блока
    // (GSM/SIM/питание — общие для всего блока управления)
    final refSensor = widget.sensors.isNotEmpty ? widget.sensors.first : null;
    final gsmSignal  = refSensor?.gsmSignal;
    final gsmBars    = refSensor?.gsmBars ?? 0;
    final simBalance = refSensor?.simBalance;
    final isAc       = refSensor?.isAcPowered ?? false;
    final battery    = refSensor?.batteryLevel;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: sch.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sch.border),
      ),
      child: Column(
        children: [
          // ── Заголовок блока ──────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.router_outlined, color: sch.accent, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          unitName,
                          style: TextStyle(
                            color: sch.accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOnline ? sch.greenBg : sch.redBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isOnline ? kGreen.withOpacity(0.3) : kRed.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? kGreen : kRed,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.sensors.length} датч.',
                        style: TextStyle(color: sch.textDim, fontSize: 11),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: sch.textDim, size: 16,
                      ),
                    ],
                  ),
                  // ── GSM / SIM / батарея блока управления ────────────────
                  if (refSensor != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniChip(
                          label: isAc ? '~220В' : '${battery ?? '—'}%',
                          color: _batteryColor(sch, isAc, battery),
                        ),
                        if (gsmSignal != null)
                          _MiniChip(
                            label: 'GSM $gsmBars/5',
                            color: _gsmColor(sch, gsmBars),
                          ),
                        if (simBalance != null)
                          _MiniChip(
                            label: '${simBalance.toStringAsFixed(0)} ₽',
                            color: simBalance < 50 ? kRed : sch.textDim,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_expanded && widget.sensors.isNotEmpty) ...[
            Container(height: 1, color: AppColors.of(context).border),
            ...widget.sensors.mapIndexed((i, sensor) => _SensorRow(
              sensor: sensor,
              repo: widget.repo,
              onTap: () => widget.onSensorTap(sensor),
              isLast: i == widget.sensors.length - 1,
              indent: true,
            )),
          ],

          if (_expanded && widget.sensors.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(
                'Нет датчиков',
                style: TextStyle(color: sch.textDim, fontSize: 12),
              ),
            ),

          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ── Строка датчика ────────────────────────────────────────────────────────────

class _SensorRow extends StatefulWidget {
  const _SensorRow({
    required this.sensor,
    required this.repo,
    required this.onTap,
    required this.isLast,
    this.indent = false,
  });
  final SensorModel sensor;
  final AppRepository repo;
  final VoidCallback onTap;
  final bool isLast;
  final bool indent;

  @override
  State<_SensorRow> createState() => _SensorRowState();
}

class _SensorRowState extends State<_SensorRow> {
  double? _temp;
  double? _hum;

  @override
  void initState() {
    super.initState();
    // Если sensor уже имеет ненулевые данные — показываем сразу
    if (widget.sensor.temperature != 0.0 || widget.sensor.humidity != 0.0) {
      _temp = widget.sensor.temperature;
      _hum  = widget.sensor.humidity;
    }
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    try {
      final live = await widget.repo
          .getLatestTelemetry(widget.sensor.id)
          .timeout(const Duration(seconds: 8));
      if (mounted && live != null) {
        setState(() {
          _temp = live.temperature;
          _hum  = live.humidity;
        });
      }
    } catch (_) {}
  }

  Color _batteryColor(AppScheme sch, bool isAc, int? level) {
    if (isAc) return kGreen;
    if (level == null) return sch.textDim;
    if (level >= 50) return kGreen;
    if (level >= 25) return kOrange;
    return kRed;
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final sensor = widget.sensor;
    final stateColor = switch (sensor.state) {
      SensorState.normal   => kGreen,
      SensorState.warning  => kOrange,
      SensorState.critical => kRed,
    };

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(widget.indent ? 20 : 14, 11, 14, 11),
        decoration: BoxDecoration(
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: sch.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stateColor,
                boxShadow: [
                  BoxShadow(color: stateColor.withOpacity(0.45), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sensor.name,
                    style: TextStyle(
                      color: sch.textMain,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _temp != null
                          ? Text(
                              '${_temp!.toStringAsFixed(1)}°C',
                              style: TextStyle(
                                fontSize: 12,
                                color: sch.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  color: sch.accent, strokeWidth: 1.5),
                            ),
                      _hum != null
                          ? Text(
                              '${_hum!.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: kCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : const SizedBox.shrink(),
                      _MiniChip(
                        label: sensor.isAcPowered
                            ? '~220В'
                            : '${sensor.batteryLevel ?? '—'}%',
                        color: _batteryColor(sch, sensor.isAcPowered, sensor.batteryLevel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: sch.textDim, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Карточка живых показаний (температура + влажность + время) ───────────────

class _LiveReadingsCard extends StatelessWidget {
  const _LiveReadingsCard({
    required this.temp,
    required this.hum,
    required this.timestamp,
    required this.loading,
    required this.isOnline,
  });
  final double?   temp;
  final double?   hum;
  final DateTime? timestamp;
  final bool      loading;
  final bool      isOnline;

  String _fmtTime(DateTime? ts) {
    if (ts == null) return '—';
    final local = ts.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: sch.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sch.border),
      ),
      child: loading
          ? const SizedBox(
              height: 48,
              child: Center(
                child: CircularProgressIndicator(color: kCyan, strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'ТЕКУЩИЕ ПОКАЗАНИЯ',
                      style: TextStyle(
                        fontSize: 10,
                        color: sch.textDim,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    // Индикатор автообновления
                    Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? kGreen : sch.textDim,
                            boxShadow: isOnline
                                ? [BoxShadow(
                                    color: kGreen.withOpacity(0.5),
                                    blurRadius: 4)]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'обн. ${_fmtTime(timestamp)}',
                          style: TextStyle(
                              fontSize: 10, color: sch.textDim),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (temp == null && hum == null)
                  Text(
                    'Нет данных от датчика',
                    style: TextStyle(color: sch.textDim, fontSize: 12),
                  )
                else
                  Row(
                    children: [
                      // Температура
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: sch.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: sch.accent.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.thermostat_outlined,
                                    color: sch.accent, size: 13),
                                const SizedBox(width: 4),
                                Text('Температура',
                                    style: TextStyle(
                                        fontSize: 10, color: sch.textDim)),
                              ]),
                              const SizedBox(height: 6),
                              Text(
                                temp != null
                                    ? '${temp!.toStringAsFixed(1)} °C'
                                    : '—',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: sch.accent,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Влажность
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: kCyan.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: kCyan.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.water_drop_outlined,
                                    color: kCyan, size: 13),
                                const SizedBox(width: 4),
                                Text('Влажность',
                                    style: TextStyle(
                                        fontSize: 10, color: sch.textDim)),
                              ]),
                              const SizedBox(height: 6),
                              Text(
                                hum != null
                                    ? '${hum!.toStringAsFixed(1)} %'
                                    : '—',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: kCyan,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

// ── Карточка технических характеристик ───────────────────────────────────────

class _HardwareStatusCard extends StatelessWidget {
  const _HardwareStatusCard({required this.sensor});
  final SensorModel sensor;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: sch.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sch.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ГОЛОВНОЙ БЛОК',
                style: TextStyle(
                  fontSize: 10,
                  color: sch.textDim,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sensor.isOnline ? sch.greenBg : sch.redBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: sensor.isOnline
                        ? kGreen.withOpacity(0.35)
                        : kRed.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  sensor.isOnline ? 'В сети' : 'Нет связи',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: sensor.isOnline ? kGreen : kRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PowerCol(sensor: sensor),
        ],
      ),
    );
  }
}

class _PowerCol extends StatelessWidget {
  const _PowerCol({required this.sensor});
  final SensorModel sensor;

  @override
  Widget build(BuildContext context) {
    final isAc = sensor.isAcPowered;
    final battery = sensor.batteryLevel;
    final color = isAc
        ? kGreen
        : (battery != null && battery < 25
            ? kRed
            : battery != null && battery < 50
                ? kOrange
                : kGreen);
    final value = isAc ? 'Сеть 220В' : (battery != null ? '$battery%' : '—');

    return _StatCol(
      label: 'ПИТАНИЕ',
      value: value,
      valueColor: color,
      extra: (!isAc && battery != null) ? _BatteryBar(level: battery) : null,
    );
  }
}

class _GsmCol extends StatelessWidget {
  const _GsmCol({required this.sensor});
  final SensorModel sensor;

  @override
  Widget build(BuildContext context) {
    final bars = sensor.gsmBars;
    final hasSignal = sensor.gsmSignal != null;
    final color = bars >= 4
        ? kGreen
        : bars == 3
            ? kGreen
            : bars == 2
                ? kOrange
                : bars == 1
                    ? kRed
                    : AppColors.of(context).textDim;

    return _StatCol(
      label: 'GSM',
      value: hasSignal ? '$bars/5' : '—',
      valueColor: color,
      extra: hasSignal ? _GsmBars(bars: bars) : null,
    );
  }
}

class _SimCol extends StatelessWidget {
  const _SimCol({required this.sensor});
  final SensorModel sensor;

  @override
  Widget build(BuildContext context) {
    final balance = sensor.simBalance;
    final color = balance == null
        ? AppColors.of(context).textDim
        : balance < 50
            ? kRed
            : balance < 150
                ? kOrange
                : kGreen;

    return _StatCol(
      label: 'SIM',
      value: balance != null ? '${balance.toStringAsFixed(0)} ₽' : '—',
      valueColor: color,
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({
    required this.label,
    required this.value,
    required this.valueColor,
    this.extra,
  });
  final String label;
  final String value;
  final Color valueColor;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: AppColors.of(context).textDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
          if (extra != null) ...[
            const SizedBox(height: 5),
            extra!,
          ],
        ],
      ),
    );
  }
}

// ── Мелкие виджеты ────────────────────────────────────────────────────────────

class _BatteryBar extends StatelessWidget {
  const _BatteryBar({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = level < 25 ? kRed : level < 50 ? kOrange : kGreen;
    return SizedBox(
      width: 44,
      child: Stack(
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.of(context).border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          FractionallySizedBox(
            widthFactor: level / 100,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GsmBars extends StatelessWidget {
  const _GsmBars({required this.bars});
  final int bars;

  @override
  Widget build(BuildContext context) {
    final color = bars >= 4 ? kGreen : bars == 3 ? kGreen : bars == 2 ? kOrange : kRed;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 2,
      children: List.generate(5, (i) {
        final filled = i < bars;
        return Container(
          width: 4,
          height: 3.0 + i * 2.5,
          decoration: BoxDecoration(
            color: filled ? color : AppColors.of(context).border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: sch.textDim,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Вспомогательные виджеты статистики ───────────────────────────────────────

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 9,
              color: AppColors.of(context).textDim,
              letterSpacing: 0.4,
            )),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 22, color: AppColors.of(context).border);
}

// ─────────────────────────────────────────────────────────────────────────────

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onChanged});
  final String selected;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 6,
      children: ['День', 'Неделя', 'Месяц'].map((p) {
        final active = p == selected;
        return GestureDetector(
          onTap: () => onChanged(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: active ? kCyan.withOpacity(0.15) : AppColors.of(context).card2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active ? kCyan.withOpacity(0.5) : AppColors.of(context).border,
              ),
            ),
            child: Text(
              p,
              style: TextStyle(
                fontSize: 12,
                color: active ? kCyan : AppColors.of(context).textDim,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChartToggleBtn extends StatelessWidget {
  const _ChartToggleBtn({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : AppColors.of(context).card2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : AppColors.of(context).border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? color : AppColors.of(context).textDim,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.label,
    required this.color,
    required this.minCtrl,
    required this.maxCtrl,
    this.signed = false,
    this.readOnly = false,
  });
  final String label;
  final Color color;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final bool signed;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: _DarkField(
            controller: minCtrl,
            label: 'Min',
            keyboardType: TextInputType.numberWithOptions(
                decimal: true, signed: signed),
            readOnly: readOnly,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DarkField(
            controller: maxCtrl,
            label: 'Max',
            keyboardType: TextInputType.numberWithOptions(
                decimal: true, signed: signed),
            readOnly: readOnly,
          ),
        ),
      ],
    );
  }
}

// ── Тёмные компоненты (аналогичны settings_screen) ───────────────────────────

class _DarkDialog extends StatelessWidget {
  const _DarkDialog({
    required this.title,
    required this.content,
    required this.actions,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    final sch = AppColors.of(context);
    return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenH * 0.88),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sch.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Заголовок ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: sch.textMain,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    // Кнопка ✕ закрытия в шапке
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: sch.card2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.close,
                            color: sch.textDim, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: sch.border),

              // ── Контент (скроллируемый) ───────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: content,
                ),
              ),

              // ── Кнопки действий ───────────────────────────────────────────
              if (actions.isNotEmpty) ...[
                Divider(height: 1, color: sch.border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: TextStyle(
        color: readOnly ? sch.textDim : sch.textMain,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: sch.textDim, fontSize: 13),
        hintStyle: TextStyle(color: sch.textDim, fontSize: 12),
        filled: readOnly,
        fillColor: readOnly ? sch.card2 : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: readOnly ? sch.border.withOpacity(0.5) : sch.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: readOnly ? sch.border.withOpacity(0.5) : kCyan,
          ),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }
}

class _DarkDropdown<T> extends StatelessWidget {
  const _DarkDropdown({
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
    final sch = AppColors.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(color: sch.textMain, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sch.textDim, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: sch.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _DarkTextButton extends StatelessWidget {
  const _DarkTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: sch.textDim, fontSize: 13)),
    );
  }
}

class _DarkFilledButton extends StatelessWidget {
  const _DarkFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: kCyan,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

// ── Расширение для mapIndexed ─────────────────────────────────────────────────

extension _IndexedIterable<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) f) {
    var i = 0;
    return map((e) => f(i++, e));
  }
}