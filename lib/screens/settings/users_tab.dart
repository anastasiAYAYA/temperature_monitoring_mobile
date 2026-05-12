part of '../settings_screen.dart';

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
        child: CircularProgressIndicator(color: kCyan, strokeWidth: 2),
      );
    }

    return RefreshIndicator(
      color: kCyan,
      backgroundColor: AppColors.of(context).card,
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
              style: TextStyle(
                color: AppColors.of(context).textMain,
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
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: kCyan.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kCyan.withOpacity(0.35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_outlined, size: 14, color: kCyan),
                      SizedBox(width: 6),
                      Text(
                        'Добавить',
                        style: TextStyle(
                          fontSize: 12,
                          color: kCyan,
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
                'Нет сотрудников',
                style: TextStyle(color: AppColors.of(context).textDim),
              ),
            ),
          )
        else ...[
          // Заголовок таблицы
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.of(context).card2,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Пользователь',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.of(context).textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Email',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.of(context).textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    'Роль',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.of(context).textDim,
                      fontWeight: FontWeight.w600,
                    ),
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
        color: AppColors.of(context).card,
        border: Border(
          left: BorderSide(color: AppColors.of(context).border),
          right: BorderSide(color: AppColors.of(context).border),
          bottom: BorderSide(
            color: isLast
                ? AppColors.of(context).border
                : const Color(0xFF19282B),
          ),
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
                    user.fullName.isNotEmpty ? user.fullName : user.username,
                    style: TextStyle(
                      color: AppColors.of(context).textMain,
                      fontSize: 13,
                    ),
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
              style: TextStyle(
                color: AppColors.of(context).textDim,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 72,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor == AppColors.of(context).accent
                    ? AppColors.of(context).yellowBg
                    : roleColor == kRed
                    ? AppColors.of(context).redBg
                    : AppColors.of(context).border,
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
