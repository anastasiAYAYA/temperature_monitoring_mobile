part of '../settings_screen.dart';

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
  final TextEditingController _actionSearchCtrl = TextEditingController();
  String _actionQuery = '';
  // Роль по user_id — для badge в карточке аудита (без изменения модели)
  final Map<String, String> _userRoles =
      {}; // имя -> роль ('admin','editor','viewer')

  @override
  void initState() {
    super.initState();
    // Если есть preloaded или rawEntries — данные уже есть, запрос не нужен
    _future = (widget.preloadedEntries != null || widget.rawEntries != null)
        ? Future.value()
        : widget.repo.loadAuditLog();
  }

  @override
  void dispose() {
    _actionSearchCtrl.dispose();
    super.dispose();
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
            child: CircularProgressIndicator(color: kCyan, strokeWidth: 2),
          );
        }

        final filterIds = widget.filterByUserIds;
        final rawEntries = widget.rawEntries;
        final preloaded = widget.preloadedEntries;

        late List<AuditEntry> entries;
        // userNames: id -> имя. Заполняем без admin (locationUsers, subordinateUsers, себя).
        final userNames = <int, String>{};

        // Из locationUsers (admin-ветка с preloaded/rawEntries) — без admin
        if (widget.locationUsers != null) {
          for (final u in widget.locationUsers!) {
            if (u.role == 'admin') continue; // admin скрыт
            userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
          }
        }

        if (preloaded != null) {
          // Данные из LocationDetails (admin смотрит компанию).
          // Исключаем admin-записи: проверяем по userNames (туда admin не попал).

          // FIX: заполняем _userRoles из locationUsers, чтобы бейдж роли в карточке
          // аудита отображал реальную роль (editor/viewer), а не дефолтный 'viewer'.
          // Раньше _userRoles заполнялся только в ветках editor/viewer, а в admin-ветке
          // (preloaded != null) словарь оставался пустым → все пользователи показывались
          // как «Читатель» независимо от их реальной роли.
          if (widget.locationUsers != null) {
            for (final u in widget.locationUsers!) {
              if (u.role == 'admin') continue; // admin в журнале не показываем
              final displayName = u.fullName.isNotEmpty
                  ? u.fullName
                  : u.username;
              _userRoles[displayName] = u.role; // 'editor' или 'viewer'
            }
          }

          entries = preloaded
              .where((e) => userNames.values.contains(e.user))
              .toList();
          if (_selectedUserId != null) {
            final selectedName = userNames[_selectedUserId] ?? '';
            entries = entries.where((e) => e.user == selectedName).toList();
          }
        } else if (filterIds != null && rawEntries != null) {
          // editor/viewer с явным списком id и сырыми записями
          final repo = widget.repo;
          for (final u in repo.subordinateUsers) {
            if (u.role == 'admin') continue;
            final uName = u.fullName.isNotEmpty ? u.fullName : u.username;
            userNames[u.id] = uName;
            _userRoles[uName] = u.role; // для badge
          }
          if (repo.currentUserId != null) {
            final selfName = repo.currentUserFullName?.isNotEmpty == true
                ? repo.currentUserFullName!
                : (repo.currentUser ?? '');
            userNames[repo.currentUserId!] = selfName;
            // filterIds уже содержит только не-admin ids, роль из filterByUserIds
          }
          // filterIds уже содержит только не-admin ids (приходит из _AdminCompanyUsersSection)
          entries = rawEntries
              .where((e) {
                final uid = (e['user_id'] as num?)?.toInt() ?? 0;
                if (!filterIds.contains(uid)) return false;
                if (_selectedUserId != null && uid != _selectedUserId)
                  return false;
                return true;
              })
              .map((e) {
                final uid = (e['user_id'] as num?)?.toInt() ?? 0;
                final tsRaw = e['timestamp'] as String? ?? '';
                String timeFormatted = tsRaw;
                try {
                  final dt = DateTime.parse(tsRaw).toLocal();
                  final h = dt.hour.toString().padLeft(2, '0');
                  final mn = dt.minute.toString().padLeft(2, '0');
                  final d = dt.day.toString().padLeft(2, '0');
                  final mo = dt.month.toString().padLeft(2, '0');
                  timeFormatted = '$d.$mo.${dt.year}  $h:$mn';
                } catch (_) {}
                return AuditEntry(
                  user: userNames[uid] ?? '',
                  action: e['action'] as String? ?? '',
                  time: timeFormatted,
                );
              })
              .where(
                (e) => e.user.isNotEmpty,
              ) // убираем строки без известного имени
              .toList();
        } else {
          // editor/viewer: данные из repo.audit (уже отфильтрованы в loadAuditLog по allowedIds)
          final repo = widget.repo;
          for (final u in repo.subordinateUsers) {
            if (u.role == 'admin') continue;
            userNames[u.id] = u.fullName.isNotEmpty ? u.fullName : u.username;
            _userRoles[userNames[u.id]!] = u.role; // для badge
          }
          if (repo.currentUserId != null) {
            final selfName = repo.currentUserFullName?.isNotEmpty == true
                ? repo.currentUserFullName!
                : (repo.currentUser ?? '');
            userNames[repo.currentUserId!] = selfName;
            final selfRole = switch (repo.role) {
              UserRole.admin => 'admin',
              UserRole.editor => 'editor',
              UserRole.viewer => 'viewer',
            };
            _userRoles[selfName] = selfRole; // для badge своей роли
          }
          entries = repo.audit;
          if (_selectedUserId != null) {
            final selectedName = userNames[_selectedUserId] ?? '';
            entries = entries.where((e) => e.user == selectedName).toList();
          }
        }

        // Для dropdown: сотрудники без admin, отсортированные по имени
        final filterUsers = <int, String>{
          for (final e
              in userNames.entries.toList()
                ..sort((a, b) => a.value.compareTo(b.value)))
            e.key: e.value,
        };

        // Применяем текстовый фильтр по действию поверх dropdown-фильтра
        final q = _actionQuery.toLowerCase();
        final displayed = q.isEmpty
            ? entries
            : entries.where((e) => e.action.toLowerCase().contains(q)).toList();

        return Column(
          children: [
            // ── Фильтр: dropdown по сотруднику + поиск по действию ─────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                children: [
                  // Dropdown по сотруднику (только если больше одного человека)
                  if (filterUsers.length > 1)
                    DropdownButtonFormField<int?>(
                      value: _selectedUserId,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: TextStyle(
                        color: AppColors.of(context).textMain,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Сотрудник',
                        labelStyle: TextStyle(
                          color: AppColors.of(context).textDim,
                          fontSize: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: AppColors.of(context).textDim,
                          size: 16,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.of(context).border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: kCyan),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Все сотрудники'),
                        ),
                        ...filterUsers.entries.map(
                          (e) => DropdownMenuItem<int?>(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedUserId = v),
                    ),
                  if (filterUsers.length > 1) const SizedBox(height: 8),
                  // Текстовый поиск по действию
                  TextField(
                    controller: _actionSearchCtrl,
                    style: TextStyle(
                      color: AppColors.of(context).textMain,
                      fontSize: 13,
                    ),
                    onChanged: (v) => setState(() => _actionQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Поиск по действию…',
                      hintStyle: TextStyle(
                        color: AppColors.of(context).textDim,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.of(context).textDim,
                        size: 16,
                      ),
                      suffixIcon: _actionQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _actionSearchCtrl.clear();
                                setState(() => _actionQuery = '');
                              },
                              child: Icon(
                                Icons.close,
                                color: AppColors.of(context).textDim,
                                size: 15,
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.of(context).card,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppColors.of(context).border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: kCyan),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Список записей ─────────────────────────────────────────────
            Expanded(child: _buildList(displayed)),
          ],
        );
      },
    );
  }

  // ── Вспомогательные для карточки аудита ─────────────────────────────────

  /// Инициалы из имени пользователя (2 буквы)
  String _auditInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// Цвет аватара по роли
  Color _auditAvatarColor(String role, AppScheme sch) => switch (role) {
    'admin' => sch.accent,
    'editor' => kCyan,
    _ => kGreen,
  };

  /// Метка роли по строке
  String _auditRoleLabel(String role) => switch (role) {
    'admin' => 'Админ',
    'editor' => 'Редактор',
    _ => 'Читатель',
  };

  Widget _buildList(List<AuditEntry> entries) {
    final sch = AppColors.of(context);

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, color: sch.textDim, size: 36),
            const SizedBox(height: 10),
            Text('История пуста', style: TextStyle(color: sch.textDim)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _reload,
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
                  'Обновить',
                  style: TextStyle(color: kCyan, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kCyan,
      backgroundColor: sch.card,
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          final role = _userRoles[e.user] ?? 'viewer';
          final initials = _auditInitials(e.user);
          final avatarColor = _auditAvatarColor(role, sch);
          final roleLabel = _auditRoleLabel(role);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: sch.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sch.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Аватар ────────────────────────────────────────────────
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: avatarColor.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatarColor.withOpacity(0.45),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: avatarColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Содержимое ────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Строка: имя + роль-бейдж
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              e.user,
                              style: TextStyle(
                                color: sch.textMain,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 7),
                          // Бейдж роли
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: avatarColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: avatarColor.withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: avatarColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Текст действия
                      Text(
                        e.action,
                        style: TextStyle(color: sch.textMain, fontSize: 12.5),
                      ),
                      const SizedBox(height: 5),
                      // Дата и время
                      Text(
                        e.time,
                        style: TextStyle(color: sch.textDim, fontSize: 11),
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
