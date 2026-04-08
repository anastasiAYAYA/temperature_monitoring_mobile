import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repo});
  final AppRepository repo;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String format = 'xlsx';
  String period = 'Неделя';
  int? selectedSensorId;

  @override
  Widget build(BuildContext context) {
    final sensors = widget.repo.sensors;
    selectedSensorId ??= sensors.isNotEmpty ? sensors.first.id : null;
    final selectedSensor = sensors.where((e) => e.id == selectedSensorId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Аналитика и архив', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'День', label: Text('День')),
            ButtonSegment(value: 'Неделя', label: Text('Неделя')),
            ButtonSegment(value: 'Месяц', label: Text('Месяц')),
          ],
          selected: {period},
          onSelectionChanged: (v) => setState(() => period = v.first),
        ),
        const SizedBox(height: 8),
        if (sensors.isNotEmpty)
          DropdownButtonFormField<int>(
            initialValue: selectedSensorId,
            decoration: const InputDecoration(labelText: 'Датчик для отчета'),
            items: sensors.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
            onChanged: (v) => setState(() => selectedSensorId = v),
          ),
        const SizedBox(height: 10),
        Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LineChartWidget(
              points: selectedSensor?.points ?? [],
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LineChartWidget(
              points: widget.repo.sensors.expand((e) => e.points.take(4)).toList(),
              color: AppColors.info,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'xlsx', label: Text('CSV/XLSX')),
            ButtonSegment(value: 'pdf', label: Text('PDF')),
          ],
          selected: {format},
          onSelectionChanged: (v) => setState(() => format = v.first),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: selectedSensor == null
              ? null
              : () async {
                  final bytes = await widget.repo.downloadReport(selectedSensor.id, format);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(bytes == null ? 'Ошибка загрузки отчета' : 'Отчет получен (${bytes.length} байт)')),
                  );
                },
          child: const Text('Скачать отчет по датчику'),
        ),
      ],
    );
  }
}
