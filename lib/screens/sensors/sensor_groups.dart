part of '../sensors_screen.dart';

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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final isAdmin = widget.repo.role == UserRole.admin;

    // Датчики без блока управления
    final freeSensors = widget.sensors
        .where((s) => s.controlUnitId == null)
        .toList();

    final totalCount = widget.sensors.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: sch.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sch.isDark ? sch.border : sch.cyan.withOpacity(0.20),
        ),
        boxShadow: sch.isDark
            ? null
            : [
                BoxShadow(
                  color: sch.cyan.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        children: [
          // ── Заголовок локации ──────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sch.cyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.location.name,
                      style: TextStyle(
                        color: sch.textMain,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '$totalCount датч.',
                    style: TextStyle(color: sch.textDim, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: sch.textDim,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Container(height: 1, color: sch.border),

            // ── Блоки управления ───────────────────────────────────────────
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
                // ЦБУ всегда закрыт при открытии локации — раскрывается вручную.
                initiallyExpanded: false,
              );
            }),

            // ── Датчики без блока управления ──────────────────────────────
            // Для админа показываем их только если нет ЦБУ совсем,
            // либо показываем всегда для остальных ролей.
            if (!isAdmin || widget.controlUnits.isEmpty)
              ...freeSensors.mapIndexed(
                (i, sensor) => _SensorRow(
                  sensor: sensor,
                  repo: widget.repo,
                  onTap: () => widget.onSensorTap(sensor),
                  isLast: i == freeSensors.length - 1,
                  indent: false,
                ),
              ),

            // Для админа: свободные датчики (без ЦБУ) показываем отдельным блоком
            if (isAdmin &&
                widget.controlUnits.isNotEmpty &&
                freeSensors.isNotEmpty)
              _FreeSensorsGroup(
                sensors: freeSensors,
                onSensorTap: widget.onSensorTap,
                repo: widget.repo,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Группа датчиков без ЦБУ (только для admin, когда есть ЦБУ в локации) ─────

class _FreeSensorsGroup extends StatefulWidget {
  const _FreeSensorsGroup({
    required this.sensors,
    required this.onSensorTap,
    required this.repo,
  });
  final List<SensorModel> sensors;
  final void Function(SensorModel) onSensorTap;
  final AppRepository repo;

  @override
  State<_FreeSensorsGroup> createState() => _FreeSensorsGroupState();
}

class _FreeSensorsGroupState extends State<_FreeSensorsGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: sch.isDark ? sch.card2 : sch.greenBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sch.isDark ? sch.border : sch.green.withOpacity(0.22),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.sensors, color: sch.green, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Без блока управления',
                      style: TextStyle(
                        color: sch.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.sensors.length} датч.',
                    style: TextStyle(color: sch.textDim, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: sch.textDim,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(height: 1, color: sch.border),
            ...widget.sensors.mapIndexed(
              (i, sensor) => _SensorRow(
                sensor: sensor,
                repo: widget.repo,
                onTap: () => widget.onSensorTap(sensor),
                isLast: i == widget.sensors.length - 1,
                indent: true,
              ),
            ),
          ],
          const SizedBox(height: 6),
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
    this.initiallyExpanded = true,
  });
  final Map<String, dynamic> unit;
  final List<SensorModel> sensors;
  final void Function(SensorModel) onSensorTap;
  final AppRepository repo;

  /// false = датчики скрыты при открытии (режим admin)
  final bool initiallyExpanded;

  @override
  State<_ControlUnitGroup> createState() => _ControlUnitGroupState();
}

class _ControlUnitGroupState extends State<_ControlUnitGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  Color _gsmColor(AppScheme sch, int bars) => switch (bars) {
    5 => sch.green,
    4 => sch.green,
    3 => sch.green,
    2 => sch.orange,
    1 => sch.red,
    _ => sch.textDim,
  };

  Color _batteryColor(AppScheme sch, bool isAc, int? level) {
    if (isAc) return sch.green;
    if (level == null) return sch.textDim;
    if (level >= 50) return sch.green;
    if (level >= 25) return sch.orange;
    return sch.red;
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final isOnline = widget.unit['is_online'] as bool? ?? false;
    final unitName = widget.unit['name'] as String? ?? '—';

    final refSensor = widget.sensors.isNotEmpty ? widget.sensors.first : null;
    final gsmSignal = refSensor?.gsmSignal;
    final gsmBars = refSensor?.gsmBars ?? 0;
    final simBalance = refSensor?.simBalance;
    final isAc = refSensor?.isAcPowered ?? false;
    final battery = refSensor?.batteryLevel;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: sch.isDark ? sch.card2 : sch.yellowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sch.isDark ? sch.border : sch.accent.withOpacity(0.24),
        ),
      ),
      child: Column(
        children: [
          // ── Заголовок блока ────────────────────────────────────────────
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOnline ? sch.greenBg : sch.redBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isOnline
                                ? sch.green.withOpacity(0.3)
                                : sch.red.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? sch.green : sch.red,
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
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: sch.textDim,
                        size: 16,
                      ),
                    ],
                  ),
                  // ── GSM / SIM / батарея ──────────────────────────────────
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
                            color: simBalance < 50 ? sch.red : sch.textDim,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_expanded && widget.sensors.isNotEmpty) ...[
            Container(height: 1, color: sch.border),
            ...widget.sensors.mapIndexed(
              (i, sensor) => _SensorRow(
                sensor: sensor,
                repo: widget.repo,
                onTap: () => widget.onSensorTap(sensor),
                isLast: i == widget.sensors.length - 1,
                indent: true,
              ),
            ),
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
    if (widget.sensor.temperature != 0.0 || widget.sensor.humidity != 0.0) {
      _temp = widget.sensor.temperature;
      _hum = widget.sensor.humidity;
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
          _hum = live.humidity;
        });
      }
    } catch (_) {}
  }

  Color _batteryColor(AppScheme sch, bool isAc, int? level) {
    if (isAc) return sch.green;
    if (level == null) return sch.textDim;
    if (level >= 50) return sch.green;
    if (level >= 25) return sch.orange;
    return sch.red;
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final sensor = widget.sensor;
    final stateColor = switch (sensor.state) {
      SensorState.normal => sch.green,
      SensorState.warning => sch.orange,
      SensorState.critical => sch.red,
    };

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(widget.indent ? 20 : 14, 11, 14, 11),
        decoration: BoxDecoration(
          color: sch.isDark
              ? Colors.transparent
              : stateColor.withOpacity(widget.indent ? 0.035 : 0.025),
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
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: sch.accent,
                                strokeWidth: 1.5,
                              ),
                            ),
                      _hum != null
                          ? Text(
                              '${_hum!.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: sch.cyan,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : const SizedBox.shrink(),
                      _MiniChip(
                        label: sensor.isAcPowered
                            ? '~220В'
                            : '${sensor.batteryLevel ?? '—'}%',
                        color: _batteryColor(
                          sch,
                          sensor.isAcPowered,
                          sensor.batteryLevel,
                        ),
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
