import 'package:flutter/material.dart';

const _kBorder  = Color(0xFF19282B);
const _kTextDim = Color(0xFF7A8A8E);
const _kCard    = Color(0xFF111C1F);
const _kWarning = Color(0xFFFFB300);
const _kAlarm   = Color(0xFFFF5252);

/// Линейный график с осями, метками и hover-подсказкой.
/// [timestamps] — опциональный список DateTime, синхронизированный с [points].
/// Если передан, ось X показывает время/дату, а hover показывает точное время.
class LineChartWidget extends StatefulWidget {
  const LineChartWidget({
    super.key,
    required this.points,
    this.timestamps,
    this.color,
    this.warningMin,
    this.warningMax,
    this.alarmMin,
    this.alarmMax,
    this.unit = '',
    this.period = 'День',
  });

  final List<double>   points;
  final List<DateTime>? timestamps;
  final Color?         color;
  final double?        warningMin;
  final double?        warningMax;
  final double?        alarmMin;
  final double?        alarmMax;
  final String         unit;
  /// 'День' | 'Неделя' | 'Месяц' — влияет на формат меток оси X
  final String         period;

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
  int? _hoverIndex;

  // Отступы под ось X и под ось Y
  static const double _padLeft   = 44.0;
  static const double _padBottom = 28.0;
  static const double _padTop    = 12.0;
  static const double _padRight  = 8.0;

  int _indexFromDx(double dx, double chartW) {
    if (widget.points.length <= 1) return 0;
    final x = (dx - _padLeft).clamp(0.0, chartW);
    final step = chartW / (widget.points.length - 1);
    return (x / step).round().clamp(0, widget.points.length - 1);
  }

  void _onMove(Offset local, double totalW) {
    final chartW = totalW - _padLeft - _padRight;
    final idx = _indexFromDx(local.dx, chartW);
    if (_hoverIndex != idx) setState(() => _hoverIndex = idx);
  }

  void _onExit() => setState(() => _hoverIndex = null);

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('Нет данных', style: TextStyle(color: _kTextDim, fontSize: 13)),
        ),
      );
    }

    final lineColor = widget.color ?? Theme.of(context).colorScheme.primary;

    return LayoutBuilder(builder: (context, constraints) {
      final totalW = constraints.maxWidth;
      return MouseRegion(
        onHover: (e) => _onMove(e.localPosition, totalW),
        onExit:  (_)  => _onExit(),
        child: GestureDetector(
        onTapDown:   (d) => _onMove(d.localPosition, totalW),
        onTapUp:     (_) => _onExit(),
        onPanUpdate: (d) => _onMove(d.localPosition, totalW),
        onPanEnd:    (_) => _onExit(),
        child: SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              points:      widget.points,
              timestamps:  widget.timestamps,
              lineColor:   lineColor,
              warningMin:  widget.warningMin,
              warningMax:  widget.warningMax,
              alarmMin:    widget.alarmMin,
              alarmMax:    widget.alarmMax,
              hoverIndex:  _hoverIndex,
              unit:        widget.unit,
              period:      widget.period,
              padLeft:     _padLeft,
              padBottom:   _padBottom,
              padTop:      _padTop,
              padRight:    _padRight,
            ),
          ),
        ),
      ));
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.lineColor,
    required this.period,
    required this.padLeft,
    required this.padBottom,
    required this.padTop,
    required this.padRight,
    this.timestamps,
    this.warningMin,
    this.warningMax,
    this.alarmMin,
    this.alarmMax,
    this.hoverIndex,
    this.unit = '',
  });

  final List<double>    points;
  final List<DateTime>? timestamps;
  final Color           lineColor;
  final double?         warningMin;
  final double?         warningMax;
  final double?         alarmMin;
  final double?         alarmMax;
  final int?            hoverIndex;
  final String          unit;
  final String          period;
  final double padLeft, padBottom, padTop, padRight;

  // ── Утилиты ────────────────────────────────────────────────────────────────

  static TextPainter _tp(String text, {double size = 10, Color color = _kTextDim, FontWeight fw = FontWeight.w400}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: fw)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    return tp;
  }

  String _fmtX(int index) {
    if (timestamps == null || timestamps!.isEmpty) return '';
    final ts = timestamps![index.clamp(0, timestamps!.length - 1)].toLocal();
    switch (period) {
      case 'День':
        return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
      case 'Неделя':
        const days = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
        return '${days[(ts.weekday - 1).clamp(0, 6)]} ${ts.hour.toString().padLeft(2,'0')}ч';
      default: // Месяц
        return '${ts.day}.${ts.month.toString().padLeft(2,'0')}';
    }
  }

  String _fmtHover(int index) {
    if (timestamps == null || timestamps!.isEmpty) return '';
    final ts = timestamps![index.clamp(0, timestamps!.length - 1)].toLocal();
    switch (period) {
      case 'День':
        return '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}';
      case 'Неделя':
        const days = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
        return '${days[(ts.weekday - 1).clamp(0,6)]} ${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}';
      default:
        return '${ts.day}.${ts.month.toString().padLeft(2,'0')} ${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}';
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    try { _doPaint(canvas, size); }
    catch (e) { debugPrint('[LineChart] $e'); }
  }

  void _doPaint(Canvas canvas, Size size) {
    final chartW = size.width  - padLeft - padRight;
    final chartH = size.height - padTop  - padBottom;

    // ── Диапазон Y ────────────────────────────────────────────────────────────
    final allY = [
      ...points,
      if (warningMin != null) warningMin!,
      if (warningMax != null) warningMax!,
      if (alarmMin   != null) alarmMin!,
      if (alarmMax   != null) alarmMax!,
    ];
    final rawMin = allY.reduce((a, b) => a < b ? a : b);
    final rawMax = allY.reduce((a, b) => a > b ? a : b);
    final range  = (rawMax - rawMin).abs();
    final pad    = range < 0.001 ? 1.0 : range * 0.18;
    final dMin   = rawMin - pad;
    final dMax   = rawMax + pad;
    final dRange = (dMax - dMin).abs() < 0.0001 ? 1.0 : dMax - dMin;

    // Конвертация значения в Y-координату внутри области графика
    double toY(double v) => padTop + chartH - ((v - dMin) / dRange) * chartH;
    double toX(int i)    => padLeft + (points.length > 1 ? i * chartW / (points.length - 1) : chartW / 2);

    // ── Горизонтальные линии сетки + метки Y ─────────────────────────────────
    const yDivs = 4;
    final gridPaint = Paint()..color = _kBorder..strokeWidth = 0.5;

    for (var d = 0; d <= yDivs; d++) {
      final fraction = d / yDivs;
      final value    = dMin + dRange * fraction;
      final y        = padTop + chartH - fraction * chartH;

      // Линия сетки
      canvas.drawLine(Offset(padLeft, y), Offset(size.width - padRight, y), gridPaint);

      // Метка Y слева
      final label = value.toStringAsFixed(value.abs() < 10 ? 1 : 0);
      final tp    = _tp(label, size: 9, color: _kTextDim);
      tp.paint(canvas, Offset(padLeft - tp.width - 4, y - tp.height / 2));
    }

    // ── Метки оси X ───────────────────────────────────────────────────────────
    if (timestamps != null && timestamps!.isNotEmpty) {
      const xDivs = 4;
      for (var d = 0; d <= xDivs; d++) {
        final idx = ((points.length - 1) * d / xDivs).round().clamp(0, points.length - 1);
        final x   = toX(idx);
        final lbl = _fmtX(idx);
        if (lbl.isEmpty) continue;
        final tp = _tp(lbl, size: 9);
        tp.paint(canvas, Offset((x - tp.width / 2).clamp(padLeft, size.width - padRight - tp.width),
            size.height - padBottom + 5));
      }
    }

    // ── Пунктирные пороговые линии ────────────────────────────────────────────
    void drawDash(double value, Color color, String lbl) {
      final y = toY(value);
      if (y < padTop - 2 || y > size.height - padBottom + 2) return;
      final p = Paint()..color = color.withOpacity(0.75)..strokeWidth = 1.0;
      var x = padLeft;
      while (x < size.width - padRight) {
        canvas.drawLine(Offset(x, y), Offset((x + 5).clamp(0.0, size.width - padRight), y), p);
        x += 9;
      }
      // Метка у правого края
      final tp = _tp(lbl, size: 9, color: color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - padRight - tp.width - 6, y - tp.height / 2 - 2, tp.width + 6, tp.height + 4),
          const Radius.circular(3),
        ),
        Paint()..color = _kCard,
      );
      tp.paint(canvas, Offset(size.width - padRight - tp.width - 3, y - tp.height / 2));
    }

    if (warningMin != null) drawDash(warningMin!, _kWarning, 'W ${warningMin!.toStringAsFixed(1)}');
    if (warningMax != null) drawDash(warningMax!, _kWarning, 'W ${warningMax!.toStringAsFixed(1)}');
    if (alarmMin   != null) drawDash(alarmMin!,   _kAlarm,   'A ${alarmMin!.toStringAsFixed(1)}');
    if (alarmMax   != null) drawDash(alarmMax!,   _kAlarm,   'A ${alarmMax!.toStringAsFixed(1)}');

    // ── Заливка под линией ────────────────────────────────────────────────────
    final fillPath = Path()..moveTo(toX(0), size.height - padBottom);
    for (var i = 0; i < points.length; i++) {
      fillPath.lineTo(toX(i), toY(points[i]));
    }
    fillPath.lineTo(toX(points.length - 1), size.height - padBottom);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.22), lineColor.withOpacity(0.01)],
      ).createShader(Rect.fromLTWH(padLeft, padTop, chartW, chartH))
      ..style = PaintingStyle.fill);

    // ── Линия ─────────────────────────────────────────────────────────────────
    final linePath = Path()..moveTo(toX(0), toY(points[0]));
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(toX(i), toY(points[i]));
    }
    canvas.drawPath(linePath, Paint()
      ..color       = lineColor
      ..strokeWidth = 2.0
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round);

    // Точки на концах (первая и последняя)
    for (final idx in [0, points.length - 1]) {
      canvas.drawCircle(Offset(toX(idx), toY(points[idx])), 3,
          Paint()..color = lineColor);
    }

    // ── Hover ─────────────────────────────────────────────────────────────────
    if (hoverIndex != null && hoverIndex! < points.length) {
      final hi  = hoverIndex!;
      final hx  = toX(hi);
      final hy  = toY(points[hi]);
      final val = points[hi];

      // Вертикальная линия
      canvas.drawLine(Offset(hx, padTop), Offset(hx, size.height - padBottom),
          Paint()..color = lineColor.withOpacity(0.30)..strokeWidth = 1.0);

      // Точка
      canvas.drawCircle(Offset(hx, hy), 6, Paint()..color = _kCard);
      canvas.drawCircle(Offset(hx, hy), 4, Paint()..color = lineColor);
      canvas.drawCircle(Offset(hx, hy), 4, Paint()
        ..color = lineColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);

      // Тултип
      final timeLbl = _fmtHover(hi);
      final valLbl  = '${val.toStringAsFixed(1)}$unit';
      final mainTp  = _tp(valLbl, size: 12, color: lineColor, fw: FontWeight.w700);
      final timeTp  = timeLbl.isNotEmpty ? _tp(timeLbl, size: 10, color: _kTextDim) : null;

      const tipPad = 7.0;
      final tipW = (timeTp != null ? timeTp.width.clamp(mainTp.width, 120.0) : mainTp.width) + tipPad * 2;
      final tipH = mainTp.height + (timeTp != null ? timeTp.height + 3 : 0) + tipPad * 2;
      final tipX = (hx + 10 + tipW > size.width - padRight) ? hx - 10 - tipW : hx + 10;
      final tipY = (hy - tipH / 2).clamp(padTop, size.height - padBottom - tipH);

      final tipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tipX, tipY, tipW, tipH), const Radius.circular(6));
      canvas.drawRRect(tipRect, Paint()..color = const Color(0xF0111C1F));
      canvas.drawRRect(tipRect, Paint()
        ..color = lineColor.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);

      mainTp.paint(canvas, Offset(tipX + tipPad, tipY + tipPad));
      timeTp?.paint(canvas, Offset(tipX + tipPad, tipY + tipPad + mainTp.height + 3));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) {
    // FIX: сравниваем по содержимому, а не по идентичности объекта списка,
    // иначе перерисовка происходит на каждый build даже без изменений данных.
    if (old.hoverIndex != hoverIndex) return true;
    if (old.warningMin != warningMin || old.warningMax != warningMax) return true;
    if (old.alarmMin   != alarmMin   || old.alarmMax   != alarmMax)   return true;
    if (old.period     != period)      return true;
    if (old.points.length != points.length) return true;
    if (old.timestamps?.length != timestamps?.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (old.points[i] != points[i]) return true;
    }
    return false;
  }
}