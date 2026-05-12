part of '../sensors_screen.dart';

class _LiveReadingsCard extends StatelessWidget {
  const _LiveReadingsCard({
    required this.temp,
    required this.hum,
    required this.timestamp,
    required this.loading,
    required this.isOnline,
  });
  final double? temp;
  final double? hum;
  final DateTime? timestamp;
  final bool loading;
  final bool isOnline;

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
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? kGreen : sch.textDim,
                            boxShadow: isOnline
                                ? [
                                    BoxShadow(
                                      color: kGreen.withOpacity(0.5),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'обн. ${_fmtTime(timestamp)}',
                          style: TextStyle(fontSize: 10, color: sch.textDim),
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
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: sch.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sch.accent.withOpacity(0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.thermostat_outlined,
                                    color: sch.accent,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Температура',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: sch.textDim,
                                    ),
                                  ),
                                ],
                              ),
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
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: kCyan.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kCyan.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.water_drop_outlined,
                                    color: kCyan,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Влажность',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: sch.textDim,
                                    ),
                                  ),
                                ],
                              ),
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
          if (extra != null) ...[const SizedBox(height: 5), extra!],
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
    final color = level < 25
        ? kRed
        : level < 50
        ? kOrange
        : kGreen;
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
    final color = bars >= 4
        ? kGreen
        : bars == 3
        ? kGreen
        : bars == 2
        ? kOrange
        : kRed;
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
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: AppColors.of(context).textDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
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
              color: active
                  ? kCyan.withOpacity(0.15)
                  : AppColors.of(context).card2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active
                    ? kCyan.withOpacity(0.5)
                    : AppColors.of(context).border,
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
          color: selected
              ? color.withOpacity(0.15)
              : AppColors.of(context).card2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? color.withOpacity(0.5)
                : AppColors.of(context).border,
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
              decimal: true,
              signed: signed,
            ),
            readOnly: readOnly,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DarkField(
            controller: maxCtrl,
            label: 'Max',
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: signed,
            ),
            readOnly: readOnly,
          ),
        ),
      ],
    );
  }
}

// ── Тёмные компоненты (аналогичны settings_screen) ───────────────────────────
