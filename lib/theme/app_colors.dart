import 'package:flutter/material.dart';
import 'app_theme.dart';

// Акцентные цвета (одинаковы в обеих темах)
const kAccent = Color(0xFFFFD550); // жёлтый (фон, бордеры)
const kCyan = Color(0xFF0086A8); // голубой
const kGreen = Color(0xFF25C778); // зелёный
const kRed = Color(0xFFFF5252); // красный
const kOrange = Color(0xFFFFB300); // оранжевый
const kTextDim = Color(0xFF7A8A8E); // приглушённый (тёмная тема)
const kAccentDark = Color(0xFFf5a714);
const kGreenDark = Color(0xFF1F8A5B);

class AppColors {
  AppColors._();

  static const primary = kAccent;
  static const danger = kRed;
  static const success = kGreen;
  static const info = kCyan;
  static const warning = kOrange;

  static AppScheme of(BuildContext context) {
    final p = AppThemeProvider.maybeOf(context);
    return (p?.isDark ?? true)
        ? const AppScheme.dark()
        : const AppScheme.light();
  }
}

class AppScheme {
  const AppScheme.dark()
    : bg = const Color(0xFF0A0A0A),
      card = const Color(0x4D323232),
      card2 = const Color(0x334B4B4B),
      border = const Color(0xFF19282B),
      textMain = Colors.white,
      textDim = const Color(0xFF7A8A8E),
      surface = const Color(0xFF111111),
      yellowBg = const Color(0xFF312C1C),
      redBg = const Color(0xFF321C1B),
      greenBg = const Color(0xFF0D2B1F),
      // В тёмной теме жёлтый читается хорошо
      accentText = kAccent,
      isDark = true;

  const AppScheme.light()
    : bg = const Color(0xFFFBFCFE),
      card = const Color(0xFFFFFFFF),
      card2 = const Color(0xFFF6FBFD),
      border = const Color(0xFFE3EBF0),
      textMain = const Color(0xFF102A3A),
      textDim = const Color(0xFF5E7280),
      surface = const Color(0xFFFFFFFF),
      yellowBg = const Color(0xFFFFF4D6),
      redBg = const Color(0xFFFFECEF),
      greenBg = const Color(0xFFE8F6EF),
      accentText = kAccentDark,
      isDark = false;

  final Color bg;
  final Color card;
  final Color card2;
  final Color border;
  final Color textMain;
  final Color textDim;
  final Color surface;
  final Color yellowBg;
  final Color redBg;
  final Color greenBg;
  final bool isDark;

  /// Цвет текста/иконок поверх жёлтого фона.
  /// Тёмная тема: kAccent (жёлтый), светлая: kAccentDark (янтарно-коричневый).
  final Color accentText;

  /// Фирменный жёлтый: яркий в тёмной теме, более тёмный янтарь в светлой (читаемость на белом).
  Color get accent => isDark ? kAccent : kAccentDark;

  Color get green => isDark ? kGreen : kGreenDark;

  Color get cyan => kCyan;
  Color get red => kRed;
  Color get orange => kOrange;
}
