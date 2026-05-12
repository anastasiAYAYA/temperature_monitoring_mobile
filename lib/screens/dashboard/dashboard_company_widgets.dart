part of '../dashboard_screen.dart';

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.name,
    required this.sensorCount,
    required this.onTap,
    required this.c,
  });
  final String name;
  final int sensorCount;
  final VoidCallback onTap;
  final AppScheme c;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.cyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.cyan.withOpacity(0.25)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.business_outlined, size: 18, color: c.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: c.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sensorCount датч.',
                    style: TextStyle(fontSize: 11, color: c.textDim),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.textDim),
          ],
        ),
      ),
    );
  }
}

// ── Секционный заголовок ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.textDim,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: c.card2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              color: c.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
