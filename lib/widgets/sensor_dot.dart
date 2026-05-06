import 'package:flutter/material.dart';
import '../models/sensor_model.dart';
import '../theme/app_colors.dart';

class SensorDot extends StatelessWidget { // класс для отображения точки датчика
  const SensorDot({super.key, required this.state, this.sensor}); // конструктор класса

  final SensorState state; // состояние датчика
  // Если передан sensor — показываем карточку с данными (для мнемосхемы).
  // Если null — показываем только цветную точку (для списка датчиков).
  final dynamic sensor; // SensorModel, но без циклического импорта не нужен тип

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state); // цвет точки

    if (sensor == null) {
      // Простая точка для списков
      return Container( // контейнер для точки
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle), // декор
      );
    }

    // Карточка датчика для мнемосхемы (компактная)
    return _SensorCard(sensor: sensor, borderColor: color); // карточка датчика
  }

  Color _stateColor(SensorState s) => switch (s) {
        SensorState.normal   => const Color(0xFF00E676), // зеленый цвет
        SensorState.warning  => const Color(0xFFFF9800), // оранжевый цвет  
        SensorState.critical => const Color(0xFFFF1744), // красный цвет
      };
}

class _SensorCard extends StatelessWidget { // класс для отображения карточки датчика
  const _SensorCard({required this.sensor, required this.borderColor}); // конструктор класса
  final dynamic sensor; // датчик
  final Color borderColor; // цвет границы

  @override
  Widget build(BuildContext context) { // функция для построения карточки датчика
    final isDark      = AppColors.of(context).isDark; // признак тёмной темы
    final name        = (sensor.name as String?) ?? ''; // название датчика
    final temperature = (sensor.temperature as double?) ?? 0.0; // температура
    final humidity    = (sensor.humidity    as double?) ?? 0.0; // влажность

    // Сокращаем имя датчика если оно длинное
    final shortName = name.length > 8 ? '${name.substring(0, 7)}…' : name; // сокращенное название датчика

    // В светлой теме используем белый непрозрачный фон вместо тёмного
    final bgColor = isDark
        ? const Color(0xDD0E1A1C) // тёмный фон карточки для тёмной темы
        : const Color(0xF0FFFFFF); // белый фон карточки для светлой темы

    // В светлой теме текст данных тёмный для читаемости
    final dataTextColor = isDark
        ? const Color(0xFFE0E0E0) // светлый текст для тёмной темы
        : const Color(0xFF1A2A30); // тёмный текст для светлой темы

    return Container( // контейнер для карточки датчика
      constraints: const BoxConstraints(minWidth: 42, maxWidth: 62), // ограничения для карточки датчика
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // отступы для карточки датчика
      decoration: BoxDecoration(
        color: bgColor, // цвет карточки датчика (зависит от темы)
        borderRadius: BorderRadius.circular(5), // закругление углов карточки датчика
        border: Border.all(color: borderColor, width: 1.0), // граница карточки датчика
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.28), // цвет тени карточки датчика
            blurRadius: 4, // размытие тени карточки датчика
            spreadRadius: 0, // распространение тени карточки датчика
          ),
        ], // тень карточки датчика
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // размер контейнера
        crossAxisAlignment: CrossAxisAlignment.center, // выравнивание по центру 
        children: [
          Text(
            shortName, // название датчика
            style: TextStyle(
              color: borderColor, // цвет текста (цвет состояния датчика)
              fontSize: 8, // размер текста
              fontWeight: FontWeight.w700, // жирность текста
              height: 1.1, // высота текста
            ), // стиль текста
            textAlign: TextAlign.center, // выравнивание по центру
            maxLines: 1, // максимальное количество строк
            overflow: TextOverflow.clip, // переполнение текста
          ),
          const SizedBox(height: 1), // отступ
          Text(
            '${temperature.toStringAsFixed(1)}°/${humidity.toStringAsFixed(0)}%', // температура и влажность
            style: TextStyle(
              color: dataTextColor, // цвет текста (зависит от темы)
              fontSize: 8, // размер текста
              fontWeight: FontWeight.w500, // жирность текста
              height: 1.1, // высота текста
            ), // стиль текста
            textAlign: TextAlign.center, // выравнивание по центру
          ),
        ],
      ),
    );
  }
}