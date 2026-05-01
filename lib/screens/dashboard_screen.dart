import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:file_picker/file_picker.dart';

import '../models/alarm_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../widgets/line_chart.dart';
import '../widgets/sensor_dot.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen(
      {super.key, required this.repo, required this.onRefresh});
  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppScheme get c => AppColors.of(context);
  int _selectedLocationIndex = 0;

  // Для admin: выбранная компания (null = ни одна не выбрана)
  int? _adminSelectedLocationId;

  // Поиск компаний для admin
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  final GlobalKey _schemaKey = GlobalKey();

  // Контроллер трансформации для InteractiveViewer (зум + пан)
  final TransformationController _transformCtrl = TransformationController();

  // Режим редактирования позиций датчиков
  bool _editMode = false;
  // Временные позиции датчиков (оригиналы до начала редактирования)
  final Map<int, (double, double)> _draftPositions = {};

  bool get _isAdmin => widget.repo.role == UserRole.admin;

  @override
  void dispose() {
    _transformCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCharts());
  }

  Future<void> _loadCharts() async {
    final sensors = _sensorsForCurrentLocation;
    for (final s in sensors) {
      await widget.repo.loadHistory(s.id, 'День');
    }
    if (mounted) setState(() {});
  }

  // ── Диалог создания локации ───────────────────────────────────────────────

  Future<void> _showCreateLocationDialog() async {
    final nameCtrl = TextEditingController();
    PlatformFile? pickedFile;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _DarkDialog(
          title: 'Новая компания',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DarkField(controller: nameCtrl, label: 'Название компании'),
              const SizedBox(height: 14),
              if (pickedFile != null) ...[
                Container(
                  height: 60,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 18, color: c.cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(pickedFile!.name,
                            style: TextStyle(fontSize: 12, color: c.textDim),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _OutlineBtn(
                      label: pickedFile == null ? 'Выбрать план' : 'Сменить',
                      color: c.cyan,
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
                      onPressed: () =>
                          setDialogState(() => pickedFile = null),
                    ),
                  ],
                ],
              ),
              if (pickedFile == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('JPG, PNG или SVG, до 50 МБ',
                      style: TextStyle(fontSize: 11, color: c.textDim)),
                ),
            ],
          ),
          actions: [
            _DarkTextBtn(label: 'Отмена', onTap: () => Navigator.pop(context)),
            _DarkFilledBtn(
              label: 'Создать',
              onTap: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Введите название компании')));
                  return;
                }
                final createErr =
                    await widget.repo.createLocation(name: name);
                if (!context.mounted) return;
                if (createErr != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(createErr)));
                  return;
                }
                if (pickedFile != null) {
                  await widget.onRefresh();
                  if (!context.mounted) return;
                  final newLoc = widget.repo.locations.isNotEmpty
                      ? widget.repo.locations.last
                      : null;
                  if (newLoc != null) {
                    final uploadErr =
                        await widget.repo.uploadLocationPlan(
                      locationId: newLoc.id,
                      fileBytes: pickedFile!.bytes!,
                      mimeType: _mimeType(pickedFile!.name),
                      fileName: pickedFile!.name,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(uploadErr == null
                          ? 'Компания создана с планом'
                          : 'Компания создана, план не загрузился: $uploadErr'),
                    ));
                    await widget.onRefresh();
                    return;
                  }
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Компания создана')));
                await widget.onRefresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Диалог загрузки плана ─────────────────────────────────────────────────

  Future<void> _showUploadPlanDialog(int locationId, String locationName) async {
    PlatformFile? pickedFile;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => _DarkDialog(
          title: 'План для «$locationName»',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pickedFile != null) ...[
                Container(
                  height: 60,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 18, color: c.cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(pickedFile!.name,
                            style: TextStyle(fontSize: 12, color: c.textDim),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _OutlineBtn(
                label: pickedFile == null ? 'Выбрать файл' : 'Сменить',
                color: c.cyan,
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
              Text('JPG, PNG или SVG, до 50 МБ',
                  style: TextStyle(fontSize: 11, color: c.textDim)),
            ],
          ),
          actions: [
            _DarkTextBtn(label: 'Отмена', onTap: () => Navigator.pop(context)),
            _DarkFilledBtn(
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
                          SnackBar(content: Text(err ?? 'План загружен')));
                      if (err == null) await widget.onRefresh();
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ── Вспомогательное ───────────────────────────────────────────────────────

  String _mimeType(String path) {
    final l = path.toLowerCase();
    if (l.endsWith('.png')) return 'image/png';
    if (l.endsWith('.svg')) return 'image/svg+xml';
    return 'image/jpeg';
  }

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

  void _onSensorPanUpdate(SensorModel sensor, Offset delta) {
    final box = _schemaKey.currentContext?.findRenderObject() as RenderBox?;
    final schemaW = box?.size.width  ?? 300.0;
    final schemaH = box?.size.height ?? 300.0;

    setState(() {
      sensor.x = (sensor.x + delta.dx / schemaW).clamp(0.0, 1.0);
      sensor.y = (sensor.y + delta.dy / schemaH).clamp(0.0, 1.0);
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

  Future<void> _confirmEditMode() async {
    final changed = widget.repo.sensors.where(
      (s) {
        final orig = _draftPositions[s.id];
        if (orig == null) return false;
        return (s.x - orig.$1).abs() > 0.002 || (s.y - orig.$2).abs() > 0.002;
      },
    ).toList();

    setState(() => _editMode = false);
    _draftPositions.clear();

    if (changed.isEmpty) return;

    final errors = <String>[];
    for (final s in changed) {
      final err = await widget.repo.updateSensorPosition(
        sensorId: s.id,
        posX: s.x,
        posY: s.y,
      );
      if (err != null) errors.add('${s.name}: $err');
    }

    if (!mounted) return;
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed.length == 1
                ? 'Позиция датчика сохранена'
                : 'Позиции ${changed.length} датчиков сохранены',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибки: ${errors.join(', ')}')),
      );
    }
  }

  String _resolveImageUrl(String imageUrl, String baseUrl) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    return '${baseUrl.replaceAll(RegExp(r'/api/v\d+$'), '')}$imageUrl';
  }

  Color _alarmColor(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => c.red,
        AlarmStatus.acknowledged => c.orange,
        AlarmStatus.resolved     => c.green,
      };

  String _alarmLabel(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => 'НОВОЕ',
        AlarmStatus.acknowledged => 'В РАБОТЕ',
        AlarmStatus.resolved     => 'РЕШЕНО',
      };

  Color _alarmBg(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => c.redBg,
        AlarmStatus.acknowledged => const Color(0xFF2A1E00),
        AlarmStatus.resolved     => const Color(0xFF0E2A1E),
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(primary: c.cyan),
      ),
      child: _isAdmin ? _buildAdminView(c) : _buildUserView(c),
    );
  }

  // ── Вид администратора ────────────────────────────────────────────────────

  Widget _buildAdminView(AppScheme c) {
    final locations = widget.repo.locations;

    // Фильтрованный список по поисковому запросу
    final filtered = _searchQuery.isEmpty
        ? locations
        : locations
            .where((l) =>
                l.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    // Сортировка по алфавиту
    final sorted = List.of(filtered)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Если компания выбрана — показываем её содержимое
    if (_adminSelectedLocationId != null) {
      final loc = locations
          .where((l) => l.id == _adminSelectedLocationId)
          .firstOrNull;
      return _buildCompanyContent(c, loc);
    }

    // Иначе — экран выбора компании
    return Container(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Заголовок ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Компании',
                    style: TextStyle(
                      color: Colors.white,
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
                        horizontal: 10, vertical: 6),
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

          // ── Поиск ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: Colors.white, fontSize: 14),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

          // ── Алфавитный список ─────────────────────────────────────────────
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_outlined,
                            size: 48, color: c.textDim),
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
    // Группируем по первой букве
    final Map<String, List<dynamic>> groups = {};
    for (final loc in sorted) {
      final letter = loc.name.isNotEmpty
          ? loc.name[0].toUpperCase()
          : '#';
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
            // Буква-разделитель
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
            ...items.map((loc) => _CompanyTile(
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
                )),
          ],
        );
      },
    );
  }

  // ── Содержимое выбранной компании (для admin) ─────────────────────────────

  Widget _buildCompanyContent(AppScheme c, dynamic currentLocation) {
    final sensors = _sensorsForCurrentLocation;
    final alarms  = widget.repo.alarms.take(5).toList();

    return Container(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          // ── Навигация назад + название ─────────────────────────────────────
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
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 14, color: c.textDim),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentLocation?.name ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Мнемосхема ────────────────────────────────────────────────────
          _buildSchemaCard(c, currentLocation, sensors, canManage: true),

          const SizedBox(height: 14),

          // ── Датчики ───────────────────────────────────────────────────────
          if (sensors.isNotEmpty) ...[
            _SectionHeader(label: 'Датчики', count: sensors.length),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Column(
                children:
                    sensors.take(8).map((s) => _SensorRow(sensor: s)).toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Последние тревоги ─────────────────────────────────────────────
          if (alarms.isNotEmpty) ...[
            _SectionHeader(
                label: 'Последние события', count: alarms.length),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Column(
                children: alarms
                    .map((alarm) => _AlarmRow(
                          alarm: alarm,
                          color: _alarmColor(alarm.status),
                          bgColor: _alarmBg(alarm.status),
                          label: _alarmLabel(alarm.status),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Вид обычного пользователя (editor / viewer) ───────────────────────────

  Widget _buildUserView(AppScheme c) {
    final locations = widget.repo.locations;
    final currentLocation =
        locations.isNotEmpty ? locations[_selectedLocationIndex] : null;
    final sensors = _sensorsForCurrentLocation;
    final alarms  = widget.repo.alarms.take(5).toList();

    return Container(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          // ── Заголовок ──────────────────────────────────────────────────────
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Мониторинг',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Переключатель локаций ─────────────────────────────────────────
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
                          horizontal: 14, vertical: 6),
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

          // ── Мнемосхема ────────────────────────────────────────────────────
          // editor и viewer не могут менять план и позиции датчиков
          _buildSchemaCard(
            c,
            currentLocation,
            sensors,
            canManage: false,
          ),

          const SizedBox(height: 14),

          // ── Датчики ───────────────────────────────────────────────────────
          if (sensors.isNotEmpty) ...[
            _SectionHeader(label: 'Датчики', count: sensors.length),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Column(
                children:
                    sensors.take(8).map((s) => _SensorRow(sensor: s)).toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Последние тревоги ─────────────────────────────────────────────
          if (alarms.isNotEmpty) ...[
            _SectionHeader(
                label: 'Последние события', count: alarms.length),
            const SizedBox(height: 8),
            DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Column(
                children: alarms
                    .map((alarm) => _AlarmRow(
                          alarm: alarm,
                          color: _alarmColor(alarm.status),
                          bgColor: _alarmBg(alarm.status),
                          label: _alarmLabel(alarm.status),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Карточка мнемосхемы (общая для admin и user) ──────────────────────────

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(9)),
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
                      )
                    : Container(
                        height: 200,
                        color: const Color(0xFF060E0F),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.map_outlined,
                                size: 36, color: c.textDim),
                            const SizedBox(height: 8),
                            Text(
                              canManage
                                  ? 'Нажмите «↑ план» чтобы загрузить мнемосхему'
                                  : 'Мнемосхема не загружена',
                              style: TextStyle(
                                  color: c.textDim, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
          ),

          // Панель кнопок под картинкой
          if (_editMode || (canManage && currentLocation != null))
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(9)),
              child: Container(
                color: c.card2,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      GestureDetector(
                        onTap: _cancelEditMode,
                        child:
                            _SchemaBtn(label: '✕ отмена', color: c.red),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _confirmEditMode,
                        child: _SchemaBtn(
                            label: '✓ сохранить', color: c.green),
                      ),
                    ] else ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showUploadPlanDialog(
                          currentLocation!.id as int,
                          currentLocation.name as String,
                        ),
                        child:
                            _SchemaBtn(label: '↑ план', color: c.cyan),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _enterEditMode,
                        child: _SchemaBtn(
                            label: '✎ датчики', color: c.accent),
                      ),
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

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.name,
    required this.sensorCount,
    required this.onTap,
    required this.c,
  });
  final String name;
  final int sensorCount;
  final VoidCallback onTap;
  final AppScheme c;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.cyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.cyan.withOpacity(0.25)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.business_outlined, size: 18, color: c.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sensorCount датч.',
                    style: TextStyle(fontSize: 11, color: c.textDim),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.textDim),
          ],
        ),
      ),
    );
  }
}

// ── Секционный заголовок ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.textDim,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: c.card2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              color: c.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Строка датчика (с графиком и переключателем темп/влажность) ───────────────

class _SensorRow extends StatefulWidget {
  const _SensorRow({required this.sensor});
  final SensorModel sensor;

  @override
  State<_SensorRow> createState() => _SensorRowState();
}

class _SensorRowState extends State<_SensorRow> {
  AppScheme get c => AppColors.of(context);
  bool _showTemp = true;

  SensorModel get s => widget.sensor;

  Color get _stateColor => switch (s.state) {
        SensorState.normal   => c.green,
        SensorState.warning  => c.orange,
        SensorState.critical => c.red,
      };

  Color get _powerColor {
    if (s.isAcPowered) return c.green;
    final b = s.batteryLevel;
    if (b == null) return c.textDim;
    if (b >= 50) return c.green;
    if (b >= 25) return c.orange;
    return c.red;
  }

  String get _powerLabel {
    if (s.isAcPowered) return '~220В';
    final b = s.batteryLevel;
    return b != null ? '$b%' : '—';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tempPoints = s.points;
    final humPoints  = s.humidityPoints;
    final hasChart   = _showTemp ? tempPoints.isNotEmpty : humPoints.isNotEmpty;

    final chartColor  = _showTemp ? c.accent : c.cyan;
    final chartPoints = _showTemp ? tempPoints : humPoints;
    final chartUnit   = _showTemp ? '°C' : '%';
    final wMin  = _showTemp ? s.warningMinTemp  : s.warningMinHum;
    final wMax  = _showTemp ? s.warningMaxTemp  : s.warningMaxHum;
    final aMin  = _showTemp ? s.alarmMinTemp    : s.alarmMinHum;
    final aMax  = _showTemp ? s.alarmMaxTemp    : s.alarmMaxHum;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: _stateColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: s.isOnline ? c.green : c.red,
                              boxShadow: s.isOnline
                                  ? [
                                      BoxShadow(
                                          color: c.green.withOpacity(0.5),
                                          blurRadius: 5)
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _MetricChip(
                              value: '${s.temperature.toStringAsFixed(1)}°C',
                              color: c.accent),
                          const SizedBox(width: 4),
                          _MetricChip(
                              value: '${s.humidity.toStringAsFixed(1)}%',
                              color: c.cyan),
                          const SizedBox(width: 4),
                          _MetricChip(value: _powerLabel, color: _powerColor),
                        ],
                      ),

                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ChartTab(
                            label: 'Температура',
                            selected: _showTemp,
                            color: c.accent,
                            onTap: () => setState(() => _showTemp = true),
                          ),
                          const SizedBox(width: 6),
                          _ChartTab(
                            label: 'Влажность',
                            selected: !_showTemp,
                            color: c.cyan,
                            onTap: () => setState(() => _showTemp = false),
                          ),
                          const Spacer(),
                          Text(
                            _showTemp
                                ? '${s.temperature.toStringAsFixed(1)}°C'
                                : '${s.humidity.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: chartColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      if (!hasChart)
                        Container(
                          height: 80,
                          alignment: Alignment.center,
                          child: Text(
                            'Нет данных за 24 часа',
                            style:
                                TextStyle(color: c.textDim, fontSize: 12),
                          ),
                        )
                      else
                        SizedBox(
                          height: 110,
                          child: LineChartWidget(
                            points: chartPoints,
                            color: chartColor,
                            unit: chartUnit,
                            warningMin: wMin,
                            warningMax: wMax,
                            alarmMin: aMin,
                            alarmMax: aMax,
                          ),
                        ),

                      if (hasChart) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: c.card2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatCell(
                                label: 'Мин',
                                value:
                                    '${chartPoints.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}$chartUnit',
                                color: c.cyan,
                              ),
                              _VertDiv(),
                              _StatCell(
                                label: 'Среднее',
                                value:
                                    '${(chartPoints.reduce((a, b) => a + b) / chartPoints.length).toStringAsFixed(1)}$chartUnit',
                                color: Colors.white,
                              ),
                              _VertDiv(),
                              _StatCell(
                                label: 'Макс',
                                value:
                                    '${chartPoints.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}$chartUnit',
                                color: chartColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartTab extends StatelessWidget {
  const _ChartTab({
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
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? color.withOpacity(0.55) : c.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? color : c.textDim,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 9,
              color: c.textDim,
              letterSpacing: 0.4,
            )),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            )),
      ],
    );
  }
}

class _VertDiv extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(width: 1, height: 22, color: c.border);
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.value, required this.color});
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        value,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Строка тревоги ────────────────────────────────────────────────────────────

class _AlarmRow extends StatelessWidget {
  const _AlarmRow({
    required this.alarm,
    required this.color,
    required this.bgColor,
    required this.label,
  });
  final AlarmModel alarm;
  final Color color;
  final Color bgColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alarm.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (alarm.description.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                alarm.description,
                                style: TextStyle(
                                    fontSize: 11, color: c.textDim),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: color.withOpacity(0.4)),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Кнопка на мнемосхеме ──────────────────────────────────────────────────────

class _SchemaBtn extends StatelessWidget {
  const _SchemaBtn({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Диалоги ───────────────────────────────────────────────────────────────────

class _DarkDialog extends StatelessWidget {
  const _DarkDialog(
      {required this.title, required this.content, required this.actions});
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16)),
      content: content,
      actions: actions,
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textDim, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.cyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn(
      {required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DarkTextBtn extends StatelessWidget {
  const _DarkTextBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: c.textDim, fontSize: 13)),
    );
  }
}

class _DarkFilledBtn extends StatelessWidget {
  const _DarkFilledBtn({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: c.cyan,
        foregroundColor: Colors.black,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child:
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

// ── Режим просмотра: картинка по ширине, высота по аспекту, датчики поверх ───

class _SchemaViewport extends StatefulWidget {
  const _SchemaViewport({
    super.key,
    required this.imageUrl,
    required this.sensors,
    required this.transformCtrl,
    required this.textDim,
  });

  final String imageUrl;
  final List<SensorModel> sensors;
  final TransformationController transformCtrl;
  final Color textDim;

  @override
  State<_SchemaViewport> createState() => _SchemaViewportState();
}

class _SchemaViewportState extends State<_SchemaViewport> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  void _resolveImageSize() {
    final stream =
        NetworkImage(widget.imageUrl).resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((info, _) {
      if (!mounted) return;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) setState(() => _aspectRatio = w / h);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width  = constraints.maxWidth;
        final ratio  = _aspectRatio ?? (16 / 9);
        final height = width / ratio;

        return SizedBox(
          width: width,
          height: height,
          child: InteractiveViewer(
            transformationController: widget.transformCtrl,
            minScale: 0.5,
            maxScale: 6.0,
            child: Stack(
              children: [
                Image.network(
                  widget.imageUrl,
                  width: width,
                  height: height,
                  fit: BoxFit.fill,
                  color: Colors.black.withOpacity(0.45),
                  colorBlendMode: BlendMode.darken,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text('Не удалось загрузить план',
                        style: TextStyle(
                            color: widget.textDim, fontSize: 12)),
                  ),
                ),
                ...widget.sensors.map(
                  (sensor) {
                    final px = sensor.x * width;
                    final py = sensor.y * height;
                    return Positioned(
                      left: px,
                      top: py,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, -0.5),
                        child:
                            SensorDot(state: sensor.state, sensor: sensor),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Мнемосхема в режиме редактирования ───────────────────────────────────────

class _EditableSchema extends StatefulWidget {
  const _EditableSchema({
    super.key,
    required this.imageUrl,
    required this.sensors,
    required this.onPanUpdate,
  });

  final String? imageUrl;
  final List<SensorModel> sensors;
  final void Function(SensorModel sensor, Offset delta) onPanUpdate;

  @override
  State<_EditableSchema> createState() => _EditableSchemaState();
}

class _EditableSchemaState extends State<_EditableSchema> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrl != null) _resolveImageSize();
  }

  void _resolveImageSize() {
    final stream =
        NetworkImage(widget.imageUrl!).resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((info, _) {
      if (!mounted) return;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) setState(() => _aspectRatio = w / h);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width  = constraints.maxWidth;
        final ratio  = _aspectRatio ?? (16 / 9);
        final height = width / ratio;

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Container(
                color: const Color(0xFF060E0F),
                width: width,
                height: height,
                child: widget.imageUrl != null
                    ? Image.network(
                        widget.imageUrl!,
                        fit: BoxFit.fill,
                        width: width,
                        height: height,
                        color: Colors.black.withOpacity(0.45),
                        colorBlendMode: BlendMode.darken,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text('Не удалось загрузить план',
                              style: TextStyle(
                                  color: c.textDim, fontSize: 12)),
                        ),
                      )
                    : Center(
                        child: Text('Мнемосхема не загружена',
                            style: TextStyle(
                                color: c.textDim, fontSize: 12)),
                      ),
              ),
              ...widget.sensors.map(
                (s) => _SmoothDraggableDot(
                  sensor: s,
                  schemaWidth: width,
                  schemaHeight: height,
                  onPanUpdate: (delta) => widget.onPanUpdate(s, delta),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Датчик с плавным перетаскиванием ─────────────────────────────────────────

class _SmoothDraggableDot extends StatefulWidget {
  const _SmoothDraggableDot({
    required this.sensor,
    required this.schemaWidth,
    required this.schemaHeight,
    required this.onPanUpdate,
  });
  final SensorModel sensor;
  final double schemaWidth;
  final double schemaHeight;
  final void Function(Offset delta) onPanUpdate;

  @override
  State<_SmoothDraggableDot> createState() => _SmoothDraggableDotState();
}

class _SmoothDraggableDotState extends State<_SmoothDraggableDot> {
  AppScheme get c => AppColors.of(context);
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Используем меньший размер карточки т.к. SensorDot стал компактнее
    const cardW = 62.0;
    const cardH = 36.0;

    final px = widget.sensor.x * widget.schemaWidth - cardW / 2;
    final py = widget.sensor.y * widget.schemaHeight - cardH / 2;

    return Positioned(
      left: px.clamp(0.0, widget.schemaWidth - cardW),
      top:  py.clamp(0.0, widget.schemaHeight - cardH),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) => widget.onPanUpdate(d.delta),
        onPanEnd: (_) => setState(() => _dragging = false),
        child: AnimatedScale(
          scale: _dragging ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_dragging)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color:
                          _stateColor(widget.sensor.state).withOpacity(0.15),
                    ),
                  ),
                ),
              SensorDot(state: widget.sensor.state, sensor: widget.sensor),
            ],
          ),
        ),
      ),
    );
  }

  Color _stateColor(SensorState s) => switch (s) {
        SensorState.normal   => c.green,
        SensorState.warning  => c.orange,
        SensorState.critical => c.red,
      };
}