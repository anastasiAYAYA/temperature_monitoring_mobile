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

part 'sensors/sensor_detail_dialog.dart';
part 'sensors/sensor_groups.dart';
part 'sensors/sensor_cards.dart';
part 'sensors/sensor_common_widgets.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.repo, required this.onRefresh});

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
    final nameCtrl = TextEditingController();
    final serialNumberCtrl = TextEditingController();
    final devEuiCtrl = TextEditingController();
    int? selectedLocationId = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;

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
                    .map(
                      (e) => DropdownMenuItem<int>(
                        value: e.id,
                        child: Text(e.name),
                      ),
                    )
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
                final name = nameCtrl.text.trim();
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
                  name: name,
                  locationId: selectedLocationId!,
                  serialNumber: serialNumber,
                  devEui: devEui.isEmpty ? null : devEui,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (result.error != null) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(result.error!)));
                  return;
                }

                // Токен не показываем пользователю — он передаётся на устройство
                // через прошивку и не должен отображаться в интерфейсе.
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: c.green, size: 16),
                          const SizedBox(width: 8),
                          const Text('Блок управления успешно создан'),
                        ],
                      ),
                      backgroundColor: c.greenBg,
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
    final nameCtrl = TextEditingController();
    final internalIdCtrl = TextEditingController();
    final delayCtrl = TextEditingController(text: '0');

    int? selectedLocationId = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;
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
              !units.any(
                (u) => (u['id'] as num?)?.toInt() == selectedControlUnitId,
              )) {
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
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() {
                      selectedLocationId = v;
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
                      ...units.map(
                        (u) => DropdownMenuItem<int>(
                          value: (u['id'] as num?)?.toInt(),
                          child: Text(u['name'] as String? ?? '—'),
                        ),
                      ),
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
                    onTap: () =>
                        setSt(() => thresholdsExpanded = !thresholdsExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
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
                      label: 'Внимание',
                      color: kOrange,
                      minCtrl: wMinTCtrl,
                      maxCtrl: wMaxTCtrl,
                      signed: true,
                    ),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Тревога',
                      color: kRed,
                      minCtrl: aMinTCtrl,
                      maxCtrl: aMaxTCtrl,
                      signed: true,
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel(text: 'ВЛАЖНОСТЬ (%)'),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Внимание',
                      color: kOrange,
                      minCtrl: wMinHCtrl,
                      maxCtrl: wMaxHCtrl,
                    ),
                    const SizedBox(height: 6),
                    _ThresholdRow(
                      label: 'Тревога',
                      color: kRed,
                      minCtrl: aMinHCtrl,
                      maxCtrl: aMaxHCtrl,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.cyan.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.cyan.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Правило: Тревога min ≤ Внимание min < Внимание max ≤ Тревога max',
                        style: TextStyle(fontSize: 11, color: c.cyan),
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
                  if (aMinT != null &&
                      wMinT != null &&
                      wMaxT != null &&
                      aMaxT != null) {
                    if (!(aMinT <= wMinT && wMinT < wMaxT && wMaxT <= aMaxT)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Нарушен порядок порогов: '
                            'Тревога min ≤ Внимание min < Внимание max ≤ Тревога max',
                          ),
                        ),
                      );
                      setSt(() => thresholdsExpanded = true);
                      return;
                    }
                  }

                  final internalId = internalIdCtrl.text.trim();

                  final err = await widget.repo.createSensor(
                    name: name,
                    locationId: selectedLocationId!,
                    controlUnitId: selectedControlUnitId,
                    internalId: internalId.isEmpty ? null : internalId,
                    alarmDelaySeconds: delay,
                    warningMinTemp: wMinT,
                    warningMaxTemp: wMaxT,
                    alarmMinTemp: aMinT,
                    alarmMaxTemp: aMaxT,
                    warningMinHum: wMinH,
                    warningMaxHum: wMaxH,
                    alarmMinHum: aMinH,
                    alarmMaxHum: aMaxH,
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
    final canManage =
        widget.repo.role == UserRole.admin ||
        widget.repo.role == UserRole.editor;

    final grouped = <LocationModel, List<SensorModel>>{};
    for (final location in widget.repo.locations) {
      final items = widget.repo.sensors
          .where((e) => e.groupId == location.id)
          .toList();
      final hasUnits = widget.repo.controlUnits.any(
        (u) => (u['group_id'] as num?)?.toInt() == location.id,
      );
      if (items.isNotEmpty || hasUnits) grouped[location] = items;
      // Локации без датчиков и без блоков управления — не добавляем (не показываем)
    }

    final query = search.trim().toLowerCase();
    final filteredEntries = grouped.entries.where((entry) {
      if (query.isEmpty) return true;
      final locUnits = widget.repo.controlUnits.where(
        (u) => (u['group_id'] as num?)?.toInt() == entry.key.id,
      );
      return entry.key.name.toLowerCase().contains(query) ||
          entry.value.any((s) => s.name.toLowerCase().contains(query)) ||
          locUnits.any(
            (u) => (u['name'] as String? ?? '').toLowerCase().contains(query),
          );
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
                    borderSide: BorderSide(color: c.cyan),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                      child: Icon(
                        Icons.router_outlined,
                        color: c.accent,
                        size: 20,
                      ),
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
                      color: c.cyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.cyan.withOpacity(0.35)),
                    ),
                    child: Icon(Icons.add, color: c.cyan, size: 20),
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
                  .where(
                    (u) => (u['group_id'] as num?)?.toInt() == entry.key.id,
                  )
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
