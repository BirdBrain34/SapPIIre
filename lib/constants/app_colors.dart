import 'package:flutter/material.dart';

class AppColors {
  
  
  // Background & Branding Panel
  static const Color primaryBlue = Color(0xFF0D1B4E); // Deep navy (Scaffold bg)
  static const Color midBlue = Color(0xFF1A3A8F);     // Rich blue (Gradient end)
  
  // Card
  static const Color accentBlue = Color(0xFF152257);  // Lighter navy (Card surface)
  static const Color highlight = Color(0xFF4C8BF5);   // CTA Blue (Primary Button)
  
  // Text & Icons
  static const Color mutedBlue = Color(0xFF8BAEE0);   // Subtitles / Muted text
  static const Color lightBlue = Color(0xFF6EA8FE);   // Icons / Forgot Password link
  static const Color labelBlue = Color(0xFFB8CCF0);   // Field labels (Username/Password)
  static const Color copyrightBlue = Color(0xFF3D5A99); // Footer copyright text
  
  // Inputs & Dividers
  static const Color borderNavy = Color(0xFF2A3F7A);  // Borders & Divider lines
  static const Color inputBg = Color(0xFF0D1B4E);     // Darkest navy (Input fields)
  static const Color hintText = Color(0xFF4A6499);    // Placeholder text color
  static const Color featureIconBg = Color(0xFF1E3570); // Background for feature icons

  // ── Status Colors (From Web Snackbars) ─────────────────────────
  static const Color successGreen = Color(0xFF2EC4B6); // Teal green
  static const Color dangerRed = Color(0xFFE63946);    // Red
  static const Color warningAmber = Color(0xFFF4A261); // Amber (Legacy)

  // ── Utility / Legacy Support ───────────────────────────────────
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  static const Color transparent = Colors.transparent;

  // Aliases for compatibility
  static const Color success = successGreen;
  static const Color danger = dangerRed;

    // ── Page / content area ────────────────────────────────────────
  static const Color pageBg = Color(0xFFF5F6FA); // off-white page bg
  static const Color cardBg = Color(0xFFFFFFFF); // white cards
  static const Color cardBorder = Color(0xFFE8ECF4); // subtle card border
   // input fields on light bg
  static const Color textDark = Color(0xFF1C2B4A); // dark text
  static const Color textMuted = Color(0xFF8A94B0); // muted grey-blue text

  // ── Legacy (keep so mobile still compiles) ─────────────────────
  static const Color buttonPurple = Color(0xFF673AB7);
  static const Color buttonOutlineBlue = Color(0xFF42A5F5);



}