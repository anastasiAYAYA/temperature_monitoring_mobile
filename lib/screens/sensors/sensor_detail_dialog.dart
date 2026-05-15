part of '../sensors_screen.dart';

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
  List<double> _humPoints = [];

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
  String _fmt(double? v) =>
      v != null ? v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1) : '';

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
    _liveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchLiveData(),
    );
    _historyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadHistory(),
    );
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _historyTimer?.cancel();
    _wMinTCtrl.dispose();
    _wMaxTCtrl.dispose();
    _aMinTCtrl.dispose();
    _aMaxTCtrl.dispose();
    _wMinHCtrl.dispose();
    _wMaxHCtrl.dispose();
    _aMinHCtrl.dispose();
    _aMaxHCtrl.dispose();
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
          _liveTemp = live.temperature;
          _liveHum = live.humidity;
          _liveTs = live.timestamp;
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
      await widget.repo
          .loadHistory(widget.sensor.id, _period)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Таймаут или ошибка сети — показываем "нет данных", не зависаем
    }
    if (mounted)
      setState(() {
        _loading = false;
        _tempPoints = List.of(widget.sensor.points);
        _humPoints = List.of(widget.sensor.humidityPoints);
      });
  }

  Future<void> _changePeriod(String p) async {
    if (!mounted) return;
    setState(() {
      _period = p;
      _loading = true;
    });
    try {
      await widget.repo
          .loadHistory(widget.sensor.id, p)
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (mounted)
      setState(() {
        _loading = false;
        _tempPoints = List.of(widget.sensor.points);
        _humPoints = List.of(widget.sensor.humidityPoints);
      });
  }

  Widget _buildChart() {
    final s = widget.sensor;
    final points = _showTemperature ? _tempPoints : _humPoints;
    final unit = _showTemperature ? '°C' : '%';
    final label = _showTemperature ? 'Температура' : 'Влажность';
    final color = _showTemperature
        ? AppColors.of(context).accent
        : AppColors.of(context).cyan;
    final warningMin = _showTemperature ? s.warningMinTemp : s.warningMinHum;
    final warningMax = _showTemperature ? s.warningMaxTemp : s.warningMaxHum;
    final alarmMin = _showTemperature ? s.alarmMinTemp : s.alarmMinHum;
    final alarmMax = _showTemperature ? s.alarmMaxTemp : s.alarmMaxHum;

    if (points.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.of(context).card2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: Text(
          'Нет данных ($label)',
          style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12),
        ),
      );
    }

    final minVal = points.reduce((a, b) => a < b ? a : b);
    final maxVal = points.reduce((a, b) => a > b ? a : b);
    final avg = points.reduce((a, b) => a + b) / points.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LineChartWidget(
          points: points,
          timestamps: widget.sensor.timestamps.isNotEmpty
              ? widget.sensor.timestamps
              : null,
          color: color,
          unit: unit,
          period: _period,
          warningMin: warningMin,
          warningMax: warningMax,
          alarmMin: alarmMin,
          alarmMax: alarmMax,
        ),
        const SizedBox(height: 8),
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
                label: 'МИН',
                value: '${minVal.toStringAsFixed(1)}$unit',
                color: AppColors.of(context).cyan,
              ),
              _VertDivider(),
              _StatCell(
                label: 'СРЕДНЕЕ',
                value: '${avg.toStringAsFixed(1)}$unit',
                color: AppColors.of(context).textMain,
              ),
              _VertDivider(),
              _StatCell(
                label: 'МАКС',
                value: '${maxVal.toStringAsFixed(1)}$unit',
                color: color,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 11,
              color: AppColors.of(context).textDim,
            ),
            const SizedBox(width: 4),
            Text(
              'Нажмите или проведите по графику',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.of(context).textDim,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        widget.repo.role == UserRole.admin ||
        widget.repo.role == UserRole.editor;

    return _DarkDialog(
      title: widget.sensor.name,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Live-показания (обновляются каждые 10 сек) ────────────────────
          _LiveReadingsCard(
            temp: _liveTemp,
            hum: _liveHum,
            timestamp: _liveTs,
            loading: _liveLoading,
            isOnline: widget.sensor.isOnline,
          ),
          const SizedBox(height: 12),
          _HardwareStatusCard(sensor: widget.sensor),
          const SizedBox(height: 16),
          const _SectionLabel(text: 'ПЕРИОД'),
          const SizedBox(height: 6),
          _PeriodTabs(selected: _period, onChanged: _changePeriod),
          const SizedBox(height: 12),
          Row(
            children: [
              _ChartToggleBtn(
                label: 'Температура',
                selected: _showTemperature,
                color: AppColors.of(context).accent,
                onTap: () => setState(() => _showTemperature = true),
              ),
              const SizedBox(width: 8),
              _ChartToggleBtn(
                label: 'Влажность',
                selected: !_showTemperature,
                color: AppColors.of(context).cyan,
                onTap: () => setState(() => _showTemperature = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.of(context).cyan,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            _buildChart(),
          const SizedBox(height: 20),
          const _SectionLabel(text: 'ПОРОГИ ТЕМПЕРАТУРЫ (°C)'),
          const SizedBox(height: 8),
          _ThresholdRow(
            label: 'Внимание',
            color: kOrange,
            minCtrl: _wMinTCtrl,
            maxCtrl: _wMaxTCtrl,
            signed: true,
            readOnly: !canEdit,
          ),
          const SizedBox(height: 6),
          _ThresholdRow(
            label: 'Тревога',
            color: kRed,
            minCtrl: _aMinTCtrl,
            maxCtrl: _aMaxTCtrl,
            signed: true,
            readOnly: !canEdit,
          ),
          const SizedBox(height: 20),
          const _SectionLabel(text: 'ПОРОГИ ВЛАЖНОСТИ (%)'),
          const SizedBox(height: 8),
          _ThresholdRow(
            label: 'Внимание',
            color: kOrange,
            minCtrl: _wMinHCtrl,
            maxCtrl: _wMaxHCtrl,
            readOnly: !canEdit,
          ),
          const SizedBox(height: 6),
          _ThresholdRow(
            label: 'Тревога',
            color: kRed,
            minCtrl: _aMinHCtrl,
            maxCtrl: _aMaxHCtrl,
            readOnly: !canEdit,
          ),
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

              if (wMinT == null ||
                  wMaxT == null ||
                  aMinT == null ||
                  aMaxT == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите корректные значения температуры'),
                  ),
                );
                return;
              }

              final err = await widget.repo.updateSensorThresholds(
                sensorId: widget.sensor.id,
                warningMinTemp: wMinT,
                warningMaxTemp: wMaxT,
                alarmMinTemp: aMinT,
                alarmMaxTemp: aMaxT,
                warningMinHum: wMinH,
                warningMaxHum: wMaxH,
                alarmMinHum: aMinH,
                alarmMaxHum: aMaxH,
              );

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(err ?? 'Пороги сохранены')),
              );
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
