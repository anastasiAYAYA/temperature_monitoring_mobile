part of '../reports_screen.dart';

class _ChartBlock extends StatelessWidget {
  const _ChartBlock({
    required this.label,
    required this.unit,
    required this.color,
    required this.points,
    required this.loading,
    this.timestamps,
    this.period = 'День',
    this.error,
  });
  final String label;
  final String unit;
  final Color color;
  final List<double> points;
  final bool loading;
  final List<DateTime>? timestamps;
  final String period;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок с цветной полоской
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
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (loading)
          SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.of(context).cyan,
                strokeWidth: 2,
              ),
            ),
          )
        else if (error != null)
          SizedBox(
            height: 70,
            child: Center(
              child: Text(
                error!,
                style: TextStyle(
                  color: AppColors.of(context).textDim,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (points.isEmpty)
          SizedBox(
            height: 70,
            child: Center(
              child: Text(
                'Нет данных за выбранный период',
                style: TextStyle(
                  color: AppColors.of(context).textDim,
                  fontSize: 12,
                ),
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 110,
            child: LineChartWidget(
              points: points,
              color: color,
              timestamps: timestamps,
              period: period,
            ),
          ),
          const SizedBox(height: 8),
          // Статистика
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
                  label: 'Мин',
                  value:
                      '${points.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).cyan,
                ),
                _Divider(),
                _StatCell(
                  label: 'Среднее',
                  value:
                      '${(points.reduce((a, b) => a + b) / points.length).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).textMain,
                ),
                _Divider(),
                _StatCell(
                  label: 'Макс',
                  value:
                      '${points.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}$unit',
                  color: AppColors.of(context).accent,
                ),
                _Divider(),
                _StatCell(
                  label: 'Точек',
                  value: '${points.length}',
                  color: AppColors.of(context).textDim,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppColors.of(context).border);
  }
}
