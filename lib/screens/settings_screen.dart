import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Вспомогательные цвета профиля (без зависимости от AppColors)
// ─────────────────────────────────────────────────────────────────────────────

// ── Фирменная палитра ─────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0A0A0A);   // фон
const _kCard    = Color(0x4D323232);   // #3232324D блоки
const _kCard2   = Color(0x334B4B4B);   // #4B4B4B33 вложенные
const _kBorder  = Color(0xFF19282B);   // бордер
const _kAccent  = Color(0xFFFFD550);   // жёлтый акцент
const _kCyan    = Color(0xFF07BCD4);   // голубой
const _kGreen   = Color(0xFF01E676);   // зелёный
const _kRed     = Color(0xFFFF5252);   // красный
const _kYellowBg= Color(0xFF312C1C);   // фон жёлтых бейджей
const _kRedBg   = Color(0xFF321C1B);   // фон красных бейджей
const _kTextDim = Color(0xFF7A8A8E);   // приглушённый текст

// ─────────────────────────────────────────────────────────────────────────────
// Главный виджет
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repo,
    required this.onRefresh,
    this.onLogout,
    this.onToggleTheme,
  });

  final AppRepository repo;
  final Future<void> Function() onRefresh;
  final VoidCallback? onLogout;
  final VoidCallback? onToggleTheme;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Вспомогательные ────────────────────────────────────────────────────────

  String _roleLabel(String role) => switch (role) {
        'admin' => 'Администратор',
        'editor' => 'Редактор',
        _ => 'Читатель',
      };

  String _roleFromEnum(UserRole r) => switch (r) {
        UserRole.admin => 'admin',
        UserRole.editor => 'editor',
        UserRole.viewer => 'viewer',
      };

  Color _roleColor(String role) => switch (role) {
        'admin' => _kAccent,   // жёлтый — администратор
        'editor' => _kCyan,    // голубой — редактор
        _ => _kGreen,          // зелёный — читатель
      };

  String _initials(String fullName, String username) {
    final name = fullName.isNotEmpty ? fullName : username;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // ── Диалог настроек приложения (тема + смена пароля) ─────────────────────

  Future<void> _showAppSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final provider  = AppThemeProvider.maybeOf(ctx);
          final isDark    = provider?.isDark ?? true;

          return _DarkDialog(
            title: 'Настройки',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Тема ───────────────────────────────────────────────────
                const _SectionLabel('ОФОРМЛЕНИЕ'),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    widget.onToggleTheme?.call();
                    setSt(() {});
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _kCyan.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kCyan.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          color: _kCyan, size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isDark ? 'Переключить на светлую тему'
                                   : 'Переключить на тёмную тему',
                            style: const TextStyle(
                              color: _kCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Визуальный переключатель
                        Container(
                          width: 42, height: 24,
                          decoration: BoxDecoration(
                            color: isDark
                                ? _kBorder
                                : _kCyan.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _kCyan.withOpacity(0.5)),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 180),
                            alignment: isDark
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              width: 18, height: 18,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3),
                              decoration: BoxDecoration(
                                color: _kCyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ],
            ),
            actions: [
              _DarkTextButton(
                label: 'Закрыть',
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Диалог редактирования профиля ──────────────────────────────────────────

  Future<void> _showEditProfileDialog() async {
    final nameCtrl =
        TextEditingController(text: widget.repo.currentUserFullName ?? '');
    final emailCtrl =
        TextEditingController(text: widget.repo.currentUserEmail ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => _DarkDialog(
        title: 'Редактировать профиль',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DarkField(controller: nameCtrl, label: 'ФИО'),
            const SizedBox(height: 12),
            _DarkField(
              controller: emailCtrl,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          _DarkTextButton(
            label: 'Отмена',
            onTap: () => Navigator.pop(ctx),
          ),
          _DarkFilledButton(
            label: 'Сохранить',
            onTap: () async {
              final err = await widget.repo.updateProfile(
                fullName: nameCtrl.text.trim(),
                email: emailCtrl.text.trim().isEmpty
                    ? null
                    : emailCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _snack(err ?? 'Профиль обновлён');
              if (err == null) {
                await widget.onRefresh();
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  // ── Диалог добавления пользователя ─────────────────────────────────────────

  Future<void> _showCreateUserDialog() async {
    final loginCtrl  = TextEditingController();
    final passCtrl   = TextEditingController();
    final nameCtrl   = TextEditingController();
    final emailCtrl  = TextEditingController();
    final isAdmin    = widget.repo.role == UserRole.admin;
    final isEditor   = widget.repo.role == UserRole.editor;

    // Доступные роли по гайду:
    // admin → admin, editor, viewer
    // editor → editor, viewer
    final availableRoles = <String>[
      if (isAdmin) 'admin',
      'editor',
      'viewer',
    ];
    String roleName = 'viewer';
    int? selectedLocation = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;
    bool obscurePass = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          // Editor не выбирает location_id — бэк назначает автоматически
          final showLocation = isAdmin && widget.repo.locations.isNotEmpty;

          return _DarkDialog(
            title: 'Новый сотрудник',
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ФИО
                  _DarkField(controller: nameCtrl, label: 'ФИО *'),
                  const SizedBox(height: 10),

                  // Логин
                  _DarkField(controller: loginCtrl, label: 'Логин *'),
                  const SizedBox(height: 10),

                  // Пароль с кнопкой показать/скрыть
                  _DarkField(
                    controller: passCtrl,
                    label: 'Пароль *',
                    obscure: obscurePass,
                    suffix: GestureDetector(
                      onTap: () => setSt(() => obscurePass = !obscurePass),
                      child: Icon(
                        obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: _kTextDim, size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Email
                  _DarkField(
                    controller: emailCtrl,
                    label: 'Email (необязательно)',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  // Роль — выбор по правам
                  _DarkDropdown<String>(
                    label: 'Роль *',
                    value: roleName,
                    items: availableRoles.map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(switch (r) {
                        'admin'  => 'Администратор (admin)',
                        'editor' => 'Редактор (editor)',
                        _        => 'Читатель (viewer)',
                      }),
                    )).toList(),
                    onChanged: (v) => setSt(() => roleName = v ?? roleName),
                  ),

                  // Локация — только для admin (у editor назначается автоматически)
                  if (showLocation) ...[
                    const SizedBox(height: 10),
                    _DarkDropdown<int>(
                      label: 'Локация',
                      value: selectedLocation,
                      items: widget.repo.locations
                          .map((e) => DropdownMenuItem<int>(
                                value: e.id,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (v) => setSt(() => selectedLocation = v),
                    ),
                  ],

                  // Подсказка для editor
                  if (isEditor) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kCyan.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kCyan.withOpacity(0.25)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 13, color: _kCyan),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Локация будет назначена автоматически',
                              style: TextStyle(color: _kCyan, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              _DarkTextButton(
                  label: 'Отмена', onTap: () => Navigator.pop(ctx)),
              _DarkFilledButton(
                label: 'Создать',
                onTap: () async {
                  final login    = loginCtrl.text.trim();
                  final pass     = passCtrl.text.trim();
                  final name     = nameCtrl.text.trim();
                  final email    = emailCtrl.text.trim();

                  // Валидация по гайду
                  if (name.isEmpty) {
                    _snack('Введите ФИО');
                    return;
                  }
                  if (login.isEmpty) {
                    _snack('Введите логин');
                    return;
                  }
                  if (pass.isEmpty) {
                    _snack('Введите пароль');
                    return;
                  }
                  if (email.isNotEmpty && !email.contains('@')) {
                    _snack('Введите корректный Email');
                    return;
                  }

                  final err = await widget.repo.createUser(
                    username:   login,
                    password:   pass,
                    fullName:   name,
                    roleName:   roleName,
                    // Editor: location_id не передаём, бэк назначит сам
                    locationId: isAdmin ? selectedLocation : null,
                    email:      email.isEmpty ? null : email,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _snack(err ?? 'Сотрудник успешно создан');
                  if (err == null) {
                    await widget.onRefresh();
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final username = repo.currentUser ?? '—';
    final fullName = repo.currentUserFullName ?? username;
    final email = repo.currentUserEmail;
    final roleStr = _roleFromEnum(repo.role);

    return Container(
      color: _kBg,
      child: Column(
        children: [
          // ── Шапка профиля ───────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              border: const Border(
                bottom: BorderSide(color: _kBorder),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    // Аватар
                    _Avatar(initials: _initials(fullName, username)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (email != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: const TextStyle(
                                  color: _kTextDim, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: roleStr == 'admin'
                                  ? _kYellowBg
                                  : roleStr == 'editor'
                                      ? _kBorder
                                      : const Color(0xFF0D2B1F),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: _roleColor(roleStr).withOpacity(0.5)),
                            ),
                            child: Text(
                              _roleLabel(roleStr),
                              style: TextStyle(
                                fontSize: 11,
                                color: _roleColor(roleStr),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Кнопка редактировать профиль
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: _kCyan, size: 20),
                      tooltip: 'Редактировать профиль',
                      onPressed: _showEditProfileDialog,
                    ),
                    // Иконки: Настройки и Выйти рядом с карандашом
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: _kTextDim, size: 20),
                      tooltip: 'Настройки приложения',
                      onPressed: _showAppSettingsDialog,
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout,
                          color: _kRed, size: 20),
                      tooltip: 'Выйти',
                      onPressed: () {
                        repo.logout();
                        widget.onLogout?.call();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Таб-бар
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: _kCyan,
                  indicatorWeight: 2,
                  labelColor: _kCyan,
                  unselectedLabelColor: _kTextDim,
                  dividerColor: _kBorder,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: [
                    Tab(
                      text: repo.role != UserRole.viewer
                          ? 'Пользователи (${repo.subordinateUsers.length})'
                          : 'Команда',
                    ),
                    const Tab(text: 'История действий'),
                  ],
                ),
              ],
            ),
          ),

          // ── Содержимое табов ─────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _UsersTab(
                  repo: repo,
                  onAddUser: repo.role != UserRole.viewer
                      ? _showCreateUserDialog
                      : null,
                  roleLabel: _roleLabel,
                  roleColor: _roleColor,
                  initials: _initials,
                ),
                _AuditTab(repo: repo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Таб: Пользователи
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab({
    required this.repo,
    required this.onAddUser,
    required this.roleLabel,
    required this.roleColor,
    required this.initials,
  });

  final AppRepository repo;
  final VoidCallback? onAddUser;
  final String Function(String) roleLabel;
  final Color Function(String) roleColor;
  final String Function(String, String) initials;

  @override
  Widget build(BuildContext context) {
    final users = repo.subordinateUsers;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Заголовок + кнопка добавить
        Row(
          children: [
            const Text(
              'Пользователи',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (onAddUser != null)
              GestureDetector(
                onTap: onAddUser,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kCyan.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kCyan.withOpacity(0.35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_outlined,
                          size: 14, color: _kCyan),
                      SizedBox(width: 6),
                      Text(
                        'Добавить',
                        style: TextStyle(
                          fontSize: 12,
                          color: _kCyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (users.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Нет подчинённых пользователей',
                style: const TextStyle(color: _kTextDim),
              ),
            ),
          )
        else
          // Заголовок таблицы
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kCard2,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: _kBorder),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Пользователь',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kTextDim,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Email',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kTextDim,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    'Роль',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kTextDim,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

        ...users.asMap().entries.map((entry) {
          final i = entry.key;
          final u = entry.value;
          final isLast = i == users.length - 1;
          return _UserRow(
            user: u,
            isLast: isLast,
            roleLabel: roleLabel(u.role),
            roleColor: roleColor(u.role),
            userInitials: initials(u.fullName, u.username),
          );
        }),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isLast,
    required this.roleLabel,
    required this.roleColor,
    required this.userInitials,
  });

  final UserModel user;
  final bool isLast;
  final String roleLabel;
  final Color roleColor;
  final String userInitials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(
          left: const BorderSide(color: _kBorder),
          right: const BorderSide(color: _kBorder),
          bottom: BorderSide(
              color: isLast ? _kBorder : const Color(0xFF19282B)),
        ),
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(8))
            : BorderRadius.zero,
      ),
      child: Row(
        children: [
          // Аватар + имя
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: roleColor.withOpacity(0.2),
                  child: Text(
                    userInitials,
                    style: TextStyle(
                      fontSize: 11,
                      color: roleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.fullName.isNotEmpty ? user.fullName : user.username,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Email
          Expanded(
            flex: 2,
            child: Text(
              user.email ?? '—',
              style:
                  const TextStyle(color: _kTextDim, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Роль
          SizedBox(
            width: 72,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor == _kAccent
                    ? _kYellowBg
                    : roleColor == _kRed
                        ? _kRedBg
                        : _kBorder,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: roleColor.withOpacity(0.4)),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: roleColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Таб: История действий
// ─────────────────────────────────────────────────────────────────────────────

class _AuditTab extends StatefulWidget {
  const _AuditTab({required this.repo});
  final AppRepository repo;

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.loadAuditLog();
  }

  Future<void> _reload() {
    setState(() {
      _future = widget.repo.loadAuditLog();
    });
    return _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kCyan, strokeWidth: 2),
          );
        }

        final entries = widget.repo.audit;

        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, color: _kTextDim, size: 36),
                const SizedBox(height: 10),
                const Text(
                  'История пуста',
                  style: TextStyle(color: _kTextDim),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _reload,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: _kCyan.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Обновить',
                      style: TextStyle(color: _kCyan, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: _kCyan,
          backgroundColor: _kCard,
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _kBorder),
            itemBuilder: (context, i) {
              final e = entries[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Точка-индикатор — голубая
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 12),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kCyan,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.action,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${e.user}  •  ${e.time}',
                            style: const TextStyle(
                                color: _kTextDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Виджеты-компоненты
// ─────────────────────────────────────────────────────────────────────────────

// ── Кнопка переключения темы ──────────────────────────────────────────────────

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({this.onToggle});
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final provider = AppThemeProvider.maybeOf(context);
    final isDark = provider?.isDark ?? true;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _kCyan.withOpacity(0.4)),
          color: _kCyan.withOpacity(0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 16,
              color: _kCyan,
            ),
            const SizedBox(width: 6),
            Text(
              isDark ? 'Светлая тема' : 'Тёмная тема',
              style: const TextStyle(
                color: _kCyan,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: _kTextDim,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kYellowBg,
        border: Border.all(color: _kAccent.withOpacity(0.6), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: _kAccent,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.onTap,
    this.color = _kTextDim,
  });
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Тёмный диалог ────────────────────────────────────────────────────────────

class _DarkDialog extends StatelessWidget {
  const _DarkDialog({
    required this.title,
    required this.content,
    required this.actions,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
      ),
      content: content,
      actions: actions,
    );
  }
}

// ── Тёмное поле ввода ─────────────────────────────────────────────────────────

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextDim, fontSize: 13),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kCyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// ── Тёмный дропдаун ──────────────────────────────────────────────────────────

class _DarkDropdown<T> extends StatelessWidget {
  const _DarkDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextDim, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kCyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

// ── Кнопки диалога ───────────────────────────────────────────────────────────

class _DarkTextButton extends StatelessWidget {
  const _DarkTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label,
          style: const TextStyle(color: _kTextDim, fontSize: 13)),
    );
  }
}

class _DarkFilledButton extends StatelessWidget {
  const _DarkFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _kCyan,
        foregroundColor: Colors.black,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child:
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}