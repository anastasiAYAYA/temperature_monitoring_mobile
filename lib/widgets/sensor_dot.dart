import 'package:flutter/material.dart';
import '../models/sensor_model.dart';
import '../theme/app_colors.dart';

class SensorDot extends StatelessWidget {
  const SensorDot({super.key, required this.state});

  final SensorState state;

  @override
  Widget build(BuildContext context) {
    final color = state == SensorState.critical
        ? AppColors.danger
        : state == SensorState.warning
            ? AppColors.primary
            : AppColors.success;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
