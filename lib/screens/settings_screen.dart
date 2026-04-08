import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/app_repository.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;

  Future<void> _showCreateUserDialog(BuildContext context) async {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String roleName = 'viewer';
    int? selectedLocation = repo.locations.isNotEmpty ? repo.locations.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить сотрудника'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: 'Логин')),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Пароль')),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ФИО')),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: roleName,
                  items: [
                    const DropdownMenuItem(value: 'viewer', child: Text('viewer')),
                    if (repo.role == UserRole.admin) const DropdownMenuItem(value: 'editor', child: Text('editor')),
                  ],
                  onChanged: (v) => setDialogState(() => roleName = v ?? roleName),
                  decoration: const InputDecoration(labelText: 'Роль'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedLocation,
                  items: repo.locations
                      .map((e) => DropdownMenuItem<int>(value: e.id, child: Text('${e.id}: ${e.name}')))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedLocation = v),
                  decoration: const InputDecoration(labelText: 'Локация'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                final err = await repo.createUser(
                  username: loginCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  fullName: nameCtrl.text.trim(),
                  roleName: roleName,
                  locationId: selectedLocation,
                  email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Сотрудник создан')));
                if (err == null) await onRefresh();
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
    final baseUrlCtrl = TextEditingController(text: repo.baseUrl);
    final canManageUsers = repo.role == UserRole.admin || repo.role == UserRole.editor;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Профиль', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ListTile(title: Text(repo.currentUser ?? '-'), subtitle: Text('Роль: ${repo.role.name}')),
        TextField(controller: baseUrlCtrl, decoration: const InputDecoration(labelText: 'Base URL API')),
        FilledButton(
          onPressed: () async {
            repo.baseUrl = baseUrlCtrl.text.trim();
            await onRefresh();
          },
          child: const Text('Применить URL'),
        ),
        const SizedBox(height: 8),
        if (canManageUsers)
          FilledButton.icon(
            onPressed: () => _showCreateUserDialog(context),
            icon: const Icon(Icons.person_add),
            label: Text(repo.role == UserRole.admin ? 'Добавить editor/viewer' : 'Добавить viewer'),
          ),
        const SizedBox(height: 8),
        Text(
          repo.role == UserRole.admin ? 'Пользователи в подчинении (editor/viewer)' : 'Пользователи в подчинении (viewer)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        ...repo.subordinateUsers.map(
          (u) => ListTile(
            title: Text(u.fullName.isEmpty ? u.username : u.fullName),
            subtitle: Text('${u.role} • ${u.email ?? 'без email'}'),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Журнал аудита и история действий', style: TextStyle(fontWeight: FontWeight.bold)),
        ...repo.audit.map((e) => ListTile(title: Text(e.action), subtitle: Text('${e.user} • ${e.time}'))),
      ],
    );
  }
}
