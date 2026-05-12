part of '../notifications_screen.dart';

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
          color: AppColors.of(context).card,
          border: Border.all(color: AppColors.of(context).border),
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
                              style: TextStyle(
                                color: AppColors.of(context).textMain,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: statusColor.withOpacity(0.45),
                              ),
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
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.of(context).textDim,
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
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).card2,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.of(context).border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alarm.status == AlarmStatus.resolved
                                    ? 'КОММЕНТАРИЙ ПРИ ЗАКРЫТИИ'
                                    : 'КОММЕНТАРИЙ ОПЕРАТОРА',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.of(context).textDim,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alarm.comment!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.of(context).textMain,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (canAct && alarm.status != AlarmStatus.resolved) ...[
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: AppColors.of(context).border,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            if (alarm.status == AlarmStatus.newAlarm)
                              _ActionBtn(
                                label: 'В РАБОТУ',
                                color: kOrange,
                                onTap: onAcknowledge,
                              ),
                            _ActionBtn(
                              label: 'РЕШЕНО',
                              color: kGreen,
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
