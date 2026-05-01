import 'dart:convert';

import 'package:flutter/material.dart';
import '../models/audit_entry.dart';
import '../models/location_details.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/app_repository.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Фирменная палитра
// ─────────────────────────────────────────────────────────────────────────────

const _kBg      = Color(0xFF0A0A0A);
const _kCard    = Color(0x4D323232);
const _kCard2   = Color(0x334B4B4B);
const _kBorder  = Color(0xFF19282B);
const _kAccent  = Color(0xFFFFD550);
const _kCyan    = Color(0xFF07BCD4);
const _kGreen   = Color(0xFF01E676);
const _kRed     = Color(0xFFFF5252);
const _kYellowBg= Color(0xFF312C1C);
const _kRedBg   = Color(0xFF321C1B);
const _kTextDim = Color(0xFF7A8A8E);

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

  // ── Для admin: какая компания выбрана и что показываем ────────────────────
  int? _adminSelectedLocationId;
  String _adminSection = 'users';

  // Кеш: locationId → данные из /locations/{id}/details
  final Map<int, LocationDetails> _locationDetailsCache = {};
  bool _locationDetailsLoading = false;
  String? _locationDetailsError;

  // Кеш: locationId → кол-во сотрудников (без admin) — для списка компаний
  final Map<int, int> _companyUserCountCache = {};
  bool _companyCountsLoading = false;

  // Все пользователи компании для editor/viewer (загружаются отдельно)
  List<UserModel> _allCompanyUsers = [];
  bool _allCompanyUsersLoading = false;

  @override
  void initState() {
    super.initState();
    // Editor/viewer: tabCtrl с 2 табами
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
  Future<void> _loadAllCompanyCounts() async {
    if (_companyCountsLoading) return;
    setState(() => _companyCountsLoading = true);
    try {
      final r = await widget.repo.get('/users/?skip=0&limit=500');
      if (r.statusCode == 200) {
        final raw = _parseList(r.body).cast<Map<String, dynamic>>();
        final counts = <int, int>{};
        for (final u in raw) {
          if ((u['role'] as String?) == 'admin') continue;
          final locId = (u['location_id'] as num?)?.toInt();
          if (locId != null) counts[locId] = (counts[locId] ?? 0) + 1;
        }
        if (mounted) setState(() => _companyUserCountCache.addAll(counts));
      }
    } catch (_) {}
    if (mounted) setState(() => _companyCountsLoading = false);
  }

  // ── Список пользователей для editor/viewer ────────────────────────────────
  // По документации GET /users/ доступен только admin (editor/viewer → 403).
  // Editor видит только subordinateUsers (viewers его локации, загружены
  // в loadAll через GET /users/by-role/viewer).
  // Viewer не имеет доступа к списку вообще.
  //
  // Формируем "команду компании" из: текущий пользователь + subordinateUsers.

  Future<void> _loadAllCompanyUsers() async {
    setState(() => _allCompanyUsersLoading = true);
    final repo = widget.repo;
    final List<UserModel> result = [];

    // Себя — первым
    if (repo.currentUserId != null) {
      result.add(UserModel(
        id:       repo.currentUserId!,
        username: repo.currentUser ?? '',
        fullName: repo.currentUserFullName ?? '',
        role:     _roleFromEnum(repo.role),
        email:    repo.currentUserEmail,
      ));
    }

    // Подчинённые (уже загружены в репо при loadAll), без admin
    for (final u in repo.subordinateUsers) {
      if (u.id != repo.currentUserId && u.role != 'admin') result.add(u);
    }

    if (mounted) {
      setState(() {
        _allCompanyUsers = result;
        _allCompanyUsersLoading = false;
      });
    }
  }

  // ── Загрузка деталей локации для admin (один запрос) ─────────────────────
  Future<void> _loadLocationDetails(int locationId, {bool forceReload = false}) async {
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
        'admin'  => 'Администратор',
        'editor' => 'Редактор',
        _        => 'Читатель',
      };

  String _roleFromEnum(UserRole r) => switch (r) {
        UserRole.admin  => 'admin',
        UserRole.editor => 'editor',
        UserRole.viewer => 'viewer',
      };

  Color _roleColor(String role) => switch (role) {
        'admin'  => _kAccent,
        'editor' => _kCyan,
        _        => _kGreen,
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
          final isDark   = provider?.isDark ?? true;

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
                            isDark
                                ? 'Переключить на светлую тему'
                                : 'Переключить на тёмную тему',
                            style: const TextStyle(
                              color: _kCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
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
                              decoration: const BoxDecoration(
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
                        color: _kTextDim, size: 18,
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
                  final login = loginCtrl.text.trim();
                  final pass  = passCtrl.text.trim();
                  final name  = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim();

                  if (name.isEmpty)  { _snack('Введите ФИО');    return; }
                  if (login.isEmpty) { _snack('Введите логин');  return; }
                  if (pass.isEmpty)  { _snack('Введите пароль'); return; }
                  if (email.isNotEmpty && !email.contains('@')) {
                    _snack('Введите корректный Email');
                    return;
                  }

                  final err = await widget.repo.createUser(
                    username:   login,
                    password:   pass,
                    fullName:   name,
                    roleName:   roleName,
                    locationId: isAdmin ? selectedLocation : null,
                    email:      email.isEmpty ? null : email,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _snack(err ?? 'Сотрудник успешно создан');
                  if (err == null) {
                    await widget.onRefresh();
                    if (_adminSelectedLocationId != null) {
                      await _loadLocationDetails(_adminSelectedLocationId!, forceReload: true);
                    }
                    if (widget.repo.role != UserRole.admin) {
                      await _loadAllCompanyUsers();
                    }
                    // Сбрасываем счётчики — данные изменились
                    _companyUserCountCache.clear();
                    if (widget.repo.role == UserRole.admin) _loadAllCompanyCounts();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repo     = widget.repo;
    final username = repo.currentUser ?? '—';
    final fullName = repo.currentUserFullName ?? username;
    final email    = repo.currentUserEmail;
    final roleStr  = _roleFromEnum(repo.role);

    return Container(
      color: _kBg,
      child: Column(
        children: [
          // ── Шапка профиля ─────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: _kCard,
              border: Border(bottom: BorderSide(color: _kBorder)),
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
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: _kCyan, size: 20),
                      tooltip: 'Редактировать профиль',
                      onPressed: _showEditProfileDialog,
                    ),
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

                // ── Таб-бар только для editor/viewer ──────────────────────
                if (repo.role != UserRole.admin) ...[
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
                        text: 'Сотрудники'
                            '${_allCompanyUsers.isNotEmpty ? " (${_allCompanyUsers.length})" : ""}',
                      ),
                      const Tab(text: 'История действий'),
                    ],
                  ),
                ] else ...[
                  // Для admin: breadcrumb-навигация
                  if (_adminSelectedLocationId != null)
                    _AdminBreadcrumb(
                      companyName: repo.locations
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
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Компании',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
      return _AdminCompanyList(
        repo: widget.repo,
        userCountByLocation: _companyUserCountCache,
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
        child: CircularProgressIndicator(color: _kCyan, strokeWidth: 2),
      );
    }

    if (_locationDetailsError != null && details == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 40),
            const SizedBox(height: 10),
            Text(_locationDetailsError!,
                style: const TextStyle(color: _kTextDim, fontSize: 13)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _loadLocationDetails(locationId, forceReload: true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: _kCyan.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Повторить',
                    style: TextStyle(color: _kCyan, fontSize: 13)),
              ),
            ),
          ],
        ),
      );
    }

    return _AdminCompanyUsersSection(
      repo:            widget.repo,
      locationId:      locationId,
      details:         details,
      isLoading:       _locationDetailsLoading,
      section:         _adminSection,
      onSectionChange: (s) => setState(() => _adminSection = s),
      onAddUser:       _showCreateUserDialog,
      roleLabel:       _roleLabel,
      roleColor:       _roleColor,
      initials:        _initials,
      onReload:        () => _loadLocationDetails(locationId, forceReload: true),
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
          roleColor: _roleColor,
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

class _AdminBreadcrumb extends StatelessWidget {
  const _AdminBreadcrumb({
    required this.companyName,
    required this.section,
    required this.onBack,
  });

  final String companyName;
  final String section;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _kCard2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 13, color: _kTextDim),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Компании',
            style: const TextStyle(color: _kTextDim, fontSize: 13),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right, size: 14, color: _kTextDim),
          ),
          Expanded(
            child: Text(
              companyName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: список компаний
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCompanyList extends StatefulWidget {
  const _AdminCompanyList({
    required this.repo,
    required this.onSelect,
    required this.userCountByLocation,
  });

  final AppRepository repo;
  final Future<void> Function(int locationId) onSelect;
  final Map<int, int> userCountByLocation;

  @override
  State<_AdminCompanyList> createState() => _AdminCompanyListState();
}

class _AdminCompanyListState extends State<_AdminCompanyList> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = widget.repo.locations;
    final filtered = _searchQuery.isEmpty
        ? locations
        : locations
            .where((l) =>
                l.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
    final sorted = List.of(filtered)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Поиск компании…',
              hintStyle: const TextStyle(color: _kTextDim, fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search, color: _kTextDim, size: 18),
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
        ),

        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business_outlined,
                          size: 40, color: _kTextDim),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Компании не найдены'
                            : 'Нет компаний',
                        style: const TextStyle(
                            color: _kTextDim, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : _buildAlphaList(sorted),
        ),
      ],
    );
  }

  Widget _buildAlphaList(List<dynamic> sorted) {
    final Map<String, List<dynamic>> groups = {};
    for (final loc in sorted) {
      final letter =
          loc.name.isNotEmpty ? loc.name[0].toUpperCase() : '#';
      groups.putIfAbsent(letter, () => []).add(loc);
    }
    final letters = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: letters.length,
      itemBuilder: (context, i) {
        final letter = letters[i];
        final items  = groups[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
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
            ...items.map((loc) => _CompanyTile(
                  name: loc.name as String,
                  userCount: widget.userCountByLocation[loc.id as int] ?? 0,
                  onTap: () => widget.onSelect(loc.id as int),
                )),
          ],
        );
      },
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.name,
    required this.userCount,
    required this.onTap,
  });

  final String name;
  final int userCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _kCyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kCyan.withOpacity(0.3)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.business_outlined,
                  size: 18, color: _kCyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kCyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kCyan.withOpacity(0.3)),
              ),
              child: Text(
                '$userCount',
                style: const TextStyle(
                  fontSize: 11,
                  color: _kCyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: _kTextDim, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: секция выбранной компании (пользователи + кнопки)
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCompanyUsersSection extends StatelessWidget {
  const _AdminCompanyUsersSection({
    required this.repo,
    required this.locationId,
    required this.details,
    required this.isLoading,
    required this.section,
    required this.onSectionChange,
    required this.onAddUser,
    required this.roleLabel,
    required this.roleColor,
    required this.initials,
    required this.onReload,
  });

  final AppRepository repo;
  final int locationId;
  final LocationDetails? details;
  final bool isLoading;
  final String section;
  final ValueChanged<String> onSectionChange;
  final VoidCallback onAddUser;
  final String Function(String) roleLabel;
  final Color Function(String) roleColor;
  final String Function(String, String) initials;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final users     = details?.users ?? [];
    final auditLogs = details?.auditLogs ?? [];
    final userIds   = details?.users.map((u) => u.id).toSet();
    final rawLogs   = details?.rawAuditLogs;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              _SectionTab(
                label: 'Сотрудники',
                icon: Icons.people_outline,
                isActive: section == 'users',
                onTap: () => onSectionChange('users'),
              ),
              const SizedBox(width: 8),
              _SectionTab(
                label: 'Аудит',
                icon: Icons.history,
                isActive: section == 'audit',
                onTap: () => onSectionChange('audit'),
              ),
            ],
          ),
        ),

        Expanded(
          child: isLoading && details == null
              ? const Center(
                  child: CircularProgressIndicator(color: _kCyan, strokeWidth: 2),
                )
              : section == 'audit'
                  ? _AuditTab(
                      repo:            repo,
                      filterByUserIds: userIds,
                      rawEntries:      rawLogs,
                      locationUsers:   users,
                      preloadedEntries: auditLogs,
                    )
                  : _UsersTab(
                      repo:      repo,
                      users:     users,
                      onAddUser: onAddUser,
                      roleLabel: roleLabel,
                      roleColor: roleColor,
                      initials:  initials,
                    ),
        ),
      ],
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? _kCyan.withOpacity(0.12) : _kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _kCyan.withOpacity(0.5) : _kBorder,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: isActive ? _kCyan : _kTextDim),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? _kCyan : _kTextDim,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: секция локаций выбранной компании
// ─────────────────────────────────────────────────────────────────────────────

class _AdminLocationsSection extends StatelessWidget {
  const _AdminLocationsSection({
    required this.repo,
    required this.locationId,
  });

  final AppRepository repo;
  final int locationId;

  @override
  Widget build(BuildContext context) {
    final loc = repo.locations
        .where((l) => l.id == locationId)
        .firstOrNull;
    final sensors = repo.sensors
        .where((s) => s.groupId == locationId)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Карточка локации
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 18, color: _kCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc?.name ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(label: 'ID локации', value: '#$locationId'),
              _InfoRow(
                  label: 'Датчиков',
                  value: '${sensors.length}'),
              if (loc?.imageUrl != null)
                _InfoRow(label: 'План', value: 'Загружен'),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Список датчиков
        if (sensors.isNotEmpty) ...[
          const Text(
            'Датчики',
            style: TextStyle(
              color: _kTextDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ...sensors.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.isOnline ? _kGreen : _kRed,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Text(
                      s.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        color: s.isOnline ? _kGreen : _kRed,
                      ),
                    ),
                  ],
                ),
              )),
        ] else
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Датчики не найдены',
                style: TextStyle(color: _kTextDim, fontSize: 13),
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
          Text(label,
              style: const TextStyle(color: _kTextDim, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Таб: Все сотрудники компании (editor/viewer)
// ─────────────────────────────────────────────────────────────────────────────

class _AllUsersTab extends StatelessWidget {
  const _AllUsersTab({
    required this.repo,
    required this.users,
    required this.isLoading,
    required this.onAddUser,
    required this.roleLabel,
    required this.roleColor,
    required this.initials,
    required this.onRefresh,
  });

  final AppRepository repo;
  final List<UserModel> users;
  final bool isLoading;
  final VoidCallback? onAddUser;
  final String Function(String) roleLabel;
  final Color Function(String) roleColor;
  final String Function(String, String) initials;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _kCyan, strokeWidth: 2),
      );
    }

    return RefreshIndicator(
      color: _kCyan,
      backgroundColor: _kCard,
      onRefresh: onRefresh,
      child: _UsersTab(
        repo: repo,
        users: users,
        onAddUser: onAddUser,
        roleLabel: roleLabel,
        roleColor: roleColor,
        initials: initials,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Таб: Пользователи (общий для admin и editor/viewer)
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab({
    required this.repo,
    required this.users,
    required this.onAddUser,
    required this.roleLabel,
    required this.roleColor,
    required this.initials,
  });

  final AppRepository repo;
  final List<UserModel> users;
  final VoidCallback? onAddUser;
  final String Function(String) roleLabel;
  final Color Function(String) roleColor;
  final String Function(String, String) initials;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text(
              'Сотрудники (${users.length})',
              style: const TextStyle(
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Нет сотрудников',
                style: TextStyle(color: _kTextDim),
              ),
            ),
          )
        else ...[
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
            final i      = entry.key;
            final u      = entry.value;
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
                    user.fullName.isNotEmpty
                        ? user.fullName
                        : user.username,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.email ?? '—',
              style: const TextStyle(color: _kTextDim, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
  const _AuditTab({
    required this.repo,
    this.filterByUserIds,
    this.rawEntries,
    this.locationUsers,
    this.preloadedEntries,
  });
  final AppRepository repo;
  final Set<int>? filterByUserIds;
  /// Сырые записи с user_id для фильтрации по сотруднику.
  final List<Map<String, dynamic>>? rawEntries;
  /// Пользователи локации для резолва имён.
  final List<UserModel>? locationUsers;
  /// Уже распарсенные записи из LocationDetails (admin) — не делаем доп запрос.
  final List<AuditEntry>? preloadedEntries;

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  late Future<void> _future;
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    // Если есть preloaded или rawEntries — данные уже есть, запрос не нужен
    _future = (widget.preloadedEntries != null || widget.rawEntries != null)
        ? Future.value()
        : widget.repo.loadAuditLog();
  }

  Future<void> _reload() {
    setState(() {
      _future = (widget.preloadedEntries != null || widget.rawEntries != null)
          ? Future.value()
          : widget.repo.loadAuditLog();
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
            child: CircularProgressIndicator(
                color: _kCyan, strokeWidth: 2),
          );
        }

        final filterIds  = widget.filterByUserIds;
        final rawEntries = widget.rawEntries;
        final preloaded  = widget.preloadedEntries;

        late final List<AuditEntry> entries;
        final userNames = <int, String>{};

        // Строим userNames из locationUsers (для фильтра-dropdown)
        if (widget.locationUsers != null) {
          for (final u in widget.locationUsers!) {
            userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
          }
        }

        if (preloaded != null) {
          // Данные пришли из LocationDetails — уже распарсены и отфильтрованы по локации.
          // Дополнительно фильтруем по выбранному сотруднику.
          if (_selectedUserId != null) {
            final selectedName = userNames[_selectedUserId] ?? '';
            entries = preloaded
                .where((e) => e.user == selectedName || e.user == 'ID:$_selectedUserId')
                .toList();
          } else {
            entries = preloaded;
          }
        } else if (filterIds != null && rawEntries != null) {
          final repo = widget.repo;
          for (final u in repo.subordinateUsers) {
            userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
          }
          if (repo.currentUserId != null) {
            userNames[repo.currentUserId!] =
                repo.currentUserFullName?.isNotEmpty == true
                    ? repo.currentUserFullName!
                    : (repo.currentUser ?? '');
          }

          entries = rawEntries
              .where((e) {
                final uid = (e['user_id'] as num?)?.toInt() ?? 0;
                if (!filterIds.contains(uid)) return false;
                if (_selectedUserId != null && uid != _selectedUserId) return false;
                return true;
              })
              .map((e) {
                final uid   = (e['user_id'] as num?)?.toInt() ?? 0;
                final tsRaw = e['timestamp'] as String? ?? '';
                String timeFormatted = tsRaw;
                try {
                  final dt = DateTime.parse(tsRaw).toLocal();
                  final h  = dt.hour.toString().padLeft(2, '0');
                  final mn = dt.minute.toString().padLeft(2, '0');
                  final d  = dt.day.toString().padLeft(2, '0');
                  final mo = dt.month.toString().padLeft(2, '0');
                  timeFormatted = '$d.$mo.${dt.year}  $h:$mn';
                } catch (_) {}
                return AuditEntry(
                  user:   userNames[uid] ?? 'ID:$uid',
                  action: e['action'] as String? ?? '',
                  time:   timeFormatted,
                );
              })
              .toList();
        } else {
          // editor/viewer: строим userNames из repo
          final repo = widget.repo;
          for (final u in repo.subordinateUsers) {
            userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
          }
          if (repo.currentUserId != null) {
            userNames[repo.currentUserId!] =
                repo.currentUserFullName?.isNotEmpty == true
                    ? repo.currentUserFullName!
                    : (repo.currentUser ?? '');
          }

          final allEntries = repo.audit;
          if (_selectedUserId != null) {
            final selectedName = userNames[_selectedUserId] ?? '';
            entries = allEntries
                .where((e) => e.user == selectedName || e.user == 'ID:$_selectedUserId')
                .toList();
          } else {
            entries = allEntries;
          }
        }

        // Список пользователей для dropdown-фильтра
        final filterUsers = <int, String>{};
        if (userNames.isNotEmpty) {
          if (filterIds != null) {
            for (final id in filterIds) {
              if (userNames.containsKey(id)) filterUsers[id] = userNames[id]!;
            }
          } else {
            filterUsers.addAll(userNames);
          }
        }

        return Column(
          children: [
            // ── Фильтр по сотруднику ───────────────────────────────────────
            if (filterUsers.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: DropdownButtonFormField<int?>(
                  value: _selectedUserId,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Сотрудник',
                    labelStyle: const TextStyle(color: _kTextDim, fontSize: 12),
                    prefixIcon: const Icon(Icons.person_outline, color: _kTextDim, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kCyan),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Все сотрудники'),
                    ),
                    ...filterUsers.entries.map((e) => DropdownMenuItem<int?>(
                          value: e.key,
                          child: Text(e.value),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedUserId = v),
                ),
              ),

            // ── Список записей ─────────────────────────────────────────────
            Expanded(child: _buildList(entries)),
          ],
        );
      },
    );
  }

  Widget _buildList(List<AuditEntry> entries) {
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: _kCyan.withOpacity(0.4)),
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Виджеты-компоненты (без изменений)
// ─────────────────────────────────────────────────────────────────────────────

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
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16),
      ),
      content: content,
      actions: actions,
    );
  }
}

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

class _DarkTextButton extends StatelessWidget {
  const _DarkTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child:
          Text(label, style: const TextStyle(color: _kTextDim, fontSize: 13)),
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
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}