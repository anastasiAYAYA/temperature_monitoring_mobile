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
  // класс для приложения
  const TemperaturaApp({super.key}); // конструктор класса

  @override
  State<TemperaturaApp> createState() => _TemperaturaAppState(); // создание экземпляра класса
}

class _TemperaturaAppState extends State<TemperaturaApp> {
  // класс для состояния приложения
  bool _isDark = true;

  void _toggleTheme() =>
      setState(() => _isDark = !_isDark); // функция для переключения темы

  @override
  Widget build(BuildContext context) {
    // функция для построения приложения
    return AppThemeProvider(
      // класс для построения приложения
      isDark: _isDark,
      toggle: _toggleTheme,
      child: MaterialApp(
        // класс для построения приложения
        debugShowCheckedModeBanner: false,
        title: 'TEMPERATURA.KZ', // название приложения
        theme: buildMaterialTheme(isDark: _isDark),
        home: RootPage(
          // класс для построения приложения
          isDark: _isDark, // признак темной темы
          onToggleTheme: _toggleTheme, // функция для переключения темы
        ),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({
    super.key, // конструктор класса
    required this.isDark, // признак темной темы
    required this.onToggleTheme, // функция для переключения темы
  });

  final bool isDark; // признак темной темы
  final VoidCallback onToggleTheme; // функция для переключения темы

  @override
  State<RootPage> createState() => _RootPageState(); // создание экземпляра класса
}

class _RootPageState extends State<RootPage> {
  // класс для состояния приложения
  final repo = AppRepository(); // репозиторий
  int tab = 0;
  bool loading = false; // признак загрузки
  String? error; // ошибка

  Future<void> _reload() async {
    // функция для перезагрузки данных
    setState(() {
      loading = true;
      error = null;
    }); // устанавливаем признак загрузки и ошибку
    final err = await repo.loadAll(); // загружаем данные
    if (!mounted) return; // если приложение не смонтировано, то выходим
    setState(() {
      loading = false;
      error = err;
    }); // устанавливаем признак загрузки и ошибку
  }

  // Вызывается после успешного логина: загружает данные и сбрасывает таб на главную
  Future<void> _onLoginSuccess() async {
    // функция для вызова после успешного логина
    setState(() {
      tab = 0;
      loading = true;
      error = null;
    }); // устанавливаем таб на главную и признак загрузки
    final err = await repo.loadAll(); // загружаем данные
    if (!mounted) return; // если приложение не смонтировано, то выходим
    setState(() {
      loading = false;
      error = err;
    }); // устанавливаем признак загрузки и ошибку
  }

  @override
  Widget build(BuildContext context) {
    // Не авторизован — показываем логин
    if (repo.token == null) {
      return LoginScreen(repo: repo, onSuccess: _onLoginSuccess);
    }

    final screens = [
      // экраны
      DashboardScreen(repo: repo, onRefresh: _reload), // экран главная
      SensorsScreen(repo: repo, onRefresh: _reload), // экран датчики
      ReportsScreen(repo: repo), // экран отчеты
      NotificationsScreen(repo: repo, onRefresh: _reload), // экран уведомления
      SettingsScreen(
        // экран настройки
        repo: repo, // репозиторий
        onRefresh: _reload, // функция для перезагрузки данных
        onLogout: () => setState(() {
          tab = 0;
        }), // функция для выхода
        onToggleTheme: widget.onToggleTheme, // функция для переключения темы
      ),
    ];

    final isDark = widget.isDark; // признак темной темы
    final accent = isDark ? kAccent : kAccentDark;
    final navBg = isDark
        ? const Color(0xFF0E0E0E)
        : Colors.white; // цвет фона навигации
    final appBarBg = isDark
        ? const Color(0xFF0A0A0A)
        : Colors.white; // цвет фона AppBar

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0A)
          : const Color(0xFFF2F4F6), // цвет фона
      appBar: AppBar(
        backgroundColor: appBarBg, // цвет фона AppBar
        elevation: 0,
        title: Text(
          'TEMPERATURA.KZ',
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          // действия
          IconButton(
            onPressed: loading
                ? null
                : _reload, // функция для перезагрузки данных
            icon: Icon(
              Icons.refresh, // иконка для перезагрузки данных
              color: isDark ? Colors.white54 : Colors.black54,
            ), // цвет иконки
          ),
          IconButton(
            onPressed: loading
                ? null
                : () async {
                    // функция для выхода
                    await repo.logout(); // выход
                    setState(() {
                      tab = 0;
                    }); // устанавливаем таб на главную
                  },
            icon: const Icon(
              Icons.logout,
              color: Color(0xFFFF5252),
            ), // иконка для выхода
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                repo.role.name,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? Center(
              child: CircularProgressIndicator(color: accent),
            ) // индикатор загрузки
          : Column(
              children: [
                if (error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFF5252).withOpacity(0.15),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      error!, // ошибка
                      style: const TextStyle(
                        color: Color(0xFFFF5252),
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(child: screens[tab]),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        // навигация
        backgroundColor: navBg, // цвет фона навигации
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withOpacity(0.18), // цвет индикатора
        selectedIndex: tab,
        onDestinationSelected: (v) =>
            setState(() => tab = v), // функция для выбора пункта навигации
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.home_outlined, // иконка для главного экрана
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(Icons.home, color: accent),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.sensors_outlined, // иконка для экрана датчиков
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(Icons.sensors, color: accent),
            label: 'Датчики',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.bar_chart_outlined, // иконка для экрана отчетов
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(Icons.bar_chart, color: accent),
            label: 'Отчёты',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.notifications_outlined, // иконка для экрана уведомлений
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(Icons.notifications, color: accent),
            label: 'Увед.',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.settings_outlined, // иконка для экрана настроек
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            selectedIcon: Icon(Icons.settings, color: accent),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
