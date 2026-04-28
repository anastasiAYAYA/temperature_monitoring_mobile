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
class AppColors {
  const AppColors._({required this.isDark});

  final bool isDark;

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
  Color get accent => kAccent;
  Color get cyan   => kCyan;
  Color get green  => kGreen;
  Color get red    => kRed;
  Color get orange => kOrange;

  static const AppColors dark  = AppColors._(isDark: true);
  static const AppColors light = AppColors._(isDark: false);
}

// ── InheritedWidget — провайдер темы ─────────────────────────────────────────
class AppThemeProvider extends InheritedWidget {
  const AppThemeProvider({
    super.key,
    required this.isDark,
    required this.toggle,
    required super.child,
  });

  final bool isDark;
  final VoidCallback toggle;

  AppColors get colors => isDark ? AppColors.dark : AppColors.light;

  static AppThemeProvider of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    assert(result != null, 'AppThemeProvider not found in widget tree');
    return result!;
  }

  /// Безопасная версия — не падает если провайдер не найден (возвращает тёмную)
  static AppThemeProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();

  @override
  bool updateShouldNotify(AppThemeProvider old) => old.isDark != isDark;
}

// ── MaterialTheme по режиму ───────────────────────────────────────────────────
ThemeData buildMaterialTheme({required bool isDark}) {
  if (isDark) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _DarkPalette.bg,
      colorScheme: const ColorScheme.dark(
        primary: kCyan,
        secondary: kAccent,
        surface: _DarkPalette.surface,        // тёмный — фон диалогов
        onSurface: Colors.white,              // белый — текст в диалогах
      ),
      dividerColor: _DarkPalette.border,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  } else {
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