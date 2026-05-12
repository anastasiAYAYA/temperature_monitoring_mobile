part of '../dashboard_screen.dart';

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
    SensorState.normal => c.green,
    SensorState.warning => c.orange,
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
    final humPoints = s.humidityPoints;
    final hasChart = _showTemp ? tempPoints.isNotEmpty : humPoints.isNotEmpty;
    final chartColor = _showTemp ? c.accent : c.cyan;
    final chartPoints = _showTemp ? tempPoints : humPoints;
    final chartUnit = _showTemp ? '°C' : '%';
    final wMin = _showTemp ? s.warningMinTemp : s.warningMinHum;
    final wMax = _showTemp ? s.warningMaxTemp : s.warningMaxHum;
    final aMin = _showTemp ? s.alarmMinTemp : s.alarmMinHum;
    final aMax = _showTemp ? s.alarmMaxTemp : s.alarmMaxHum;

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
                                        blurRadius: 5,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                color: c.textMain,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _MetricChip(
                            value: '${s.temperature.toStringAsFixed(1)}°C',
                            color: c.accent,
                          ),
                          const SizedBox(width: 4),
                          _MetricChip(
                            value: '${s.humidity.toStringAsFixed(1)}%',
                            color: c.cyan,
                          ),
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
                            style: TextStyle(color: c.textDim, fontSize: 12),
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
                            vertical: 8,
                            horizontal: 4,
                          ),
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
                                color: c.textMain,
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
