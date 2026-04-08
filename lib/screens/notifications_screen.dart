import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: repo.alarms
          .map(
            (alarm) => Card(
              color: AppColors.card,
              child: ListTile(
                title: Text(alarm.title),
                subtitle: Text(alarm.description),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    TextButton(
                      onPressed: repo.role == UserRole.viewer
                          ? null
                          : () async {
                              final err = await repo.updateAlarm(alarm.id, 'acknowledged', 'Взято в работу');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'OK')));
                              }
                              await onRefresh();
                            },
                      child: const Text('В работу'),
                    ),
                    TextButton(
                      onPressed: repo.role == UserRole.viewer
                          ? null
                          : () async {
                              final err = await repo.updateAlarm(alarm.id, 'resolved', 'Решено оператором');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'OK')));
                              }
                              await onRefresh();
                            },
                      child: const Text('Решено'),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
