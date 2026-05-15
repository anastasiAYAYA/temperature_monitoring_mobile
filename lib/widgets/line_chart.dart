import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const _kBorder = Color(0xFF19282B);
const _kTextDim = Color(0xFF7A8A8E);
const _kCard = Color(0xFF111C1F);
const _kWarning = Color(0xFFFFB300);
const _kAlarm = Color(0xFFFF5252);

// Линейный график с осями, метками и hover-подсказкой.
// [timestamps] — опциональный список DateTime, синхронизированный с [points].
// Если передан, ось X показывает время/дату, а hover показывает точное время.
class LineChartWidget extends StatefulWidget {
  // класс для построения линейного графика
  const LineChartWidget({
    super.key, // ключ для идентификации
    required this.points, // список точек
    this.timestamps, // список временных меток
    this.color, // цвет линии
    this.warningMin, // минимальное значение для предупреждения
    this.warningMax, // максимальное значение для предупреждения
    this.alarmMin, // минимальное значение для тревоги
    this.alarmMax, // максимальное значение для тревоги
    this.unit = '', // единица измерения
    this.period = 'День', // период
  });

  final List<double> points; // список точек
  final List<DateTime>? timestamps; // список временных меток
  final Color? color; // цвет линии
  final double? warningMin; // минимальное значение для предупреждения
  final double? warningMax; // максимальное значение для предупреждения
  final double? alarmMin; // минимальное значение для тревоги
  final double? alarmMax; // максимальное значение для тревоги
  final String unit; // единица измерения
  /// 'День' | 'Неделя' | 'Месяц' — влияет на формат меток оси X
  final String period; // период

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState(); // создание состояния
}

class _LineChartWidgetState extends State<LineChartWidget> {
  // состояние для линейного графика
  int? _hoverIndex; // индекс hover

  // Отступы под ось X и под ось Y
  static const double _padLeft = 44.0; // отступ слева
  static const double _padBottom = 28.0; // отступ снизу
  static const double _padTop = 12.0; // отступ сверху
  static const double _padRight =
      64.0; // отступ справа (место для меток порогов)

  int _indexFromDx(double dx, double chartW) {
    // функция для получения индекса из координаты x
    if (widget.points.length <= 1)
      return 0; // если точек меньше 1, то возвращаем 0
    final x = (dx - _padLeft).clamp(0.0, chartW); // координата x
    final step = chartW / (widget.points.length - 1); // шаг
    return (x / step).round().clamp(0, widget.points.length - 1); // индекс
  }

  void _onMove(Offset local, double totalW) {
    // функция для перемещения hover
    final chartW = totalW - _padLeft - _padRight; // ширина графика
    final idx = _indexFromDx(local.dx, chartW); // индекс
    if (_hoverIndex != idx)
      setState(() => _hoverIndex = idx); // установка индекса
  }

  void _onExit() =>
      setState(() => _hoverIndex = null); // функция для выхода из hover

  @override
  Widget build(BuildContext context) {
    // функция для построения виджета
    if (widget.points.isEmpty) {
      // если точек нет
      return const SizedBox(
        // коробка
        height: 160, // высота
        child: Center(
          // центр
          child: Text(
            'Нет данных',
            style: TextStyle(color: _kTextDim, fontSize: 13),
          ), // текст
        ),
      ); // коробка
    }

    final lineColor =
        widget.color ?? Theme.of(context).colorScheme.primary; // цвет линии
    final isDark =
        Theme.of(context).brightness == Brightness.dark; // тёмная ли тема
    final colors = AppColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // функция для построения виджета
        final totalW = constraints.maxWidth; // ширина
        return MouseRegion(
          // мышь
          onHover: (e) => _onMove(e.localPosition, totalW), // наведение
          onExit: (_) => _onExit(), // выход
          child: GestureDetector(
            // детектор жестов
            onTapDown: (d) => _onMove(d.localPosition, totalW), // нажатие
            onTapUp: (_) => _onExit(), // отпускание
            onPanUpdate: (d) =>
                _onMove(d.localPosition, totalW), // обновление пана
            onPanEnd: (_) => _onExit(), // конец пана
            child: SizedBox(
              height: 180, // высота
              width: double.infinity, // ширина
              child: CustomPaint(
                painter: _ChartPainter(
                  points: widget.points,
                  timestamps: widget.timestamps,
                  lineColor: lineColor,
                  warningMin: widget.warningMin,
                  warningMax: widget.warningMax,
                  alarmMin: widget.alarmMin,
                  alarmMax: widget.alarmMax,
                  hoverIndex: _hoverIndex,
                  unit: widget.unit,
                  period: widget.period,
                  padLeft: _padLeft,
                  padBottom: _padBottom,
                  padTop: _padTop,
                  padRight: _padRight,
                  isDark: isDark,
                  borderColor: isDark ? _kBorder : colors.border,
                  textDim: isDark ? _kTextDim : colors.textDim,
                  cardColor: isDark ? _kCard : colors.card,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  // класс для построения графика
  _ChartPainter({
    required this.points, // список точек
    required this.lineColor, // цвет линии
    required this.period, // период
    required this.padLeft, // отступ слева
    required this.padBottom, // отступ снизу
    required this.padTop, // отступ сверху
    required this.padRight, // отступ справа
    required this.isDark, // тёмная ли тема
    required this.borderColor,
    required this.textDim,
    required this.cardColor,
    this.timestamps, // список временных меток
    this.warningMin, // минимальное значение для предупреждения
    this.warningMax, // максимальное значение для предупреждения
    this.alarmMin, // минимальное значение для тревоги
    this.alarmMax, // максимальное значение для тревоги
    this.hoverIndex, // индекс hover
    this.unit = '', // единица измерения
  });

  final List<double> points; // список точек
  final List<DateTime>? timestamps; // список временных меток
  final Color lineColor; // цвет линии
  final double? warningMin; // минимальное значение для предупреждения
  final double? warningMax; // максимальное значение для предупреждения
  final double? alarmMin; // минимальное значение для тревоги
  final double? alarmMax; // максимальное значение для тревоги
  final int? hoverIndex; // индекс hover
  final String unit; // единица измерения
  final String period; // период
  final bool isDark; // тёмная ли тема
  final Color borderColor;
  final Color textDim;
  final Color cardColor;
  final double padLeft, padBottom, padTop, padRight; // отступы

  // ── Утилиты ────────────────────────────────────────────────────────────────

  static TextPainter _tp(
    String text, {
    double size = 10,
    Color color = _kTextDim,
    FontWeight fw = FontWeight.w400,
  }) {
    // функция для построения текста
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: fw),
      ), // текст
      textDirection: TextDirection.ltr, // текст справа налево
    )..layout(maxWidth: 80); // размер текста
    return tp; // текст
  }

  String _fmtX(int index) {
    // функция для форматирования оси X
    if (timestamps == null || timestamps!.isEmpty)
      return ''; // если временных меток нет, то возвращаем пустую строку
    final ts = timestamps![index.clamp(0, timestamps!.length - 1)]
        .toLocal(); // время
    switch (period) {
      // период
      case 'День':
        return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
      case 'Неделя': // неделя
        const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']; // дни недели
        return '${days[(ts.weekday - 1).clamp(0, 6)]} ${ts.hour.toString().padLeft(2, '0')}ч'; // день недели часы
      default: // Месяц
        return '${ts.day}.${ts.month.toString().padLeft(2, '0')}'; // день.месяц
    }
  }

  String _fmtHover(int index) {
    // функция для форматирования hover
    if (timestamps == null || timestamps!.isEmpty) return '';
    final ts = timestamps![index.clamp(0, timestamps!.length - 1)]
        .toLocal(); // время
    switch (period) {
      // период
      case 'День': // день
        return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'; // часы:минуты
      case 'Неделя':
        const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']; // дни недели
        return '${days[(ts.weekday - 1).clamp(0, 6)]} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'; // день недели часы:минуты
      default: // месяц
        return '${ts.day}.${ts.month.toString().padLeft(2, '0')} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'; // день.месяц часы:минуты
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // функция для построения графика
    if (points.isEmpty) return; // если точек нет, то возвращаем
    try {
      _doPaint(canvas, size);
    } // построение графика
    catch (e) {
      debugPrint('[LineChart] $e');
    } // ошибка
  }

  void _doPaint(Canvas canvas, Size size) {
    // функция для построения графика
    final chartW = size.width - padLeft - padRight; // ширина графика
    final chartH = size.height - padTop - padBottom; // высота графика

    // ── Диапазон Y ────────────────────────────────────────────────────────────
    final allY = [
      // список всех значений
      ...points,
      if (warningMin != null)
        warningMin!, // минимальное значение для предупреждения
      if (warningMax != null)
        warningMax!, // максимальное значение для предупреждения
      if (alarmMin != null) alarmMin!, // минимальное значение для тревоги
      if (alarmMax != null) alarmMax!, // максимальное значение для тревоги
    ];
    final rawMin = allY.reduce((a, b) => a < b ? a : b); // минимальное значение
    final rawMax = allY.reduce(
      (a, b) => a > b ? a : b,
    ); // максимальное значение
    final range = (rawMax - rawMin).abs(); // диапазон
    final pad = range < 0.001 ? 1.0 : range * 0.18;
    final dMin = rawMin - pad; // минимальное значение с учетом отступа
    final dMax = rawMax + pad; // максимальное значение с учетом отступа
    final dRange = (dMax - dMin).abs() < 0.0001
        ? 1.0
        : dMax - dMin; // диапазон с учетом отступа

    // Конвертация значения в Y-координату внутри области графика
    double toY(double v) => padTop + chartH - ((v - dMin) / dRange) * chartH;
    double toX(int i) =>
        padLeft +
        (points.length > 1 ? i * chartW / (points.length - 1) : chartW / 2);

    // ── Горизонтальные линии сетки + метки Y ─────────────────────────────────
    const yDivs = 4; // количество делений по Y
    final gridPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 0.5; // рисуем сетку

    for (var d = 0; d <= yDivs; d++) {
      final fraction = d / yDivs; // доля
      final value = dMin + dRange * fraction; // значение
      final y = padTop + chartH - fraction * chartH; // координата Y

      // Линия сетки
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(size.width - padRight, y),
        gridPaint,
      );

      // Метка Y слева
      final label = value.toStringAsFixed(value.abs() < 10 ? 1 : 0); // метка
      final tp = _tp(label, size: 9, color: textDim); // текст
      tp.paint(
        canvas,
        Offset(padLeft - tp.width - 4, y - tp.height / 2),
      ); // рисуем текст
    }

    // ── Метки оси X ───────────────────────────────────────────────────────────
    if (timestamps != null && timestamps!.isNotEmpty) {
      // если временных меток нет, то возвращаем
      const xDivs = 4; // количество делений по X
      for (var d = 0; d <= xDivs; d++) {
        // рисуем деления по X
        final idx = ((points.length - 1) * d / xDivs).round().clamp(
          0,
          points.length - 1,
        ); // индекс
        final x = toX(idx); // координата X
        final lbl = _fmtX(idx); // метка
        if (lbl.isEmpty) continue; // если метка пустая, то пропускаем
        final tp = _tp(lbl, size: 9, color: textDim); // текст
        tp.paint(
          canvas,
          Offset(
            (x - tp.width / 2).clamp(
              padLeft,
              size.width - padRight - tp.width,
            ), // координата X
            size.height - padBottom + 5,
          ),
        ); // координата Y
      }
    }

    // ── Пунктирные пороговые линии ────────────────────────────────────────────
    void drawDash(double value, Color color, String lbl) {
      // функция для рисования пунктирных пороговых линий
      final y = toY(value); // координата Y
      if (y < padTop - 2 || y > size.height - padBottom + 2)
        return; // если координата Y меньше или больше, то пропускаем
      final p = Paint()
        ..color = color.withOpacity(0.75)
        ..strokeWidth = 1.0; // рисуем линию
      var x = padLeft; // координата X
      // Пунктир только до правого края области данных (не заходит в зону меток)
      while (x < size.width - padRight) {
        // рисуем линию
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 5).clamp(0.0, size.width - padRight), y),
          p,
        ); // рисуем линию
        x += 9; // шаг
      }
      // Метка справа от области графика (в зоне padRight)
      final tp = _tp(lbl, size: 9, color: color); // текст
      final bgColor = cardColor; // фон по теме
      final labelX =
          size.width -
          padRight +
          4; // левый край метки — сразу за областью данных
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelX,
            y - tp.height / 2 - 2,
            tp.width + 6,
            tp.height + 4,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = bgColor,
      );
      tp.paint(canvas, Offset(labelX + 3, y - tp.height / 2));
    }

    if (warningMin != null)
      drawDash(
        warningMin!,
        _kWarning,
        'W ${warningMin!.toStringAsFixed(1)}',
      ); // рисуем пороговое значение для предупреждения
    if (warningMax != null)
      drawDash(warningMax!, _kWarning, 'W ${warningMax!.toStringAsFixed(1)}');
    if (alarmMin != null)
      drawDash(alarmMin!, _kAlarm, 'A ${alarmMin!.toStringAsFixed(1)}');
    if (alarmMax != null)
      drawDash(alarmMax!, _kAlarm, 'A ${alarmMax!.toStringAsFixed(1)}');

    // ── Заливка под линией ────────────────────────────────────────────────────
    final fillPath = Path()
      ..moveTo(toX(0), size.height - padBottom); // рисуем заливку
    for (var i = 0; i < points.length; i++) {
      fillPath.lineTo(toX(i), toY(points[i])); // рисуем линию
    }
    fillPath.lineTo(
      toX(points.length - 1),
      size.height - padBottom,
    ); // рисуем линию
    fillPath.close(); // закрываем путь
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader =
            LinearGradient(
              // рисуем градиент
              begin: Alignment.topCenter, // начало градиента
              end: Alignment.bottomCenter, // конец градиента
              colors: [
                lineColor.withOpacity(0.22),
                lineColor.withOpacity(0.01),
              ], // цвета
            ).createShader(
              Rect.fromLTWH(padLeft, padTop, chartW, chartH),
            ) // прямоугольник
        ..style = PaintingStyle.fill,
    ); // стиль заливки

    // ── Линия ─────────────────────────────────────────────────────────────────
    final linePath = Path()..moveTo(toX(0), toY(points[0])); // рисуем линию
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(toX(i), toY(points[i]));
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color =
            lineColor // цвет линии
        ..strokeWidth =
            2.0 // ширина линии
        ..style = PaintingStyle
            .stroke // стиль линии
        ..strokeCap = StrokeCap
            .round // закругление концов линии
        ..strokeJoin = StrokeJoin.round,
    ); // соединение линий

    // Точки на концах (первая и последняя)
    for (final idx in [0, points.length - 1]) {
      // рисуем точки на концах (первая и последняя)
      canvas.drawCircle(
        Offset(toX(idx), toY(points[idx])),
        3,
        Paint()..color = lineColor,
      ); // рисуем точку
    }

    // ── Hover ─────────────────────────────────────────────────────────────────
    if (hoverIndex != null && hoverIndex! < points.length) {
      final hi = hoverIndex!; // индекс hover
      final hx = toX(hi); // координата X
      final hy = toY(points[hi]); // координата Y
      final val = points[hi]; // значение

      // Вертикальная линия
      canvas.drawLine(
        Offset(hx, padTop),
        Offset(hx, size.height - padBottom), // рисуем линию
        Paint()
          ..color = lineColor.withOpacity(0.30)
          ..strokeWidth = 1.0,
      );

      // Точка
      canvas.drawCircle(
        Offset(hx, hy),
        6,
        Paint()..color = cardColor,
      ); // рисуем точку
      canvas.drawCircle(
        Offset(hx, hy),
        4,
        Paint()..color = lineColor,
      ); // рисуем точку
      canvas.drawCircle(
        Offset(hx, hy),
        4,
        Paint()
          ..color = lineColor
              .withOpacity(0.35) // цвет линии
          ..style = PaintingStyle
              .stroke // стиль линии
          ..strokeWidth = 2,
      ); // ширина линии

      // Тултип
      final timeLbl = _fmtHover(hi);
      final valLbl = '${val.toStringAsFixed(1)}$unit';
      final mainTp = _tp(
        valLbl,
        size: 12,
        color: lineColor,
        fw: FontWeight.w700,
      ); // текст
      final timeTp = timeLbl.isNotEmpty
          ? _tp(timeLbl, size: 10, color: textDim)
          : null;

      const tipPad = 7.0; // отступ
      final tipW =
          (timeTp != null
              ? timeTp.width.clamp(mainTp.width, 120.0)
              : mainTp.width) +
          tipPad * 2; // ширина толтипа
      final tipH =
          mainTp.height +
          (timeTp != null ? timeTp.height + 3 : 0) +
          tipPad * 2; // высота толтипа
      final tipX = (hx + 10 + tipW > size.width - padRight)
          ? hx - 10 - tipW
          : hx + 10; // координата X
      final tipY = (hy - tipH / 2).clamp(
        padTop,
        size.height - padBottom - tipH,
      ); // координата Y

      final tipRect = RRect.fromRectAndRadius(
        // рисуем прямоугольник
        Rect.fromLTWH(tipX, tipY, tipW, tipH),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        tipRect,
        Paint()..color = isDark ? const Color(0xF0111C1F) : Colors.white,
      );
      canvas.drawRRect(
        tipRect,
        Paint()
          ..color = lineColor
              .withOpacity(0.4) // цвет линии
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      ); // ширина линии

      mainTp.paint(
        canvas,
        Offset(tipX + tipPad, tipY + tipPad),
      ); // рисуем текст
      timeTp?.paint(
        canvas,
        Offset(tipX + tipPad, tipY + tipPad + mainTp.height + 3),
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) {
    // функция для проверки, нужно ли перерисовывать график
    // FIX: сравниваем по содержимому, а не по идентичности объекта списка,
    // иначе перерисовка происходит на каждый build даже без изменений данных.
    if (old.hoverIndex != hoverIndex)
      return true; // если индекс hover не равен, то перерисовываем
    if (old.isDark != isDark)
      return true; // если тема изменилась, перерисовываем
    if (old.warningMin != warningMin || old.warningMax != warningMax)
      return true; // если минимальное значение для предупреждения не равно, то перерисовываем
    if (old.alarmMin != alarmMin || old.alarmMax != alarmMax)
      return true; // если минимальное значение для тревоги не равно, то перерисовываем
    if (old.period != period)
      return true; // если период не равен, то перерисовываем
    if (old.points.length != points.length)
      return true; // если количество точек не равно, то перерисовываем
    if (old.timestamps?.length != timestamps?.length)
      return true; // если количество временных меток не равно, то перерисовываем
    for (var i = 0; i < points.length; i++) {
      // проверяем, нужно ли перерисовывать точки
      if (old.points[i] != points[i])
        return true; // если значение точки не равно, то перерисовываем
    }
    return false; // не нужно перерисовывать
  }
}
