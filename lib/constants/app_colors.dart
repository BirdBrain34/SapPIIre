import 'package:flutter/material.dart';

class AppColors {
  // Brand colors used for the main app surfaces and accents.
  static const Color primaryBlue = Color(0xFF0D1B4E);
  static const Color midBlue = Color(0xFF1A3A8F);

  // Card and highlight colors.
  static const Color accentBlue = Color(0xFF152257);
  static const Color highlight = Color(0xFF4C8BF5);

  // Text, icon, and label colors.
  static const Color mutedBlue = Color(0xFF8BAEE0);
  static const Color lightBlue = Color(0xFF6EA8FE);
  static const Color labelBlue = Color(0xFFB8CCF0);
  static const Color copyrightBlue = Color(0xFF3D5A99);

  // Inputs and divider colors.
  static const Color borderNavy = Color(0xFF2A3F7A);
  static const Color inputBg = Color(0xFF0D1B4E);
  static const Color hintText = Color(0xFF4A6499);
  static const Color featureIconBg = Color(0xFF1E3570);

  // Status colors used by snackbars and alerts.
  static const Color successGreen = Color(0xFF2EC4B6);
  static const Color dangerRed = Color(0xFFE63946);
  static const Color warningAmber = Color(0xFFF4A261);

  // Core neutral colors.
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  static const Color transparent = Colors.transparent;

  // Legacy aliases kept for older screens and widgets.
  static const Color success = successGreen;
  static const Color danger = dangerRed;

  // Page and content surfaces.
  static const Color pageBg = Color(0xFFF5F6FA);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE8ECF4);
  static const Color textDark = Color(0xFF1C2B4A);
  static const Color textMuted = Color(0xFF8A94B0);

  // Legacy colors kept so older mobile widgets continue to compile.
  static const Color buttonPurple = Color(0xFF673AB7);
  static const Color buttonOutlineBlue = Color(0xFF42A5F5);

  /// Standard white card surface used across the web admin screens:
  /// rounded corners, a subtle border, and a soft drop shadow. Shared so the
  /// card look stays consistent and is defined in one place.
  /// [elevation] controls the depth: 1 (subtle), 2 (medium), 3 (deep).
  static BoxDecoration cardDecoration({double radius = 16, int elevation = 1}) {
    final shadow = switch (elevation) {
      3 => BoxShadow(
          color: Colors.black.withValues(alpha:  0.14),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      2 => BoxShadow(
          color: Colors.black.withValues(alpha:  0.09),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      _ => BoxShadow(
          color: Colors.black.withValues(alpha:  0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
    };
    return BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: cardBorder, width: 1),
      boxShadow: [shadow],
    );
  }
}
