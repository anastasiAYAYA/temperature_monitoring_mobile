import 'package:flutter/material.dart';
import '../models/sensor_model.dart';
import '../theme/app_colors.dart';

class SensorDot extends StatelessWidget {
  const SensorDot({super.key, required this.state, this.sensor});

  final SensorState state;
  // Если передан sensor — показываем карточку с данными (для мнемосхемы).
  // Если null — показываем только цветную точку (для списка датчиков).
  final dynamic sensor; // SensorModel, но без циклического импорта не нужен тип

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);

    if (sensor == null) {
      // Простая точка для списков
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    // Карточка датчика для мнемосхемы (компактная)
    return _SensorCard(sensor: sensor, borderColor: color);
  }

  Color _stateColor(SensorState s) => switch (s) {
        SensorState.normal   => const Color(0xFF00E676),
        SensorState.warning  => const Color(0xFFFF9800),
        SensorState.critical => const Color(0xFFFF1744),
      };
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({required this.sensor, required this.borderColor});
  final dynamic sensor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final name        = (sensor.name as String?) ?? '';
    final temperature = (sensor.temperature as double?) ?? 0.0;
    final humidity    = (sensor.humidity    as double?) ?? 0.0;

    // Сокращаем имя датчика если оно длинное
    final shortName = name.length > 8 ? '${name.substring(0, 7)}…' : name;

    return Container(
      constraints: const BoxConstraints(minWidth: 42, maxWidth: 62),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xDD0E1A1C),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.28),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            shortName,
            style: TextStyle(
              color: borderColor,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
          const SizedBox(height: 1),
          Text(
            '${temperature.toStringAsFixed(1)}°/${humidity.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 8,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}