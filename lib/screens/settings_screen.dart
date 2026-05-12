import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/audit_entry.dart';
import '../models/location_details.dart';
import '../models/location_model.dart';
import '../models/sensor_model.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart' show AppThemeProvider;

/// Настройки и администрирование: профиль, команда, для admin — список компаний и
/// детали локации через `GET /locations/{id}/details` ([loadLocationDetails] в репозитории).
///
/// **Роли:** admin видит все компании и агрегированные данные; editor/viewer опираются на
/// `subordinateUsers` и текущего пользователя ([_loadAllCompanyUsers]).

part 'settings/admin_company_widgets.dart';
part 'settings/admin_structure_panel.dart';
part 'settings/users_tab.dart';
part 'settings/audit_tab.dart';
part 'settings/common_widgets.dart';

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

  int? _adminSelectedLocationId;
  String _adminSection = 'users';

  final Map<int, LocationDetails> _locationDetailsCache = {};
  bool _locationDetailsLoading = false;
  String? _locationDetailsError;

  final Map<int, int> _companyUserCountCache = {};

  /// {'editor': N, 'viewer': N} по каждой локации — для подписи под названием компании.
  final Map<int, Map<String, int>> _companyRoleCountCache = {};
  bool _companyCountsLoading = false;

  List<UserModel> _allCompanyUsers = [];
  bool _allCompanyUsersLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    if (widget.repo.role != UserRole.admin) {
      _loadAllCompanyUsers();
    } else {
      _loadAllCompanyCounts();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Локальный парсер JSON-списка ─────────────────────────────────────────

  /// Ответы API могут быть массивом или объектом `{ "data": [...] }` — приводим к списку.
  List<dynamic> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // ── Загрузка кол-ва сотрудников для всех компаний (admin) ───────────────
  // Admin видит GET /users/ — считаем editor и viewer по локациям, admin скрыт.
  Future<void> _loadAllCompanyCounts() async {
    if (_companyCountsLoading) return;
    setState(() => _companyCountsLoading = true);
    try {
      final r = await widget.repo.get('/users/?skip=0&limit=500');
      if (r.statusCode == 200) {
        final raw = _parseList(r.body).cast<Map<String, dynamic>>();
        final counts = <int, int>{};
        final roleCounts = <int, Map<String, int>>{};
        for (final u in raw) {
          final role = u['role'] as String? ?? '';
          if (role == 'admin') continue; // admin не показываем нигде
          final locId = (u['location_id'] as num?)?.toInt();
          if (locId == null) continue;
          counts[locId] = (counts[locId] ?? 0) + 1;
          roleCounts.putIfAbsent(locId, () => {'editor': 0, 'viewer': 0});
          if (role == 'editor') {
            roleCounts[locId]!['editor'] =
                (roleCounts[locId]!['editor'] ?? 0) + 1;
          } else {
            roleCounts[locId]!['viewer'] =
                (roleCounts[locId]!['viewer'] ?? 0) + 1;
          }
        }
        if (mounted) {
          setState(() {
            _companyUserCountCache.addAll(counts);
            _companyRoleCountCache.addAll(roleCounts);
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _companyCountsLoading = false);
  }

  // ── Список пользователей для editor/viewer ────────────────────────────────
  // Источник: GET /users/my-location (загружен в repo.subordinateUsers при loadAll).
  // Ветвление по роли сделано сразу в loadSubordinates — здесь только сборка UI-списка.
  // Admin в списке никогда не появляется (отфильтрован в loadSubordinates).

  Future<void> _loadAllCompanyUsers() async {
    setState(() => _allCompanyUsersLoading = true);
    final repo = widget.repo;
    final List<UserModel> result = [];

    // Себя — первым (из repo.currentUser*, role строго из /users/me)
    if (repo.currentUserId != null) {
      result.add(
        UserModel(
          id: repo.currentUserId!,
          username: repo.currentUser ?? '',
          fullName: repo.currentUserFullName ?? '',
          role: _roleFromEnum(repo.role),
          email: repo.currentUserEmail,
        ),
      );
    }

    // Коллеги из своей локации — subordinateUsers уже без admin и без себя
    for (final u in repo.subordinateUsers) {
      result.add(u);
    }

    // Сортировка: editor → viewer → по имени
    result.sort((a, b) {
      final order = {'editor': 0, 'viewer': 1};
      final ro = (order[a.role] ?? 2).compareTo(order[b.role] ?? 2);
      if (ro != 0) return ro;
      final na = (a.fullName.isNotEmpty ? a.fullName : a.username)
          .toLowerCase();
      final nb = (b.fullName.isNotEmpty ? b.fullName : b.username)
          .toLowerCase();
      return na.compareTo(nb);
    });

    if (mounted) {
      setState(() {
        _allCompanyUsers = result;
        _allCompanyUsersLoading = false;
      });
    }
  }

  // ── Загрузка деталей локации для admin (один запрос) ─────────────────────
  Future<void> _loadLocationDetails(
    int locationId, {
    bool forceReload = false,
  }) async {
    if (!forceReload && _locationDetailsCache.containsKey(locationId)) return;
    setState(() {
      _locationDetailsLoading = true;
      _locationDetailsError = null;
    });
    final result = await widget.repo.loadLocationDetails(locationId);
    if (!mounted) return;
    if (result.data != null) {
      _companyUserCountCache[locationId] = result.data!.users.length;
      setState(() {
        _locationDetailsCache[locationId] = result.data!;
        _locationDetailsLoading = false;
      });
    } else {
      setState(() {
        _locationDetailsError = result.error;
        _locationDetailsLoading = false;
      });
    }
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

  Color _roleColor(AppScheme sch, String role) => switch (role) {
    'admin' => sch.accent,
    'editor' => kCyan,
    _ => kGreen,
  };

  String _initials(String fullName, String username) {
    final name = fullName.isNotEmpty ? fullName : username;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // ── Диалог настроек приложения ─────────────────────────────────────────────

  Future<void> _showAppSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final provider = AppThemeProvider.maybeOf(ctx);
          final isDark = provider?.isDark ?? true;

          return _DarkDialog(
            title: 'Настройки',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: kCyan.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kCyan.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          color: kCyan,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isDark
                                ? 'Переключить на светлую тему'
                                : 'Переключить на тёмную тему',
                            style: const TextStyle(
                              color: kCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.of(context).border
                                : kCyan.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kCyan.withOpacity(0.5)),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 180),
                            alignment: isDark
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: const BoxDecoration(
                                color: kCyan,
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
    final nameCtrl = TextEditingController(
      text: widget.repo.currentUserFullName ?? '',
    );
    final emailCtrl = TextEditingController(
      text: widget.repo.currentUserEmail ?? '',
    );

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
          _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
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
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final isAdmin = widget.repo.role == UserRole.admin;
    final isEditor = widget.repo.role == UserRole.editor;

    final availableRoles = <String>[if (isAdmin) 'admin', 'editor', 'viewer'];
    String roleName = 'viewer';
    int? selectedLocation = widget.repo.locations.isNotEmpty
        ? widget.repo.locations.first.id
        : null;
    bool obscurePass = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final showLocation = isAdmin && widget.repo.locations.isNotEmpty;

          return _DarkDialog(
            title: 'Новый сотрудник',
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DarkField(controller: nameCtrl, label: 'ФИО *'),
                  const SizedBox(height: 10),
                  _DarkField(controller: loginCtrl, label: 'Логин *'),
                  const SizedBox(height: 10),
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
                        color: AppColors.of(context).textDim,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DarkField(
                    controller: emailCtrl,
                    label: 'Email (необязательно)',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _DarkDropdown<String>(
                    label: 'Роль *',
                    value: roleName,
                    items: availableRoles
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(switch (r) {
                              'admin' => 'Администратор (admin)',
                              'editor' => 'Редактор (editor)',
                              _ => 'Читатель (viewer)',
                            }),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => roleName = v ?? roleName),
                  ),
                  if (showLocation) ...[
                    const SizedBox(height: 10),
                    _DarkDropdown<int>(
                      label: 'Локация',
                      value: selectedLocation,
                      items: widget.repo.locations
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e.id,
                              child: Text(e.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setSt(() => selectedLocation = v),
                    ),
                  ],
                  if (isEditor) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kCyan.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kCyan.withOpacity(0.25)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 13, color: kCyan),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Локация будет назначена автоматически',
                              style: TextStyle(color: kCyan, fontSize: 11),
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
              _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
              _DarkFilledButton(
                label: 'Создать',
                onTap: () async {
                  final login = loginCtrl.text.trim();
                  final pass = passCtrl.text.trim();
                  final name = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim();

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
                    username: login,
                    password: pass,
                    fullName: name,
                    roleName: roleName,
                    locationId: isAdmin ? selectedLocation : null,
                    email: email.isEmpty ? null : email,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _snack(err ?? 'Сотрудник успешно создан');
                  if (err == null) {
                    await widget.onRefresh();
                    if (_adminSelectedLocationId != null) {
                      await _loadLocationDetails(
                        _adminSelectedLocationId!,
                        forceReload: true,
                      );
                    }
                    if (widget.repo.role != UserRole.admin) {
                      await _loadAllCompanyUsers();
                    }
                    // Сбрасываем счётчики — данные изменились
                    _companyUserCountCache.clear();
                    if (widget.repo.role == UserRole.admin)
                      _loadAllCompanyCounts();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reloadAdminStructure() async {
    await widget.onRefresh();
    if (!mounted) return;
    _locationDetailsCache.clear();
    if (_adminSelectedLocationId != null) {
      await _loadLocationDetails(_adminSelectedLocationId!, forceReload: true);
    }
    if (widget.repo.role == UserRole.admin) {
      await _loadAllCompanyCounts();
    }
    if (mounted) setState(() {});
  }

  Future<void> _showRenameEntityDialog({
    required String title,
    required String initialName,
    required Future<String?> Function(String name) onSave,
  }) async {
    final ctrl = TextEditingController(text: initialName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DarkDialog(
        title: title,
        content: _DarkField(controller: ctrl, label: 'Название'),
        actions: [
          _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
          _DarkFilledButton(
            label: 'Сохранить',
            onTap: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) {
                _snack('Введите название');
                return;
              }
              final err = await onSave(name);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _snack(err ?? 'Название обновлено');
              if (err == null) await _reloadAdminStructure();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteEntity({
    required String title,
    required String message,
    required Future<String?> Function() onDelete,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DarkDialog(
        title: title,
        content: Text(
          message,
          style: TextStyle(color: AppColors.of(ctx).textMain, fontSize: 13),
        ),
        actions: [
          _DarkTextButton(label: 'Отмена', onTap: () => Navigator.pop(ctx)),
          _DarkFilledButton(
            label: 'Удалить',
            onTap: () async {
              final err = await onDelete();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _snack(err ?? 'Удалено');
              if (err == null) await _reloadAdminStructure();
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final username = repo.currentUser ?? '—';
    final fullName = repo.currentUserFullName ?? username;
    final email = repo.currentUserEmail;
    final roleStr = _roleFromEnum(repo.role);
    final sch = AppColors.of(context);

    return Container(
      color: sch.bg,
      child: Column(
        children: [
          // ── Шапка профиля ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: sch.card,
              border: Border(bottom: BorderSide(color: sch.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _Avatar(initials: _initials(fullName, username)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: TextStyle(
                              color: sch.textMain,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (email != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(
                                color: sch.textDim,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: roleStr == 'admin'
                                  ? sch.yellowBg
                                  : roleStr == 'editor'
                                  ? sch.border
                                  : sch.greenBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _roleColor(
                                  sch,
                                  roleStr,
                                ).withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              _roleLabel(roleStr),
                              style: TextStyle(
                                fontSize: 11,
                                color: _roleColor(sch, roleStr),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: kCyan, size: 20),
                      tooltip: 'Редактировать профиль',
                      onPressed: _showEditProfileDialog,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: sch.textDim,
                        size: 20,
                      ),
                      tooltip: 'Настройки приложения',
                      onPressed: _showAppSettingsDialog,
                    ),
                    IconButton(
                      icon: Icon(Icons.logout, color: kRed, size: 20),
                      tooltip: 'Выйти',
                      onPressed: () {
                        repo.logout();
                        widget.onLogout?.call();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Таб-бар только для editor/viewer ──────────────────────
                if (repo.role != UserRole.admin) ...[
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: kCyan,
                    indicatorWeight: 2,
                    labelColor: kCyan,
                    unselectedLabelColor: sch.textDim,
                    dividerColor: sch.border,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(
                        text:
                            'Сотрудники'
                            '${_allCompanyUsers.isNotEmpty ? " (${_allCompanyUsers.length})" : ""}',
                      ),
                      const Tab(text: 'История действий'),
                    ],
                  ),
                ] else ...[
                  // Для admin: breadcrumb-навигация
                  if (_adminSelectedLocationId != null)
                    _AdminBreadcrumb(
                      companyName:
                          repo.locations
                              .where((l) => l.id == _adminSelectedLocationId)
                              .firstOrNull
                              ?.name ??
                          '',
                      section: _adminSection,
                      onBack: () => setState(() {
                        _adminSelectedLocationId = null;
                        _adminSection = 'users';
                      }),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          _SectionTab(
                            label: 'Компании',
                            icon: Icons.business_outlined,
                            isActive: _adminSection != 'structure',
                            onTap: () =>
                                setState(() => _adminSection = 'users'),
                          ),
                          const SizedBox(width: 8),
                          _SectionTab(
                            label: 'Структура',
                            icon: Icons.account_tree_outlined,
                            isActive: _adminSection == 'structure',
                            onTap: () =>
                                setState(() => _adminSection = 'structure'),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),

          // ── Содержимое ────────────────────────────────────────────────────
          Expanded(
            child: repo.role == UserRole.admin
                ? _buildAdminBody()
                : _buildEditorViewerBody(repo),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Admin: тело
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAdminBody() {
    if (_adminSelectedLocationId == null) {
      if (_adminSection == 'structure') {
        return _AdminStructurePanel(
          repo: widget.repo,
          onRefresh: _reloadAdminStructure,
          onRenameLocation: (location) => _showRenameEntityDialog(
            title: 'Переименовать локацию',
            initialName: location.name,
            onSave: (name) =>
                widget.repo.renameLocation(locationId: location.id, name: name),
          ),
          onDeleteLocation: (location) => _confirmDeleteEntity(
            title: 'Удалить локацию',
            message: 'Удалить "${location.name}" и связанные данные?',
            onDelete: () => widget.repo.deleteLocation(location.id),
          ),
          onRenameUnit: (unit) => _showRenameEntityDialog(
            title: 'Переименовать блок',
            initialName: unit['name'] as String? ?? 'Блок #${unit['id']}',
            onSave: (name) => widget.repo.renameControlUnit(
              unitId: (unit['id'] as num).toInt(),
              name: name,
            ),
          ),
          onDeleteUnit: (unit) => _confirmDeleteEntity(
            title: 'Удалить блок',
            message: 'Удалить "${unit['name'] ?? 'Блок #${unit['id']}'}"?',
            onDelete: () =>
                widget.repo.deleteControlUnit((unit['id'] as num).toInt()),
          ),
          onRenameSensor: (sensor) => _showRenameEntityDialog(
            title: 'Переименовать сенсор',
            initialName: sensor.name,
            onSave: (name) =>
                widget.repo.renameSensor(sensorId: sensor.id, name: name),
          ),
          onDeleteSensor: (sensor) => _confirmDeleteEntity(
            title: 'Удалить сенсор',
            message: 'Удалить "${sensor.name}"?',
            onDelete: () => widget.repo.deleteSensor(sensor.id),
          ),
        );
      }
      return _AdminCompanyList(
        repo: widget.repo,
        userCountByLocation: _companyUserCountCache,
        roleCountByLocation: _companyRoleCountCache,
        onSelect: (locationId) async {
          setState(() {
            _adminSelectedLocationId = locationId;
            _adminSection = 'users';
          });
          await _loadLocationDetails(locationId);
        },
      );
    }

    final locationId = _adminSelectedLocationId!;
    final details = _locationDetailsCache[locationId];

    if (_locationDetailsLoading && details == null) {
      return const Center(
        child: CircularProgressIndicator(color: kCyan, strokeWidth: 2),
      );
    }

    if (_locationDetailsError != null && details == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: kRed, size: 40),
            const SizedBox(height: 10),
            Text(
              _locationDetailsError!,
              style: TextStyle(
                color: AppColors.of(context).textDim,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _loadLocationDetails(locationId, forceReload: true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: kCyan.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Повторить',
                  style: TextStyle(color: kCyan, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _AdminCompanyUsersSection(
      repo: widget.repo,
      locationId: locationId,
      details: details,
      isLoading: _locationDetailsLoading,
      section: _adminSection,
      onSectionChange: (s) => setState(() => _adminSection = s),
      onAddUser: _showCreateUserDialog,
      roleLabel: _roleLabel,
      roleColor: (role) => _roleColor(AppColors.of(context), role),
      initials: _initials,
      onReload: () => _loadLocationDetails(locationId, forceReload: true),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Editor / Viewer: тело (TabBarView с 2 табами)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEditorViewerBody(AppRepository repo) {
    return TabBarView(
      controller: _tabCtrl,
      children: [
        // Таб 1: Все сотрудники компании
        _AllUsersTab(
          repo: repo,
          users: _allCompanyUsers,
          isLoading: _allCompanyUsersLoading,
          onAddUser: repo.role == UserRole.editor
              ? _showCreateUserDialog
              : null,
          roleLabel: _roleLabel,
          roleColor: (role) => _roleColor(AppColors.of(context), role),
          initials: _initials,
          onRefresh: _loadAllCompanyUsers,
        ),
        // Таб 2: Журнал аудита
        _AuditTab(repo: repo),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: breadcrumb навигация в шапке
// ─────────────────────────────────────────────────────────────────────────────
