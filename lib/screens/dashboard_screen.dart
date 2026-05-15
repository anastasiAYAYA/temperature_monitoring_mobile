import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/alarm_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';
import '../widgets/sensor_dot.dart';

/// Координаты датчиков на плане хранятся как **доли ширины/высоты** (0…1) и переводятся
/// в пиксели умножением на размер области схемы — см. [_SchemaViewport], [_onSensorPanUpdate].

part 'dashboard/dashboard_company_widgets.dart';
part 'dashboard/dashboard_sensor_row.dart';
part 'dashboard/dashboard_chart_widgets.dart';
part 'dashboard/dashboard_dialog_widgets.dart';
part 'dashboard/dashboard_schema_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
  });

  final AppRepository repo;

  /// Вызывается после создания локации / загрузки плана — перезагружает кеш в родителе.
  final Future<void> Function() onRefresh;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppScheme get c => AppColors.of(context);

  /// Индекс выбранной локации в [AppRepository.locations] (для editor/viewer).
  int _selectedLocationIndex = 0;

  /// Для admin: id выбранной компании; `null` — показан список компаний с поиском.
  int? _adminSelectedLocationId;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// Привязка к области мнемосхемы: нужна, чтобы переводить drag из пикселей в 0…1.
  final GlobalKey _schemaKey = GlobalKey();

  final TransformationController _transformCtrl = TransformationController();

  /// Режим перетаскивания датчиков; позиции до «Сохранить» можно откатить через [_draftPositions].
  bool _editMode = false;
  final Map<int, (double, double)> _draftPositions = {};

  bool get _isAdmin => widget.repo.role == UserRole.admin;

  @override
  void dispose() {
    _transformCtrl.dispose();
    _searchCtrl.dispose();
    // Снимаем колбэк позиций чтобы не вызывать setState после уничтожения виджета
    widget.repo.clearPositionCallback();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Регистрируем колбэк позиций: при WS-событии sensor_position обновляем маркер на схеме.
    // FIX: используем setPositionCallback — так мнемосхема мгновенно реагирует на правки
    // другого клиента (например, веб-интерфейса) без рефетча всего списка датчиков.
    widget.repo.setPositionCallback((sensorId, posX, posY, groupId) {
      if (!mounted) return;
      // Фильтр по группе: если groupId передан и не совпадает с открытой локацией — игнорируем.
      final currentLocId = _isAdmin
          ? _adminSelectedLocationId
          : (widget.repo.locations.isNotEmpty
                ? widget.repo.locations[_selectedLocationIndex].id
                : null);
      if (groupId != null && currentLocId != null && groupId != currentLocId)
        return;
      setState(
        () {},
      ); // позиции уже обновлены в кеше репозитория — просто перерисовываем
    });
    // Sparkline строится из repo.loadHistory — вызываем после первого кадра, когда контекст готов.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCharts());
  }

  /// Подгружает историю периода «День» для всех датчиков текущей локации (точки в [AppRepository]).
  Future<void> _loadCharts() async {
    final sensors = _sensorsForCurrentLocation;
    for (final s in sensors) {
      await widget.repo.loadHistory(s.id, 'День');
    }
    if (mounted) setState(() {});
  }

  /// Диалог: POST локации (multipart `name`), затем опционально `uploadLocationPlan` для последней созданной.
  Future<void> _showCreateLocationDialog() async {
    final nameCtrl = TextEditingController();
    PlatformFile? pickedFile;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _AppDialog(
          title: 'Новая компания',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppField(controller: nameCtrl, label: 'Название компании'),
              const SizedBox(height: 14),
              if (pickedFile != null) ...[
                _FilePreview(name: pickedFile!.name),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _OutlineBtn(
                      label: pickedFile == null ? 'Выбрать план' : 'Сменить',
                      color: kCyan,
                      onTap: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'svg'],
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          setDialogState(() => pickedFile = result.files.first);
                        }
                      },
                    ),
                  ),
                  if (pickedFile != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: c.red, size: 20),
                      onPressed: () => setDialogState(() => pickedFile = null),
                    ),
                  ],
                ],
              ),
              if (pickedFile == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'JPG, PNG или SVG, до 50 МБ',
                    style: TextStyle(fontSize: 11, color: c.textDim),
                  ),
                ),
            ],
          ),
          actions: [
            _AppTextBtn(label: 'Отмена', onTap: () => Navigator.pop(context)),
            _AppFilledBtn(
              label: 'Создать',
              onTap: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите название компании')),
                  );
                  return;
                }
                final createErr = await widget.repo.createLocation(name: name);
                if (!context.mounted) return;
                if (createErr != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(createErr)));
                  return;
                }
                if (pickedFile != null) {
                  await widget.onRefresh();
                  if (!context.mounted) return;
                  final newLoc = widget.repo.locations.isNotEmpty
                      ? widget.repo.locations.last
                      : null;
                  if (newLoc != null) {
                    final uploadErr = await widget.repo.uploadLocationPlan(
                      locationId: newLoc.id,
                      fileBytes: pickedFile!.bytes!,
                      mimeType: _mimeType(pickedFile!.name),
                      fileName: pickedFile!.name,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          uploadErr == null
                              ? 'Компания создана с планом'
                              : 'Компания создана, план не загрузился: $uploadErr',
                        ),
                      ),
                    );
                    await widget.onRefresh();
                    return;
                  }
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Компания создана')),
                );
                await widget.onRefresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUploadPlanDialog(
    int locationId,
    String locationName,
  ) async {
    PlatformFile? pickedFile;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _AppDialog(
          title: 'План для «$locationName»',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pickedFile != null) ...[
                _FilePreview(name: pickedFile!.name),
                const SizedBox(height: 8),
              ],
              _OutlineBtn(
                label: pickedFile == null ? 'Выбрать файл' : 'Сменить',
                color: kCyan,
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['jpg', 'jpeg', 'png', 'svg'],
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    setDialogState(() => pickedFile = result.files.first);
                  }
                },
              ),
              const SizedBox(height: 4),
              Text(
                'JPG, PNG или SVG, до 50 МБ',
                style: TextStyle(fontSize: 11, color: c.textDim),
              ),
            ],
          ),
          actions: [
            _AppTextBtn(label: 'Отмена', onTap: () => Navigator.pop(context)),
            _AppFilledBtn(
              label: 'Загрузить',
              onTap: pickedFile == null
                  ? null
                  : () async {
                      final err = await widget.repo.uploadLocationPlan(
                        locationId: locationId,
                        fileBytes: pickedFile!.bytes!,
                        mimeType: _mimeType(pickedFile!.name),
                        fileName: pickedFile!.name,
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err ?? 'План загружен')),
                      );
                      if (err == null) await widget.onRefresh();
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// MIME для multipart загрузки плана (сервер ориентируется на Content-Type части).
  String _mimeType(String path) {
    final l = path.toLowerCase();
    if (l.endsWith('.png')) return 'image/png';
    if (l.endsWith('.svg')) return 'image/svg+xml';
    return 'image/jpeg';
  }

  /// Датчики выбранной локации: сопоставление по `SensorModel.groupId` и id локации из репозитория.
  List<SensorModel> get _sensorsForCurrentLocation {
    if (_isAdmin) {
      if (_adminSelectedLocationId == null) return [];
      return widget.repo.sensors
          .where((s) => s.groupId == _adminSelectedLocationId)
          .toList();
    }
    if (widget.repo.locations.isEmpty) return widget.repo.sensors;
    final id = widget.repo.locations[_selectedLocationIndex].id;
    return widget.repo.sensors.where((s) => s.groupId == id).toList();
  }

  /// Перевод смещения пальца/мыши из пикселей в приращение нормализованных координат.
  void _onSensorPanUpdate(SensorModel sensor, Offset delta) {
    final box = _schemaKey.currentContext?.findRenderObject() as RenderBox?;
    final schemaW = box?.size.width ?? 300.0;
    final schemaH = box?.size.height ?? 300.0;
    setState(() {
      sensor.x = sensor.x <= 1.0
          ? (sensor.x + delta.dx / schemaW).clamp(0.0, 1.0)
          : (sensor.x + delta.dx).clamp(0.0, double.infinity);
      sensor.y = sensor.y <= 1.0
          ? (sensor.y + delta.dy / schemaH).clamp(0.0, 1.0)
          : (sensor.y + delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _enterEditMode() {
    setState(() {
      _editMode = true;
      _draftPositions.clear();
      for (final s in widget.repo.sensors) {
        _draftPositions[s.id] = (s.x, s.y);
      }
    });
  }

  void _cancelEditMode() {
    setState(() {
      for (final s in widget.repo.sensors) {
        final orig = _draftPositions[s.id];
        if (orig != null) {
          s.x = orig.$1;
          s.y = orig.$2;
        }
      }
      _editMode = false;
      _draftPositions.clear();
    });
  }

  /// PATCH координат только для датчиков, сдвинутых заметно относительно снимка [_draftPositions].
  /// По инструкции: использует PATCH /sensors/{id}/position (только admin).
  /// При любой ошибке (в т.ч. 403) откатывает координаты к снимку [_draftPositions].
  Future<void> _confirmEditMode() async {
    final changed = widget.repo.sensors.where((s) {
      final orig = _draftPositions[s.id];
      if (orig == null) return false;
      return (s.x - orig.$1).abs() > 0.002 || (s.y - orig.$2).abs() > 0.002;
    }).toList();

    setState(() => _editMode = false);
    if (changed.isEmpty) {
      _draftPositions.clear();
      return;
    }

    final errors = <String>[];
    bool anyForbidden = false;
    for (final s in changed) {
      final err = await widget.repo.updateSensorPosition(
        sensorId: s.id,
        posX: s.x,
        posY: s.y,
      );
      if (err != null) {
        errors.add('${s.name}: $err');
        // FIX: при ошибке (в т.ч. 403) откатываем позицию к серверной из снимка.
        // Не оставляем локальные координаты без подтверждения сервером (чеклист п.5).
        final orig = _draftPositions[s.id];
        if (orig != null) {
          setState(() {
            s.x = orig.$1;
            s.y = orig.$2;
          });
        }
        if (err.contains('403') || err.contains('прав')) anyForbidden = true;
      }
    }
    _draftPositions.clear();
    if (!mounted) return;

    final msg = errors.isEmpty
        ? (changed.length == 1
              ? 'Позиция датчика сохранена'
              : 'Позиции ${changed.length} датчиков сохранены')
        : anyForbidden
        ? 'Нет прав на изменение позиций. Координаты возвращены к серверным.'
        : 'Ошибки при сохранении: ${errors.join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// API может вернуть относительный `image_url` — склеиваем с origin без суффикса `/api/v1`.
  String _resolveImageUrl(String imageUrl, String baseUrl) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://'))
      return imageUrl;
    return '${baseUrl.replaceAll(RegExp(r'/api/v\d+$'), '')}$imageUrl';
  }

  Color _alarmColor(AlarmStatus s) => switch (s) {
    AlarmStatus.newAlarm => c.red,
    AlarmStatus.acknowledged => c.orange,
    AlarmStatus.resolved => c.green,
  };

  String _alarmLabel(AlarmStatus s) => switch (s) {
    AlarmStatus.newAlarm => 'НОВОЕ',
    AlarmStatus.acknowledged => 'В РАБОТЕ',
    AlarmStatus.resolved => 'РЕШЕНО',
  };

  Color _alarmBg(AlarmStatus s) => switch (s) {
    AlarmStatus.newAlarm => c.redBg,
    AlarmStatus.acknowledged =>
      c.isDark ? const Color(0xFF2A1E00) : const Color(0xFFFFF3E0),
    AlarmStatus.resolved =>
      c.isDark ? const Color(0xFF0E2A1E) : const Color(0xFFE8F5E9),
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _isAdmin ? _buildAdminView(c) : _buildUserView(c);
  }

  /// Admin: поиск и алфавитный список компаний → по тапу [_buildCompanyContent].
  Widget _buildAdminView(AppScheme c) {
    final locations = widget.repo.locations;
    final filtered = _searchQuery.isEmpty
        ? locations
        : locations
              .where(
                (l) =>
                    l.name.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();
    final sorted = List.of(filtered)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (_adminSelectedLocationId != null) {
      final loc = locations
          .where((l) => l.id == _adminSelectedLocationId)
          .firstOrNull;
      return _buildCompanyContent(c, loc);
    }

    return Container(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Компании',
                    style: TextStyle(
                      color: c.textMain,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _showCreateLocationDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.yellowBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.accent.withOpacity(0.5)),
                    ),
                    child: Text(
                      '+ Компания',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: c.textMain, fontSize: 14),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Поиск компании…',
                hintStyle: TextStyle(color: c.textDim, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: c.textDim, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(Icons.close, color: c.textDim, size: 16),
                      )
                    : null,
                filled: true,
                fillColor: c.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.cyan),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 48,
                          color: c.textDim,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Компании не найдены'
                              : 'Нет компаний\nНажмите «+ Компания» чтобы создать',
                          style: TextStyle(color: c.textDim, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _buildAlphaList(c, sorted),
          ),
        ],
      ),
    );
  }

  Widget _buildAlphaList(AppScheme c, List<dynamic> sorted) {
    final Map<String, List<dynamic>> groups = {};
    for (final loc in sorted) {
      final letter = loc.name.isNotEmpty ? loc.name[0].toUpperCase() : '#';
      groups.putIfAbsent(letter, () => []).add(loc);
    }
    final letters = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: letters.length,
      itemBuilder: (context, i) {
        final letter = letters[i];
        final items = groups[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            ...items.map(
              (loc) => _CompanyTile(
                name: loc.name,
                sensorCount: widget.repo.sensors
                    .where((s) => s.groupId == loc.id)
                    .length,
                onTap: () {
                  setState(() {
                    _adminSelectedLocationId = loc.id as int;
                    _editMode = false;
                  });
                  _loadCharts();
                },
                c: c,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompanyContent(AppScheme c, dynamic currentLocation) {
    final sensors = _sensorsForCurrentLocation;
    // Фильтруем тревоги только по датчикам текущей локации.
    final locationSensorIds = sensors.map((s) => s.id).toSet();
    final alarms = widget.repo.alarms
        .where(
          (a) => a.sensorId != null && locationSensorIds.contains(a.sensorId),
        )
        .take(5)
        .toList();

    return Container(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _adminSelectedLocationId = null;
                  _editMode = false;
                }),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.border),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: c.textDim,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentLocation?.name ?? '',
                  style: TextStyle(
                    color: c.textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSchemaCard(c, currentLocation, sensors, canManage: true),
          const SizedBox(height: 14),
          if (sensors.isNotEmpty) ...[
            _SectionHeader(label: 'Датчики', count: sensors.length),
            const SizedBox(height: 8),
            Column(
              children: sensors
                  .take(8)
                  .map((s) => _SensorRow(sensor: s))
                  .toList(),
            ),
            const SizedBox(height: 14),
          ],
          if (alarms.isNotEmpty) ...[
            _SectionHeader(label: 'Последние события', count: alarms.length),
            const SizedBox(height: 8),
            Column(
              children: alarms
                  .map(
                    (alarm) => _AlarmRow(
                      alarm: alarm,
                      color: _alarmColor(alarm.status),
                      bgColor: _alarmBg(alarm.status),
                      label: _alarmLabel(alarm.status),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserView(AppScheme c) {
    final locations = widget.repo.locations;
    final currentLocation = locations.isNotEmpty
        ? locations[_selectedLocationIndex]
        : null;
    final sensors = _sensorsForCurrentLocation;
    // Фильтруем тревоги только по датчикам текущей локации.
    final locationSensorIds = sensors.map((s) => s.id).toSet();
    final alarms = widget.repo.alarms
        .where(
          (a) => a.sensorId != null && locationSensorIds.contains(a.sensorId),
        )
        .take(5)
        .toList();

    return Container(
      color: c.bg,
      // FIX: pull-to-refresh как fallback на случай если WS недоступен.
      // При pull — полный рефетч датчиков (GET /sensors/) включая актуальные pos_x/pos_y.
      child: RefreshIndicator(
        color: kCyan,
        onRefresh: () async {
          await widget.onRefresh();
          if (mounted) setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
          children: [
            Text(
              'Мониторинг',
              style: TextStyle(
                color: c.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 14),
            if (locations.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 6,
                  children: locations.asMap().entries.map((e) {
                    final selected = e.key == _selectedLocationIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedLocationIndex = e.key);
                        _loadCharts();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? c.cyan.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? c.cyan.withOpacity(0.6)
                                : c.border,
                          ),
                        ),
                        child: Text(
                          e.value.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected ? c.cyan : c.textDim,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (currentLocation?.imageUrl != null) ...[
              _buildSchemaCard(c, currentLocation, sensors, canManage: false),
              const SizedBox(height: 14),
            ],
            if (sensors.isNotEmpty) ...[
              _SectionHeader(label: 'Датчики', count: sensors.length),
              const SizedBox(height: 8),
              Column(
                children: sensors
                    .take(8)
                    .map((s) => _SensorRow(sensor: s))
                    .toList(),
              ),
              const SizedBox(height: 14),
            ],
            if (alarms.isNotEmpty) ...[
              _SectionHeader(label: 'Последние события', count: alarms.length),
              const SizedBox(height: 8),
              Column(
                children: alarms
                    .map(
                      (alarm) => _AlarmRow(
                        alarm: alarm,
                        color: _alarmColor(alarm.status),
                        bgColor: _alarmBg(alarm.status),
                        label: _alarmLabel(alarm.status),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ), // RefreshIndicator
    );
  }

  /// Карточка мнемосхемы: просмотр с [InteractiveViewer] или редактирование [_EditableSchema].
  Widget _buildSchemaCard(
    AppScheme c,
    dynamic currentLocation,
    List<SensorModel> sensors, {
    required bool canManage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _editMode ? c.accent.withOpacity(0.6) : c.border,
          width: _editMode ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: _editMode
                ? _EditableSchema(
                    key: _schemaKey,
                    imageUrl: currentLocation?.imageUrl != null
                        ? _resolveImageUrl(
                            currentLocation!.imageUrl!,
                            widget.repo.baseUrl,
                          )
                        : null,
                    sensors: sensors,
                    onPanUpdate: _onSensorPanUpdate,
                  )
                : currentLocation?.imageUrl != null
                ? _SchemaViewport(
                    key: _schemaKey,
                    imageUrl: _resolveImageUrl(
                      currentLocation!.imageUrl!,
                      widget.repo.baseUrl,
                    ),
                    sensors: sensors,
                    transformCtrl: _transformCtrl,
                    textDim: c.textDim,
                    isDark: c.isDark,
                  )
                : Container(
                    height: 200,
                    color: c.isDark ? const Color(0xFF060E0F) : c.card2,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 36, color: c.textDim),
                        const SizedBox(height: 8),
                        Text(
                          canManage
                              ? 'Нажмите «↑ план» чтобы загрузить мнемосхему'
                              : 'Мнемосхема не загружена',
                          style: TextStyle(color: c.textDim, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
          if (_editMode || (canManage && currentLocation != null))
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(9),
              ),
              child: Container(
                color: c.card2,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (_editMode) ...[
                      Icon(Icons.open_with, size: 13, color: c.accent),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Тащите датчики, затем нажмите ✓',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _cancelEditMode,
                        child: _SchemaBtn(label: '✕ отмена', color: c.red),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _confirmEditMode,
                        child: _SchemaBtn(label: '✓ сохранить', color: c.green),
                      ),
                    ] else ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showUploadPlanDialog(
                          currentLocation!.id as int,
                          currentLocation.name as String,
                        ),
                        child: _SchemaBtn(label: '↑ план', color: c.cyan),
                      ),
                      // FIX: кнопка перетаскивания датчиков доступна только admin.
                      // Для editor/viewer позиции readonly — сервер вернёт 403 на /position.
                      if (_isAdmin) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _enterEditMode,
                          child: _SchemaBtn(
                            label: '✎ датчики',
                            color: c.accent,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Плитка компании ───────────────────────────────────────────────────────────
