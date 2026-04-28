import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sensors_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_repository.dart';
import 'theme/app_theme.dart';

class TemperaturaApp extends StatefulWidget {
  const TemperaturaApp({super.key});

  @override
  State<TemperaturaApp> createState() => _TemperaturaAppState();
}

class _TemperaturaAppState extends State<TemperaturaApp> {
  bool _isDark = true;

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return AppThemeProvider(
      isDark: _isDark,
      toggle: _toggleTheme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'TEMPERATURA.KZ',
        theme: buildMaterialTheme(isDark: _isDark),
        home: RootPage(
          isDark: _isDark,
          onToggleTheme: _toggleTheme,
        ),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final repo = AppRepository();
  int tab = 0;
  bool loading = false;
  String? error;

  Future<void> _reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    final err = await repo.loadAll();
    if (!mounted) return;
    setState(() {
      loading = false;
      error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Не авторизован — показываем логин
    if (repo.token == null) {
      return LoginScreen(repo: repo, onSuccess: _reload);
    }

    final screens = [
      DashboardScreen(repo: repo, onRefresh: _reload),
      SensorsScreen(repo: repo, onRefresh: _reload),
      ReportsScreen(repo: repo),
      NotificationsScreen(repo: repo, onRefresh: _reload),
      SettingsScreen(
        repo: repo,
        onRefresh: _reload,
        onLogout: () => setState(() {}),
        onToggleTheme: widget.onToggleTheme,
      ),
    ];

    // Цвет навбара и AppBar зависит от темы
    final isDark = widget.isDark;
    final navBg  = isDark ? const Color(0xFF0E0E0E) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B2A);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF2F4F6),
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        title: Text(
          'TEMPERATURA.KZ',
          style: TextStyle(
            color: const Color(0xFFFFD550),
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : _reload,
            icon: Icon(Icons.refresh,
                color: isDark ? Colors.white54 : Colors.black54),
          ),
          IconButton(
            onPressed: loading
                ? null
                : () async {
                    repo.logout();
                    setState(() {});
                  },
            icon: const Icon(Icons.logout, color: Color(0xFFFF5252)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                repo.role.name,
                style: const TextStyle(
                  color: Color(0xFFFFD550),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD550)))
          : Column(
              children: [
                if (error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFF5252).withOpacity(0.15),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(
                          color: Color(0xFFFF5252), fontSize: 13),
                    ),
                  ),
                Expanded(child: screens[tab]),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: navBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFFFD550).withOpacity(0.18),
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined,
                color: isDark ? Colors.white38 : Colors.black38),
            selectedIcon: const Icon(Icons.home, color: Color(0xFFFFD550)),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined,
                color: isDark ? Colors.white38 : Colors.black38),
            selectedIcon:
                const Icon(Icons.sensors, color: Color(0xFFFFD550)),
            label: 'Датчики',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined,
                color: isDark ? Colors.white38 : Colors.black38),
            selectedIcon:
                const Icon(Icons.bar_chart, color: Color(0xFFFFD550)),
            label: 'Отчёты',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined,
                color: isDark ? Colors.white38 : Colors.black38),
            selectedIcon: const Icon(Icons.notifications,
                color: Color(0xFFFFD550)),
            label: 'Увед.',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined,
                color: isDark ? Colors.white38 : Colors.black38),
            selectedIcon:
                const Icon(Icons.settings, color: Color(0xFFFFD550)),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}