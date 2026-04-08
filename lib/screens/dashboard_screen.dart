import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/sensor_dot.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repo, required this.onRefresh});
  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<void> _showCreateLocationDialog() async {
    final nameCtrl = TextEditingController();
    final schemaCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая мнемосхема / локация'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название локации')),
            TextField(controller: schemaCtrl, decoration: const InputDecoration(labelText: 'URL мнемосхемы')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final err = await widget.repo.createLocation(
                name: nameCtrl.text.trim(),
                imageUrl: schemaCtrl.text.trim().isEmpty ? null : schemaCtrl.text.trim(),
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Локация создана')));
              if (err == null) await widget.onRefresh();
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateSensorDialog() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    int? selectedLocationId = widget.repo.locations.isNotEmpty ? widget.repo.locations.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новый датчик'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название датчика')),
              TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'Internal ID')),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: selectedLocationId,
                items: widget.repo.locations
                    .map((e) => DropdownMenuItem<int>(value: e.id, child: Text('${e.id}: ${e.name}')))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedLocationId = v),
                decoration: const InputDecoration(labelText: 'Локация'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                final err = await widget.repo.createSensor(
                  name: nameCtrl.text.trim(),
                  locationId: selectedLocationId ?? 1,
                  internalId: idCtrl.text.trim().isEmpty ? null : idCtrl.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Датчик создан')));
                if (err == null) await widget.onRefresh();
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.repo.role == UserRole.admin;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Система мониторинга помещений', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (canManage)
              IconButton(
                onPressed: _showCreateLocationDialog,
                icon: const Icon(Icons.add_photo_alternate, color: AppColors.primary),
                tooltip: 'Добавить мнемосхему/локацию',
              ),
            if (canManage)
              IconButton(
                onPressed: _showCreateSensorDialog,
                icon: const Icon(Icons.sensors, color: AppColors.primary),
                tooltip: 'Добавить датчик',
              ),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          color: AppColors.card,
          child: SizedBox(
            height: 240,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      image: widget.repo.locations.isNotEmpty && widget.repo.locations.first.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(widget.repo.locations.first.imageUrl!),
                              fit: BoxFit.cover,
                              opacity: 0.6,
                            )
                          : null,
                    ),
                  ),
                ),
                ...widget.repo.sensors.map(
                  (sensor) => Positioned(
                    left: sensor.x,
                    top: sensor.y,
                    child: SensorDot(state: sensor.state),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Новейшие уведомления', style: TextStyle(fontWeight: FontWeight.w700)),
        ...widget.repo.alarms.take(5).map(
              (alarm) => ListTile(
                dense: true,
                title: Text(alarm.title),
                subtitle: Text(alarm.description, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
        const SizedBox(height: 8),
        const Text('Датчики на мнемосхеме', style: TextStyle(fontWeight: FontWeight.w700)),
        ...widget.repo.sensors.take(5).map(
              (sensor) => ListTile(
                title: Text(sensor.name),
                subtitle: Text('${sensor.temperature.toStringAsFixed(1)}°C / ${sensor.humidity.toStringAsFixed(1)}%'),
              ),
            ),
      ],
    );
  }
}
