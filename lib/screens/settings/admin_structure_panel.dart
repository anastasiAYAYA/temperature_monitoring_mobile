part of '../settings_screen.dart';

class _AdminStructurePanel extends StatelessWidget {
  const _AdminStructurePanel({
    required this.repo,
    required this.onRefresh,
    required this.onRenameLocation,
    required this.onDeleteLocation,
    required this.onRenameUnit,
    required this.onDeleteUnit,
    required this.onRenameSensor,
    required this.onDeleteSensor,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;
  final ValueChanged<LocationModel> onRenameLocation;
  final ValueChanged<LocationModel> onDeleteLocation;
  final ValueChanged<Map<String, dynamic>> onRenameUnit;
  final ValueChanged<Map<String, dynamic>> onDeleteUnit;
  final ValueChanged<SensorModel> onRenameSensor;
  final ValueChanged<SensorModel> onDeleteSensor;

  int? _unitId(Map<String, dynamic> unit) => (unit['id'] as num?)?.toInt();

  int? _unitLocationId(Map<String, dynamic> unit) =>
      (unit['group_id'] as num?)?.toInt() ??
      (unit['location_id'] as num?)?.toInt();

  String _unitName(Map<String, dynamic> unit) {
    final id = _unitId(unit);
    return unit['name'] as String? ?? (id == null ? 'Блок' : 'Блок #$id');
  }

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final locations = [...repo.locations]
      ..sort((a, b) => a.name.compareTo(b.name));

    if (locations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, color: sch.textDim, size: 38),
            const SizedBox(height: 10),
            Text('Структура пуста', style: TextStyle(color: sch.textDim)),
            const SizedBox(height: 12),
            _AdminSmallButton(
              icon: Icons.refresh,
              label: 'Обновить',
              color: kCyan,
              onTap: () => onRefresh(),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kCyan,
      backgroundColor: sch.card,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: locations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final location = locations[index];
          final units =
              repo.controlUnits
                  .where((u) => _unitLocationId(u) == location.id)
                  .toList()
                ..sort((a, b) => _unitName(a).compareTo(_unitName(b)));
          final sensors =
              repo.sensors.where((s) => s.groupId == location.id).toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          final sensorsByUnit = <int, List<SensorModel>>{};
          final looseSensors = <SensorModel>[];

          for (final sensor in sensors) {
            final unitId = sensor.controlUnitId;
            if (unitId == null) {
              looseSensors.add(sensor);
            } else {
              sensorsByUnit.putIfAbsent(unitId, () => []).add(sensor);
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: sch.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sch.border),
            ),
            child: ExpansionTile(
              initiallyExpanded: index == 0,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              iconColor: kCyan,
              collapsedIconColor: sch.textDim,
              title: _StructureTitle(
                icon: Icons.business_outlined,
                color: kCyan,
                title: location.name,
                subtitle: '${units.length} блоков · ${sensors.length} сенсоров',
              ),
              trailing: _StructureActions(
                onEdit: () => onRenameLocation(location),
                onDelete: () => onDeleteLocation(location),
              ),
              children: [
                if (units.isEmpty && sensors.isEmpty)
                  const _StructureEmptyLine(text: 'Нет блоков и сенсоров'),
                for (final unit in units) ...[
                  const SizedBox(height: 8),
                  _ControlUnitBranch(
                    unit: unit,
                    sensors: sensorsByUnit[_unitId(unit)] ?? const [],
                    unitName: _unitName(unit),
                    onRenameUnit: onRenameUnit,
                    onDeleteUnit: onDeleteUnit,
                    onRenameSensor: onRenameSensor,
                    onDeleteSensor: onDeleteSensor,
                  ),
                ],
                if (looseSensors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LooseSensorBranch(
                    sensors: looseSensors,
                    onRenameSensor: onRenameSensor,
                    onDeleteSensor: onDeleteSensor,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ControlUnitBranch extends StatelessWidget {
  const _ControlUnitBranch({
    required this.unit,
    required this.sensors,
    required this.unitName,
    required this.onRenameUnit,
    required this.onDeleteUnit,
    required this.onRenameSensor,
    required this.onDeleteSensor,
  });

  final Map<String, dynamic> unit;
  final List<SensorModel> sensors;
  final String unitName;
  final ValueChanged<Map<String, dynamic>> onRenameUnit;
  final ValueChanged<Map<String, dynamic>> onDeleteUnit;
  final ValueChanged<SensorModel> onRenameSensor;
  final ValueChanged<SensorModel> onDeleteSensor;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    final serial = unit['serial_number'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: sch.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sch.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 12, right: 8),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        iconColor: kCyan,
        collapsedIconColor: sch.textDim,
        title: _StructureTitle(
          icon: Icons.memory_outlined,
          color: kAccent,
          title: unitName,
          subtitle: serial == null
              ? '${sensors.length} сенсоров'
              : '$serial · ${sensors.length} сенсоров',
        ),
        trailing: _StructureActions(
          onEdit: () => onRenameUnit(unit),
          onDelete: () => onDeleteUnit(unit),
        ),
        children: sensors.isEmpty
            ? const [_StructureEmptyLine(text: 'Нет привязанных сенсоров')]
            : sensors
                  .map(
                    (sensor) => _SensorLeaf(
                      sensor: sensor,
                      onRenameSensor: onRenameSensor,
                      onDeleteSensor: onDeleteSensor,
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class _LooseSensorBranch extends StatelessWidget {
  const _LooseSensorBranch({
    required this.sensors,
    required this.onRenameSensor,
    required this.onDeleteSensor,
  });

  final List<SensorModel> sensors;
  final ValueChanged<SensorModel> onRenameSensor;
  final ValueChanged<SensorModel> onDeleteSensor;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: sch.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sch.border),
      ),
      child: Column(
        children: [
          _StructureTitle(
            icon: Icons.sensors_outlined,
            color: kCyan,
            title: 'Сенсоры без блока',
            subtitle: '${sensors.length} сенсоров',
          ),
          const SizedBox(height: 8),
          for (final sensor in sensors)
            _SensorLeaf(
              sensor: sensor,
              onRenameSensor: onRenameSensor,
              onDeleteSensor: onDeleteSensor,
            ),
        ],
      ),
    );
  }
}

class _SensorLeaf extends StatelessWidget {
  const _SensorLeaf({
    required this.sensor,
    required this.onRenameSensor,
    required this.onDeleteSensor,
  });

  final SensorModel sensor;
  final ValueChanged<SensorModel> onRenameSensor;
  final ValueChanged<SensorModel> onDeleteSensor;

  @override
  Widget build(BuildContext context) {
    final color = sensor.isOnline ? kGreen : kRed;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: _StructureTitle(
              icon: Icons.sensors_outlined,
              color: color,
              title: sensor.name,
              subtitle: sensor.internalId == null
                  ? 'ID #${sensor.id}'
                  : '${sensor.internalId} · ID #${sensor.id}',
            ),
          ),
          const SizedBox(width: 8),
          _StructureActions(
            compact: true,
            onEdit: () => onRenameSensor(sensor),
            onDelete: () => onDeleteSensor(sensor),
          ),
        ],
      ),
    );
  }
}

class _StructureTitle extends StatelessWidget {
  const _StructureTitle({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: sch.textMain,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sch.textDim, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StructureActions extends StatelessWidget {
  const _StructureActions({
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 34.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Редактировать название',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onEdit,
            child: SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.edit_outlined, color: kCyan, size: 18),
            ),
          ),
        ),
        Tooltip(
          message: 'Удалить',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onDelete,
            child: SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.delete_outline, color: kRed, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _StructureEmptyLine extends StatelessWidget {
  const _StructureEmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: AppColors.of(context).textDim, fontSize: 12),
        ),
      ),
    );
  }
}

class _AdminSmallButton extends StatelessWidget {
  const _AdminSmallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _AdminLocationsSection extends StatelessWidget {
  const _AdminLocationsSection({required this.repo, required this.locationId});

  final AppRepository repo;
  final int locationId;

  @override
  Widget build(BuildContext context) {
    final loc = repo.locations.where((l) => l.id == locationId).firstOrNull;
    final sensors = repo.sensors.where((s) => s.groupId == locationId).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Карточка локации
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.of(context).card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: kCyan,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc?.name ?? '',
                      style: TextStyle(
                        color: AppColors.of(context).textMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(label: 'ID локации', value: '#$locationId'),
              _InfoRow(label: 'Датчиков', value: '${sensors.length}'),
              if (loc?.imageUrl != null)
                _InfoRow(label: 'План', value: 'Загружен'),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Список датчиков
        if (sensors.isNotEmpty) ...[
          Text(
            'Датчики',
            style: TextStyle(
              color: AppColors.of(context).textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ...sensors.map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.of(context).card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.of(context).border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.isOnline ? kGreen : kRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.name,
                      style: TextStyle(
                        color: AppColors.of(context).textMain,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    s.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      color: s.isOnline ? kGreen : kRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Датчики не найдены',
                style: TextStyle(
                  color: AppColors.of(context).textDim,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.of(context).textDim,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppColors.of(context).textMain,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Таб: Все сотрудники компании (editor/viewer)
// ─────────────────────────────────────────────────────────────────────────────
