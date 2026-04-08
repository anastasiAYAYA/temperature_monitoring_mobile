import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sensors_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_repository.dart';
import 'theme/app_colors.dart';

class TemperaturaApp extends StatelessWidget {
  const TemperaturaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TEMPERATURA.KZ',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.card),
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

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
    final screens = [
      DashboardScreen(repo: repo, onRefresh: _reload),
      SensorsScreen(repo: repo, onRefresh: _reload),
      ReportsScreen(repo: repo),
      NotificationsScreen(repo: repo, onRefresh: _reload),
      SettingsScreen(repo: repo, onRefresh: _reload),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('TEMPERATURA.KZ'),
        actions: [
          IconButton(onPressed: loading ? null : _reload, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: loading
                ? null
                : () async {
                    repo.logout();
                    setState(() {});
                  },
            icon: const Icon(Icons.logout),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(child: Text(repo.role.name, style: const TextStyle(color: AppColors.primary))),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : repo.token == null
              ? LoginScreen(repo: repo, onSuccess: _reload)
              : Column(
                  children: [
                    if (error != null)
                      Container(
                        width: double.infinity,
                        color: AppColors.danger.withValues(alpha: 0.2),
                        padding: const EdgeInsets.all(8),
                        child: Text(error!, style: const TextStyle(color: AppColors.danger)),
                      ),
                    Expanded(child: screens[tab]),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Датчики'),
          NavigationDestination(icon: Icon(Icons.file_open), label: 'Отчеты'),
          NavigationDestination(icon: Icon(Icons.notifications), label: 'Увед.'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}
