import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Акцентные цвета — одинаковы в тёмной и светлой теме
const kAccent = Color(0xFFFFD550); // жёлтый
const kCyan   = Color(0xFF07BCD4); // голубой
const kGreen  = Color(0xFF01E676); // зелёный
const kRed    = Color(0xFFFF5252); // красный
const kOrange  = Color(0xFFFFB300); // оранжевый
const kTextDim = Color(0xFF7A8A8E); // приглушённый (тёмная тема)

/// Статические константы для обратной совместимости
/// (sensor_dot, login_screen и др. используют AppColors.primary и т.д.)
class AppColors {
  AppColors._();

  static const primary  = kAccent;
  static const danger   = kRed;
  static const success  = kGreen;
  static const info     = kCyan;
  static const warning  = kOrange;

  /// Динамические цвета текущей темы.
  /// Использование: `final c = AppColors.of(context);`
  static AppScheme of(BuildContext context) {
    final p = AppThemeProvider.maybeOf(context);
    return (p?.isDark ?? true) ? const AppScheme.dark() : const AppScheme.light();
  }
}

class AppScheme {
  const AppScheme.dark()
      : bg       = const Color(0xFF0A0A0A),
        card     = const Color(0x4D323232),
        card2    = const Color(0x334B4B4B),
        border   = const Color(0xFF19282B),
        textMain = Colors.white,
        textDim  = const Color(0xFF7A8A8E),
        surface  = const Color(0xFF111111),
        yellowBg = const Color(0xFF312C1C),
        redBg    = const Color(0xFF321C1B),
        greenBg  = const Color(0xFF0D2B1F),
        isDark   = true;

  const AppScheme.light()
      : bg       = const Color(0xFFF2F4F6),
        card     = const Color(0xFFFFFFFF),
        card2    = const Color(0xFFEEF1F4),
        border   = const Color(0xFFD1DBE3),
        textMain = const Color(0xFF0D1B2A),
        textDim  = const Color(0xFF7A8A9E),
        surface  = const Color(0xFFFFFFFF),
        yellowBg = const Color(0xFFFFF8E1),
        redBg    = const Color(0xFFFFEBEE),
        greenBg  = const Color(0xFFE8F5E9),
        isDark   = false;

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

  // Акценты — одинаковы в обеих темах
  Color get accent => kAccent;
  Color get cyan   => kCyan;
  Color get green  => kGreen;
  Color get red    => kRed;
  Color get orange => kOrange;
}