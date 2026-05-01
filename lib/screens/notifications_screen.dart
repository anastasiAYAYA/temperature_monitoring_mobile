import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../models/location_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';

// ── Фирменная палитра ─────────────────────────────────────────────────────────
const _kBg       = Color(0xFF0A0A0A);
const _kCard     = Color(0x4D323232);
const _kCard2    = Color(0x334B4B4B);
const _kBorder   = Color(0xFF19282B);
const _kCyan     = Color(0xFF07BCD4);
const _kGreen    = Color(0xFF01E676);
const _kRed      = Color(0xFFFF5252);
const _kOrange   = Color(0xFFFF9800);
const _kAccent   = Color(0xFFFFD550);
const _kRedBg    = Color(0xFF321C1B);
const _kTextDim  = Color(0xFF7A8A8E);

// ── Сортировка ────────────────────────────────────────────────────────────────

enum _SortOrder { newestFirst, oldestFirst, statusPriority }

extension _SortOrderLabel on _SortOrder {
  String get label => switch (this) {
        _SortOrder.newestFirst    => 'Сначала новые',
        _SortOrder.oldestFirst    => 'Сначала старые',
        _SortOrder.statusPriority => 'По критичности',
      };
}

// ── Экран ─────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  AlarmStatus? _filterStatus;
  _SortOrder _sortOrder = _SortOrder.newestFirst;

  // Поиск (для admin)
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Выбранная компания для admin (null = список компаний)
  int? _adminSelectedLocationId;

  // Локально отключённые уведомления для локаций (фронт-заглушка до бэка)
  final Set<int> _mutedLocationIds = {};

  bool get _isAdmin => widget.repo.role == UserRole.admin;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Данные ───────────────────────────────────────────────────────────────

  List<AlarmModel> _alarmsForLocation(int? locationId) {
    final sensors = widget.repo.sensors
        .where((s) => locationId == null || s.groupId == locationId)
        .map((s) => s.id)
        .toSet();

    var list = widget.repo.alarms.where((a) {
      final matchesSensor =
          locationId == null || sensors.contains(a.sensorId);
      if (!matchesSensor) return false;
      if (_filterStatus == null) return true;
      return a.status == _filterStatus;
    }).toList();

    switch (_sortOrder) {
      case _SortOrder.newestFirst:
        list = list.reversed.toList();
      case _SortOrder.oldestFirst:
        break;
      case _SortOrder.statusPriority:
        const p = {
          AlarmStatus.newAlarm: 0,
          AlarmStatus.acknowledged: 1,
          AlarmStatus.resolved: 2,
        };
        list.sort((a, b) => p[a.status]!.compareTo(p[b.status]!));
    }
    return list;
  }

  List<AlarmModel> get _displayedAlarms {
    if (_isAdmin) {
      return _alarmsForLocation(_adminSelectedLocationId);
    }
    return _alarmsForLocation(null);
  }

  int get _newCount =>
      widget.repo.alarms.where((a) => a.status == AlarmStatus.newAlarm).length;

  int _newCountForLocation(int locationId) {
    final sensors = widget.repo.sensors
        .where((s) => s.groupId == locationId)
        .map((s) => s.id)
        .toSet();
    return widget.repo.alarms
        .where((a) =>
            a.status == AlarmStatus.newAlarm && sensors.contains(a.sensorId))
        .length;
  }

  // ── Цвета / метки ────────────────────────────────────────────────────────

  Color _statusColor(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => _kRed,
        AlarmStatus.acknowledged => _kOrange,
        AlarmStatus.resolved     => _kGreen,
      };

  Color _statusBg(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => _kRedBg,
        AlarmStatus.acknowledged => const Color(0xFF2A1E00),
        AlarmStatus.resolved     => const Color(0xFF0D2B1F),
      };

  String _statusLabel(AlarmStatus s) => switch (s) {
        AlarmStatus.newAlarm     => 'НОВОЕ',
        AlarmStatus.acknowledged => 'В РАБОТЕ',
        AlarmStatus.resolved     => 'РЕШЕНО',
      };

  // ── Диалог действия ──────────────────────────────────────────────────────

  Future<void> _showActionDialog({
    required AlarmModel alarm,
    required String newStatus,
    required String actionLabel,
    required String hintText,
    required Color accentColor,
  }) async {
    final commentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: Theme.of(context).colorScheme,
        ),
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kBorder),
          ),
          title: Text(
            actionLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kCard2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alarm.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (alarm.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        alarm.description,
                        style: const TextStyle(
                            fontSize: 12, color: _kTextDim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                autofocus: true,
                maxLines: 3,
                style:
                    const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle:
                      const TextStyle(color: _kTextDim, fontSize: 13),
                  labelText: 'Комментарий',
                  labelStyle: const TextStyle(color: _kTextDim),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена',
                  style: TextStyle(color: _kTextDim)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(actionLabel,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final err = await widget.repo.updateAlarm(
      alarm.id,
      newStatus,
      commentCtrl.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'Статус обновлён')));
    if (mounted) setState(() {});
    await widget.onRefresh();
    if (mounted) setState(() {});
  }

  // ── Диалог отключения уведомлений ────────────────────────────────────────

  Future<void> _showMuteDialog(LocationModel location) async {
    final isMuted = _mutedLocationIds.contains(location.id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: Theme.of(context).colorScheme,
        ),
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kBorder),
          ),
          title: Text(
            isMuted
                ? 'Включить уведомления'
                : 'Отключить уведомления',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kCard2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.business_outlined,
                        size: 16, color: _kCyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        location.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isMuted
                    ? 'Уведомления для этой компании будут снова активированы.'
                    : 'Все уведомления для этой компании будут отключены. '
                        'Тревоги всё равно будут записываться, '
                        'но пуш-уведомления приходить не будут.',
                style:
                    const TextStyle(color: _kTextDim, fontSize: 13, height: 1.5),
              ),
              if (!isMuted) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kRed.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined,
                          size: 14, color: _kRed),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Функция в разработке — изменение сохраняется только локально',
                          style: TextStyle(fontSize: 11, color: _kRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена',
                  style: TextStyle(color: _kTextDim)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isMuted ? _kGreen : _kRed,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                isMuted ? 'Включить' : 'Отключить',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      if (isMuted) {
        _mutedLocationIds.remove(location.id);
      } else {
        _mutedLocationIds.add(location.id);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isMuted
              ? 'Уведомления для «${location.name}» включены'
              : 'Уведомления для «${location.name}» отключены',
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _kBg,
        colorScheme: Theme.of(context).colorScheme,
      ),
      child: Container(
        color: _kBg,
        child: _isAdmin ? _buildAdminView() : _buildUserView(),
      ),
    );
  }

  // ── Вид администратора ────────────────────────────────────────────────────

  Widget _buildAdminView() {
    // Если выбрана компания — показываем её уведомления
    if (_adminSelectedLocationId != null) {
      final loc = widget.repo.locations
          .where((l) => l.id == _adminSelectedLocationId)
          .firstOrNull;
      return _buildLocationAlarms(loc);
    }

    // Иначе — список компаний с поиском
    final locations = widget.repo.locations;
    final filtered = _searchQuery.isEmpty
        ? locations
        : locations
            .where((l) =>
                l.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
    final sorted = List.of(filtered)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Группируем по первой букве
    final Map<String, List<LocationModel>> groups = {};
    for (final loc in sorted) {
      final letter =
          loc.name.isNotEmpty ? loc.name[0].toUpperCase() : '#';
      groups.putIfAbsent(letter, () => []).add(loc);
    }
    final letters = groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Шапка ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: Color(0x4D323232),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Уведомления',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_newCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kRedBg,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: _kRed.withOpacity(0.5)),
                      ),
                      child: Text(
                        '$_newCount новых',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kRed,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Поиск
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Поиск компании…',
                  hintStyle:
                      const TextStyle(color: _kTextDim, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: _kTextDim, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close,
                              color: _kTextDim, size: 16),
                        )
                      : null,
                  filled: true,
                  fillColor: _kCard,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kCyan),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Алфавитный список компаний ─────────────────────────────────────
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'Компании не найдены'
                        : 'Нет компаний',
                    style: const TextStyle(
                        color: _kTextDim, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: letters.length,
                  itemBuilder: (context, i) {
                    final letter = letters[i];
                    final items = groups[letter]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 10, bottom: 4),
                          child: Text(
                            letter,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _kTextDim,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        ...items.map((loc) {
                          final newCnt =
                              _newCountForLocation(loc.id);
                          final isMuted =
                              _mutedLocationIds.contains(loc.id);
                          return _CompanyNotifTile(
                            location: loc,
                            newCount: newCnt,
                            isMuted: isMuted,
                            onTap: () => setState(
                                () => _adminSelectedLocationId = loc.id),
                            onMuteTap: () => _showMuteDialog(loc),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Уведомления выбранной компании (admin) ────────────────────────────────

  Widget _buildLocationAlarms(LocationModel? loc) {
    final alarms = _displayedAlarms;
    final isMuted =
        _adminSelectedLocationId != null &&
        _mutedLocationIds.contains(_adminSelectedLocationId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Шапка ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: Color(0x4D323232),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Кнопка назад
                  GestureDetector(
                    onTap: () => setState(
                        () => _adminSelectedLocationId = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _kCard2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kBorder),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 14, color: _kTextDim),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loc?.name ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Кнопка отключения уведомлений
                  if (loc != null)
                    GestureDetector(
                      onTap: () => _showMuteDialog(loc),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isMuted
                              ? _kRed.withOpacity(0.12)
                              : _kCard2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isMuted
                                ? _kRed.withOpacity(0.45)
                                : _kBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMuted
                                  ? Icons.notifications_off_outlined
                                  : Icons.notifications_outlined,
                              size: 14,
                              color: isMuted ? _kRed : _kTextDim,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isMuted ? 'Выкл' : 'Вкл',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMuted ? _kRed : _kTextDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Сортировка
                  _sortMenuBtn(),
                ],
              ),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 10),
            ],
          ),
        ),

        // Предупреждение если уведомления отключены
        if (isMuted)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kRed.withOpacity(0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.notifications_off_outlined,
                    size: 14, color: _kRed),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Уведомления для этой компании отключены',
                    style: TextStyle(
                        fontSize: 12,
                        color: _kRed,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        // ── Список ─────────────────────────────────────────────────────────
        Expanded(child: _alarmList(alarms, canAct: true)),
      ],
    );
  }

  // ── Вид обычного пользователя ─────────────────────────────────────────────

  Widget _buildUserView() {
    final canAct = widget.repo.role != UserRole.viewer;
    final alarms = _displayedAlarms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Шапка ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: Color(0x4D323232),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Уведомления',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_newCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kRedBg,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: _kRed.withOpacity(0.5)),
                      ),
                      child: Text(
                        '$_newCount новых',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kRed,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  const Spacer(),
                  _sortMenuBtn(),
                ],
              ),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 10),
            ],
          ),
        ),

        // ── Список ─────────────────────────────────────────────────────────
        Expanded(child: _alarmList(alarms, canAct: canAct)),
      ],
    );
  }

  // ── Переиспользуемые части UI ─────────────────────────────────────────────

  Widget _sortMenuBtn() {
    return PopupMenuButton<_SortOrder>(
      color: Theme.of(context).colorScheme.surface,
      tooltip: 'Сортировка',
      icon: const Text(
        'СОРТИРОВКА',
        style: TextStyle(
          fontSize: 10,
          color: _kTextDim,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
      initialValue: _sortOrder,
      onSelected: (v) => setState(() => _sortOrder = v),
      itemBuilder: (_) => _SortOrder.values
          .map((o) => PopupMenuItem(
                value: o,
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _sortOrder == o
                            ? _kCyan
                            : Colors.transparent,
                        border: Border.all(
                          color: _sortOrder == o
                              ? _kCyan
                              : Colors.white38,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      o.label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children: [
          _FilterChip(
            label: 'Все',
            selected: _filterStatus == null,
            color: _kCyan,
            onTap: () => setState(() => _filterStatus = null),
          ),
          ...AlarmStatus.values.map((s) => _FilterChip(
                label: _statusLabel(s),
                selected: _filterStatus == s,
                color: _statusColor(s),
                onTap: () => setState(() =>
                    _filterStatus = _filterStatus == s ? null : s),
              )),
        ],
      ),
    );
  }

  Widget _alarmList(List<AlarmModel> alarms, {required bool canAct}) {
    if (alarms.isEmpty) {
      return const Center(
        child: Text(
          'Событий нет',
          style: TextStyle(color: _kTextDim, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: alarms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final alarm = alarms[index];
        return _AlarmCard(
          alarm: alarm,
          canAct: canAct,
          statusColor: _statusColor(alarm.status),
          statusBg: _statusBg(alarm.status),
          statusLabel: _statusLabel(alarm.status),
          onAcknowledge: () => _showActionDialog(
            alarm: alarm,
            newStatus: 'acknowledged',
            actionLabel: 'Взять в работу',
            hintText: 'Опишите, что предпринимается...',
            accentColor: _kOrange,
          ),
          onResolve: () => _showActionDialog(
            alarm: alarm,
            newStatus: 'resolved',
            actionLabel: 'Закрыть событие',
            hintText: 'Опишите, как проблема была решена...',
            accentColor: _kGreen,
          ),
        );
      },
    );
  }
}

// ── Плитка компании в списке уведомлений ─────────────────────────────────────

class _CompanyNotifTile extends StatelessWidget {
  const _CompanyNotifTile({
    required this.location,
    required this.newCount,
    required this.isMuted,
    required this.onTap,
    required this.onMuteTap,
  });

  final LocationModel location;
  final int newCount;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onMuteTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMuted ? _kRed.withOpacity(0.3) : _kBorder,
          ),
        ),
        child: Row(
          children: [
            // Иконка компании
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isMuted
                    ? _kRed.withOpacity(0.08)
                    : _kCyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isMuted
                      ? _kRed.withOpacity(0.25)
                      : _kCyan.withOpacity(0.25),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.business_outlined,
                size: 18,
                color: isMuted ? _kRed : _kCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.name,
                    style: TextStyle(
                      color: isMuted ? _kTextDim : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isMuted ? 'Уведомления отключены' : 'Нажмите чтобы посмотреть',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMuted ? _kRed : _kTextDim,
                    ),
                  ),
                ],
              ),
            ),
            // Бейдж новых уведомлений
            if (newCount > 0 && !isMuted) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kRedBg,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _kRed.withOpacity(0.45)),
                ),
                child: Text(
                  '$newCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Кнопка отключения/включения уведомлений
            GestureDetector(
              onTap: onMuteTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Icon(
                  isMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  size: 18,
                  color: isMuted ? _kRed : _kTextDim,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: _kTextDim),
          ],
        ),
      ),
    );
  }
}

// ── Карточка события ──────────────────────────────────────────────────────────

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.canAct,
    required this.statusColor,
    required this.statusBg,
    required this.statusLabel,
    required this.onAcknowledge,
    required this.onResolve,
  });

  final AlarmModel alarm;
  final bool canAct;
  final Color statusColor;
  final Color statusBg;
  final String statusLabel;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x4D323232),
          border: Border.all(color: _kBorder),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              alarm.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color:
                                      statusColor.withOpacity(0.45)),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (alarm.description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          alarm.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextDim,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (alarm.comment != null &&
                          alarm.comment!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x334B4B4B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alarm.status == AlarmStatus.resolved
                                    ? 'КОММЕНТАРИЙ ПРИ ЗАКРЫТИИ'
                                    : 'КОММЕНТАРИЙ ОПЕРАТОРА',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: _kTextDim,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alarm.comment!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (canAct &&
                          alarm.status != AlarmStatus.resolved) ...[
                        const SizedBox(height: 10),
                        Container(height: 1, color: _kBorder),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            if (alarm.status == AlarmStatus.newAlarm)
                              _ActionBtn(
                                label: 'В РАБОТУ',
                                color: _kOrange,
                                onTap: onAcknowledge,
                              ),
                            _ActionBtn(
                              label: 'РЕШЕНО',
                              color: _kGreen,
                              filled: true,
                              onTap: onResolve,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Фильтр-чип ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color:
              selected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color.withOpacity(0.55) : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: selected ? color : _kTextDim,
          ),
        ),
      ),
    );
  }
}

// ── Кнопка действия ──────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:
              filled ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}