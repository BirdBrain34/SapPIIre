import 'package:flutter/material.dart';

class AppColors {
  // ── Brand blues (login + sidebar) ──────────────────────────────
  static const Color primaryBlue = Color(0xFF0D1B4E); // deep navy
  static const Color accentBlue = Color(0xFF152257); // slightly lighter navy
  static const Color midBlue = Color(0xFF1A3A8F); // gradient mid blue
  static const Color highlight = Color(0xFF4C8BF5); // bright CTA blue
  static const Color lightBlue = Color(0xFF6EA8FE); // icon / accent
  static const Color mutedBlue = Color(0xFF8BAEE0); // secondary text on dark
  static const Color borderNavy = Color(0xFF2A3F7A); // borders on dark bg

  // ── Page / content area ────────────────────────────────────────
  static const Color pageBg = Color(0xFFF5F6FA); // off-white page bg
  static const Color cardBg = Color(0xFFFFFFFF); // white cards
  static const Color cardBorder = Color(0xFFE8ECF4); // subtle card border
  static const Color inputBg = Color(0xFFF0F3FA); // input fields on light bg
  static const Color textDark = Color(0xFF1C2B4A); // dark text
  static const Color textMuted = Color(0xFF8A94B0); // muted grey-blue text

  // ── Status colors ──────────────────────────────────────────────
  static const Color successGreen = Color(0xFF2EC4B6); // teal green
  static const Color dangerRed = Color(0xFFE63946); // red
  static const Color warningAmber = Color(0xFFF4A261); // amber

  // ── Legacy (keep so mobile still compiles) ─────────────────────
  static const Color buttonPurple = Color(0xFF673AB7);
  static const Color buttonOutlineBlue = Color(0xFF42A5F5);
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  
  // Alias for compatibility
  static const Color success = successGreen;
  static const Color danger = dangerRed;
}