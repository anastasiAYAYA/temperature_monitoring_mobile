import 'package:flutter/material.dart';

// ── Акцентные цвета ───────────────────────────────────────────────────────────
const kAccent = Color(0xFFFFD550); // жёлтый (фон кнопок, бордеры)
const kAccentDark = Color(
  0xFFf5a714,
); // янтарно-коричневый — текст на жёлтом в светлой теме
const kCyan = Color(0xFF0086A8);
const kGreen = Color(0xFF25C778);
const kGreenDark = Color(0xFF1F8A5B);
const kRed = Color(0xFFFF5252);
const kOrange = Color(0xFFFFB300);

// ── Тёмная тема ───────────────────────────────────────────────────────────────
class _DarkPalette {
  static const bg = Color(0xFF0A0A0A);
  static const card = Color(0x4D323232);
  static const card2 = Color(0x334B4B4B);
  static const border = Color(0xFF19282B);
  static const textDim = Color(0xFF7A8A8E);
  static const textMain = Colors.white;
  static const yellowBg = Color(0xFF312C1C);
  static const redBg = Color(0xFF321C1B);
  static const greenBg = Color(0xFF0D2B1F);
  static const surface = Color(0xFF111111);
}

// ── Светлая тема ──────────────────────────────────────────────────────────────
class _LightPalette {
  static const bg = Color(0xFFFBFCFE);
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF6FBFD);
  static const border = Color(0xFFE3EBF0);
  static const textDim = Color(0xFF5E7280);
  static const textMain = Color(0xFF102A3A);
  // Чуть насыщеннее чем чистый белый — жёлтый заметнее
  static const yellowBg = Color(0xFFFFF4D6);
  static const redBg = Color(0xFFFFECEF);
  static const greenBg = Color(0xFFE8F6EF);
  static const surface = Color(0xFFFFFFFF);
}

// ── AppColors ─────────────────────────────────────────────────────────────────
class AppColors {
  const AppColors._({required this.isDark});
  final bool isDark;

  Color get bg => isDark ? _DarkPalette.bg : _LightPalette.bg;
  Color get card => isDark ? _DarkPalette.card : _LightPalette.card;
  Color get card2 => isDark ? _DarkPalette.card2 : _LightPalette.card2;
  Color get border => isDark ? _DarkPalette.border : _LightPalette.border;
  Color get textDim => isDark ? _DarkPalette.textDim : _LightPalette.textDim;
  Color get textMain => isDark ? _DarkPalette.textMain : _LightPalette.textMain;
  Color get yellowBg => isDark ? _DarkPalette.yellowBg : _LightPalette.yellowBg;
  Color get redBg => isDark ? _DarkPalette.redBg : _LightPalette.redBg;
  Color get greenBg => isDark ? _DarkPalette.greenBg : _LightPalette.greenBg;
  Color get surface => isDark ? _DarkPalette.surface : _LightPalette.surface;

  Color get accent => isDark ? kAccent : kAccentDark;
  Color get cyan => kCyan;
  Color get green => isDark ? kGreen : kGreenDark;
  Color get red => kRed;
  Color get orange => kOrange;

  /// Цвет текста/иконок поверх жёлтого фона.
  /// Тёмная: kAccent (жёлтый читается на тёмном), светлая: kAccentDark (коричневый).
  Color get accentText => isDark ? kAccent : kAccentDark;

  static const AppColors dark = AppColors._(isDark: true);
  static const AppColors light = AppColors._(isDark: false);
}

// ── AppThemeProvider ──────────────────────────────────────────────────────────
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
    final result = context
        .dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    assert(result != null, 'AppThemeProvider not found in widget tree');
    return result!;
  }

  static AppThemeProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();

  @override
  bool updateShouldNotify(AppThemeProvider old) => old.isDark != isDark;
}

// ── MaterialTheme ─────────────────────────────────────────────────────────────
ThemeData buildMaterialTheme({required bool isDark}) {
  if (isDark) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _DarkPalette.bg,
      colorScheme: const ColorScheme.dark(
        primary: kCyan,
        secondary: kAccentDark,
        surface: _DarkPalette.surface,
        onSurface: Colors.white,
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
        surface: _LightPalette.surface,
        onSurface: _LightPalette.textMain,
      ),
      dividerColor: _LightPalette.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _LightPalette.textMain,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      cardColor: _LightPalette.card,
      dialogBackgroundColor: _LightPalette.surface,
    );
  }
}
