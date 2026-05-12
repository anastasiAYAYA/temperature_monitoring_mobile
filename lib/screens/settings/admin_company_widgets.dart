part of '../settings_screen.dart';

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
                color: AppColors.of(context).card2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.of(context).border),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 13,
                color: AppColors.of(context).textDim,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Компании',
            style: TextStyle(
              color: AppColors.of(context).textDim,
              fontSize: 13,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColors.of(context).textDim,
            ),
          ),
          Expanded(
            child: Text(
              companyName,
              style: TextStyle(
                color: AppColors.of(context).textMain,
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
    required this.roleCountByLocation,
  });

  final AppRepository repo;
  final Future<void> Function(int locationId) onSelect;
  final Map<int, int> userCountByLocation;

  /// {'editor': N, 'viewer': N} по каждой локации.
  final Map<int, Map<String, int>> roleCountByLocation;

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
              .where(
                (l) =>
                    l.name.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
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
            style: TextStyle(
              color: AppColors.of(context).textMain,
              fontSize: 14,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Поиск компании…',
              hintStyle: TextStyle(
                color: AppColors.of(context).textDim,
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.of(context).textDim,
                size: 18,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Icon(
                        Icons.close,
                        color: AppColors.of(context).textDim,
                        size: 16,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.of(context).card,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.of(context).border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kCyan),
              ),
            ),
          ),
        ),

        // Количество найденных
        if (sorted.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Text(
              'Компаний: ${sorted.length}',
              style: TextStyle(
                color: AppColors.of(context).textDim,
                fontSize: 11,
              ),
            ),
          ),

        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 40,
                        color: AppColors.of(context).textDim,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Компании не найдены'
                            : 'Нет компаний',
                        style: TextStyle(
                          color: AppColors.of(context).textDim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final loc = sorted[i];
                    return _CompanyCard(
                      name: loc.name as String,
                      userCount: widget.userCountByLocation[loc.id as int] ?? 0,
                      roleCount: widget.roleCountByLocation[loc.id as int],
                      // Аватарки заполняются после открытия карточки через LocationDetails.
                      // Здесь передаём пустой список — они появятся при onTap.
                      locationUsers: const [],
                      onTap: () => widget.onSelect(loc.id as int),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Карточка компании в стиле дашборда: метрики + чипы ролей + аватарки.
class _CompanyCard extends StatefulWidget {
  const _CompanyCard({
    required this.name,
    required this.userCount,
    required this.onTap,
    this.roleCount,
    this.locationUsers = const [],
  });

  final String name;
  final int userCount;
  final VoidCallback onTap;
  final Map<String, int>? roleCount;
  final List<UserModel> locationUsers;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _expanded = false;

  String _initials(UserModel u) {
    final name = u.fullName.isNotEmpty ? u.fullName : u.username;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _avatarColor(String role) => switch (role) {
    'editor' => kCyan,
    _ => kGreen,
  };

  @override
  Widget build(BuildContext context) {
    final editorN = widget.roleCount?['editor'] ?? 0;
    final viewerN = widget.roleCount?['viewer'] ?? 0;
    final hasUsers = widget.userCount > 0;

    // Аватарки — максимум 5, остальные «+N»
    final avatarUsers = widget.locationUsers.take(5).toList();
    final extraCount = widget.locationUsers.length > 5
        ? widget.locationUsers.length - 5
        : 0;

    return GestureDetector(
      onTap: () {
        setState(() => _expanded = !_expanded);
        widget.onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.of(context).card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Иконка компании ───────────────────────────────────────────
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: kCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kCyan.withOpacity(0.3)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.business_outlined,
                  size: 17,
                  color: kCyan,
                ),
              ),
              const SizedBox(width: 10),

              // ── Название + чипы ролей ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      style: TextStyle(
                        color: AppColors.of(context).textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Чипы ролей под названием (только если есть данные)
                    if (hasUsers && (editorN > 0 || viewerN > 0)) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (editorN > 0)
                            _RoleChip(
                              label: editorN == 1
                                  ? '1 редактор'
                                  : '$editorN редактора',
                              color: kCyan,
                            ),
                          if (editorN > 0 && viewerN > 0)
                            const SizedBox(width: 6),
                          if (viewerN > 0)
                            _RoleChip(
                              label: viewerN == 1
                                  ? '1 читатель'
                                  : '$viewerN читателя',
                              color: kGreen,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ── Кружок с количеством пользователей (на уровне названия) ──
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCyan.withOpacity(0.10),
                  border: Border.all(color: kCyan.withOpacity(0.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.userCount}',
                  style: const TextStyle(
                    color: kCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

/// Один столбец с числом и подписью (Пользователей / Онлайн / Событий).
class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.value, required this.label, this.color});
  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final clr = color ?? (value > 0 ? kCyan : AppColors.of(context).textMain);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: clr,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: AppColors.of(context).textDim,
            fontSize: 9,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

/// Чип с цветной точкой для роли (редактор / читатель).
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    final users = details?.users ?? [];
    final auditLogs = details?.auditLogs ?? [];
    final userIds = details?.users.map((u) => u.id).toSet();
    final rawLogs = details?.rawAuditLogs;

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
                  child: CircularProgressIndicator(
                    color: kCyan,
                    strokeWidth: 2,
                  ),
                )
              : section == 'audit'
              ? _AuditTab(
                  repo: repo,
                  filterByUserIds: userIds,
                  rawEntries: rawLogs,
                  locationUsers: users,
                  preloadedEntries: auditLogs,
                )
              : _UsersTab(
                  repo: repo,
                  users: users,
                  onAddUser: onAddUser,
                  roleLabel: roleLabel,
                  roleColor: roleColor,
                  initials: initials,
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
            color: isActive
                ? kCyan.withOpacity(0.12)
                : AppColors.of(context).card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? kCyan.withOpacity(0.5)
                  : AppColors.of(context).border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? kCyan : AppColors.of(context).textDim,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? kCyan : AppColors.of(context).textDim,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
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
