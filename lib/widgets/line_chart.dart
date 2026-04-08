import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LineChartWidget extends StatelessWidget {
  const LineChartWidget({
    super.key,
    required this.points,
    this.color = AppColors.primary,
  });

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: CustomPaint(painter: _LinePainter(points, color)),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minV = points.reduce(min);
    final maxV = points.reduce(max);
    final span = max(maxV - minV, 0.001);
    final path = Path();

    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / max(1, points.length - 1);
      final y = size.height - ((points[i] - minV) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
