part of '../notifications_screen.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.of(context).card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMuted
                ? kRed.withOpacity(0.3)
                : AppColors.of(context).border,
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
                    ? kRed.withOpacity(0.08)
                    : kCyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isMuted
                      ? kRed.withOpacity(0.25)
                      : kCyan.withOpacity(0.25),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.business_outlined,
                size: 18,
                color: isMuted ? kRed : kCyan,
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
                      color: isMuted
                          ? AppColors.of(context).textDim
                          : AppColors.of(context).textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isMuted
                        ? 'Уведомления отключены'
                        : 'Нажмите чтобы посмотреть',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMuted ? kRed : AppColors.of(context).textDim,
                    ),
                  ),
                ],
              ),
            ),
            // Бейдж новых уведомлений
            if (newCount > 0 && !isMuted) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.of(context).redBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kRed.withOpacity(0.45)),
                ),
                child: Text(
                  '$newCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: kRed,
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
                  color: isMuted ? kRed : AppColors.of(context).textDim,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.of(context).textDim,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Карточка события ──────────────────────────────────────────────────────────
