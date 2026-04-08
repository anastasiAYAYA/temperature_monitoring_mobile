import 'package:flutter/material.dart';

import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/line_chart.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.repo, required this.onRefresh});
  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  String period = 'День';
  String search = '';

  Future<void> _openSensorDetails(SensorModel sensor) async {
    final wMinCtrl = TextEditingController(text: (sensor.warningMinTemp ?? 18).toString());
    final wMaxCtrl = TextEditingController(text: (sensor.warningMaxTemp ?? 26).toString());
    final aMinCtrl = TextEditingController(text: (sensor.alarmMinTemp ?? 16).toString());
    final aMaxCtrl = TextEditingController(text: (sensor.alarmMaxTemp ?? 28).toString());
    bool loading = true;

    await widget.repo.loadHistory(sensor.id, period);
    loading = false;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Датчик ${sensor.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'День', label: Text('День')),
                    ButtonSegment(value: 'Неделя', label: Text('Неделя')),
                    ButtonSegment(value: 'Месяц', label: Text('Месяц')),
                  ],
                  selected: {period},
                  onSelectionChanged: (v) async {
                    setStateDialog(() {
                      period = v.first;
                      loading = true;
                    });
                    await widget.repo.loadHistory(sensor.id, period);
                    setStateDialog(() => loading = false);
                  },
                ),
                const SizedBox(height: 8),
                if (loading)
                  const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                else
                  LineChartWidget(points: sensor.points),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Пороговые значения', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextField(controller: wMinCtrl, decoration: const InputDecoration(labelText: 'Warning min °C')),
                TextField(controller: wMaxCtrl, decoration: const InputDecoration(labelText: 'Warning max °C')),
                TextField(controller: aMinCtrl, decoration: const InputDecoration(labelText: 'Alarm min °C')),
                TextField(controller: aMaxCtrl, decoration: const InputDecoration(labelText: 'Alarm max °C')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
            if (widget.repo.role == UserRole.admin || widget.repo.role == UserRole.editor)
              FilledButton(
                onPressed: () async {
                  final err = await widget.repo.updateSensorThresholds(
                    sensorId: sensor.id,
                    warningMinTemp: double.tryParse(wMinCtrl.text.trim()) ?? 18,
                    warningMaxTemp: double.tryParse(wMaxCtrl.text.trim()) ?? 26,
                    alarmMinTemp: double.tryParse(aMinCtrl.text.trim()) ?? 16,
                    alarmMaxTemp: double.tryParse(aMaxCtrl.text.trim()) ?? 28,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Пороги сохранены')));
                  if (err == null) {
                    Navigator.pop(context);
                    await widget.onRefresh();
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: const Text('Сохранить пороги'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <LocationModel, List<SensorModel>>{};
    for (final location in widget.repo.locations) {
      final items = widget.repo.sensors.where((e) => e.groupId == location.id).toList();
      if (items.isNotEmpty) {
        grouped[location] = items;
      }
    }

    final query = search.trim().toLowerCase();
    final filteredEntries = grouped.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.name.toLowerCase().contains(query) ||
          entry.value.any((sensor) => sensor.name.toLowerCase().contains(query));
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Поиск по локациям и датчикам',
          ),
          onChanged: (value) => setState(() => search = value),
        ),
        const SizedBox(height: 8),
        ...filteredEntries.map(
          (entry) => Card(
            color: AppColors.card,
            child: ExpansionTile(
              title: Text(entry.key.name),
              subtitle: Text('Датчиков: ${entry.value.length}'),
              children: entry.value
                  .map(
                    (sensor) => ListTile(
                      title: Text(sensor.name),
                      subtitle: Text('${sensor.temperature.toStringAsFixed(1)}°C • ${sensor.humidity.toStringAsFixed(1)}%'),
                      onTap: () => _openSensorDetails(sensor),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
