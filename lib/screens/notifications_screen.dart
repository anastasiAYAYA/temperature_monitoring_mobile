import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
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

  // ── Данные ───────────────────────────────────────────────────────────────

  List<AlarmModel> get _displayedAlarms {
    var list = widget.repo.alarms.where((a) {
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

  int get _newCount =>
      widget.repo.alarms.where((a) => a.status == AlarmStatus.newAlarm).length;

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
                        style: const TextStyle(fontSize: 12, color: _kTextDim),
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
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(color: _kTextDim, fontSize: 13),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена', style: TextStyle(color: _kTextDim)),
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
                  style: const TextStyle(fontWeight: FontWeight.w700)),
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
    // Сначала перерисовываем UI с локально сохранённым комментарием,
    // затем делаем рефреш в фоне (он восстановит комментарий даже если
    // бэкенд не вернул user_comment в списке).
    if (mounted) setState(() {});
    await widget.onRefresh();
    if (mounted) setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canAct = widget.repo.role != UserRole.viewer;
    final alarms = _displayedAlarms;

    // Оборачиваем в тёмную тему чтобы наследованные стили текста были белыми
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _kBg,
        colorScheme: Theme.of(context).colorScheme,
      ),
      child: Container(
        color: _kBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Шапка ────────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Color(0x4D323232),
                border: Border(bottom: BorderSide(color: _kBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок + счётчик + сортировка
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
                            border: Border.all(
                                color: _kRed.withOpacity(0.5)),
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
                      // Сортировка
                      PopupMenuButton<_SortOrder>(
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
                        onSelected: (v) =>
                            setState(() => _sortOrder = v),
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
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Фильтр-чипы
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: 6,
                      children: [
                        _FilterChip(
                          label: 'Все',
                          selected: _filterStatus == null,
                          color: _kCyan,
                          onTap: () =>
                              setState(() => _filterStatus = null),
                        ),
                        ...AlarmStatus.values.map((s) => _FilterChip(
                              label: _statusLabel(s),
                              selected: _filterStatus == s,
                              color: _statusColor(s),
                              onTap: () => setState(() =>
                                  _filterStatus =
                                      _filterStatus == s ? null : s),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            // ── Список ───────────────────────────────────────────────────────
            Expanded(
              child: alarms.isEmpty
                  ? const Center(
                      child: Text(
                        'Событий нет',
                        style: TextStyle(
                          color: _kTextDim,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: alarms.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
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
                            hintText:
                                'Опишите, как проблема была решена...',
                            accentColor: _kGreen,
                          ),
                        );
                      },
                    ),
            ),
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
    // ClipRRect + однородная рамка — обходим ограничение Flutter,
    // запрещающее borderRadius при разных цветах сторон границы.
    // Цветная полоска слева реализована отдельным Container внутри Row.
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
              // Цветная полоска по статусу
              Container(width: 4, color: statusColor),
              // Контент карточки
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Заголовок + бейдж ──────────────────────────────
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
                                  color: statusColor.withOpacity(0.45)),
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

                      // ── Описание ───────────────────────────────────────
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

                      // ── Комментарий ────────────────────────────────────
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

                      // ── Кнопки ─────────────────────────────────────────
                      if (canAct && alarm.status != AlarmStatus.resolved) ...[
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: filled
              ? color.withOpacity(0.12)
              : Colors.transparent,
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