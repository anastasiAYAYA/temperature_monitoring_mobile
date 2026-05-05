import 'package:flutter/material.dart';

// ── Акцентные цвета (одинаковы в обеих темах) ─────────────────────────────────
const kAccent = Color(0xFFFFD550); // жёлтый
const kCyan   = Color(0xFF07BCD4); // голубой
const kGreen  = Color(0xFF01E676); // зелёный
const kRed    = Color(0xFFFF5252); // красный
const kOrange = Color(0xFFFFB300); // оранжевый

// ── Тёмная тема ───────────────────────────────────────────────────────────────
class _DarkPalette {
  static const bg       = Color(0xFF0A0A0A);
  static const card     = Color(0x4D323232);
  static const card2    = Color(0x334B4B4B);
  static const border   = Color(0xFF19282B);
  static const textDim  = Color(0xFF7A8A8E);
  static const textMain = Colors.white;
  static const yellowBg = Color(0xFF312C1C);
  static const redBg    = Color(0xFF321C1B);
  static const greenBg  = Color(0xFF0D2B1F);
  static const surface  = Color(0xFF111111); // диалоги
}

// ── Светлая тема ──────────────────────────────────────────────────────────────
class _LightPalette {
  static const bg       = Color(0xFFF2F4F6);
  static const card     = Color(0xFFFFFFFF);
  static const card2    = Color(0xFFEEF1F4);
  static const border   = Color(0xFFD1DBE3);
  static const textDim  = Color(0xFF7A8A9E);
  static const textMain = Color(0xFF0D1B2A);
  static const yellowBg = Color(0xFFFFF8E1);
  static const redBg    = Color(0xFFFFEBEE);
  static const greenBg  = Color(0xFFE8F5E9);
  static const surface  = Color(0xFFFFFFFF); // диалоги
}

// ── AppColors — текущие цвета в зависимости от темы ──────────────────────────
class AppColors { // класс для получения цветов в зависимости от темы
  const AppColors._({required this.isDark}); // конструктор класса

  final bool isDark; // признак темной темы

  Color get bg       => isDark ? _DarkPalette.bg       : _LightPalette.bg;
  Color get card     => isDark ? _DarkPalette.card     : _LightPalette.card;
  Color get card2    => isDark ? _DarkPalette.card2    : _LightPalette.card2;
  Color get border   => isDark ? _DarkPalette.border   : _LightPalette.border;
  Color get textDim  => isDark ? _DarkPalette.textDim  : _LightPalette.textDim;
  Color get textMain => isDark ? _DarkPalette.textMain : _LightPalette.textMain;
  Color get yellowBg => isDark ? _DarkPalette.yellowBg : _LightPalette.yellowBg;
  Color get redBg    => isDark ? _DarkPalette.redBg    : _LightPalette.redBg;
  Color get greenBg  => isDark ? _DarkPalette.greenBg  : _LightPalette.greenBg;
  Color get surface  => isDark ? _DarkPalette.surface  : _LightPalette.surface;

  // Акценты одинаковы
  Color get accent => kAccent; // жёлтый
  Color get cyan   => kCyan; // голубой
  Color get green  => kGreen; // зелёный
  Color get red    => kRed; // красный
  Color get orange => kOrange; // оранжевый

  static const AppColors dark  = AppColors._(isDark: true); // тёмная тема
  static const AppColors light = AppColors._(isDark: false); // светлая тема
}

// ── InheritedWidget — провайдер темы ─────────────────────────────────────────
class AppThemeProvider extends InheritedWidget { // класс для получения цветов в зависимости от темы
  const AppThemeProvider({
    super.key, // ключ для идентификации
    required this.isDark, // признак темной темы
    required this.toggle, // функция для переключения темы
    required super.child, // child - дочерний виджет
  });

  final bool isDark; // признак темной темы
  final VoidCallback toggle; // функция для переключения темы

  AppColors get colors => isDark ? AppColors.dark : AppColors.light; // получение цветов в зависимости от темы

  static AppThemeProvider of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppThemeProvider>()!; // получение провайдера темы из контекста

  @override
  bool updateShouldNotify(AppThemeProvider old) => old.isDark != isDark; // обновление при изменении признака темной темы
}

// ── MaterialTheme по режиму ───────────────────────────────────────────────────
ThemeData buildMaterialTheme({required bool isDark}) { // функция для построения темы Material
  if (isDark) { // если темная тема
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _DarkPalette.bg,
      colorScheme: const ColorScheme.dark(
        primary: kCyan,
        secondary: kAccent,
        surface: _DarkPalette.surface,        // тёмный — фон диалогов
        onSurface: Colors.white,              // белый — текст в диалогах
      ),
      dividerColor: _DarkPalette.border, // тёмно-серый разделитель 
      snackBarTheme: const SnackBarThemeData( // тёмная тема
        backgroundColor: Color(0xFF1E1E1E), // тёмно-серый фон
        contentTextStyle: TextStyle(color: Colors.white), // белый текст
      ),
    );
  } else { // если светлая тема
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: _LightPalette.bg,
      colorScheme: const ColorScheme.light(
        primary: kCyan,
        secondary: kAccent,
        surface: _LightPalette.surface,       // белый — фон диалогов
        onSurface: _LightPalette.textMain,    // тёмный — текст в диалогах
      ),
      dividerColor: _LightPalette.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _LightPalette.textMain,
        contentTextStyle:
            const TextStyle(color: Colors.white),
      ),
      cardColor: _LightPalette.card,
      dialogBackgroundColor: _LightPalette.surface,
    );
  }
}