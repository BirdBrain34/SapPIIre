import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

/// The one typography scale for the app.
///
/// Before this, text was styled with ~9 ad-hoc `fontSize` values (10–34)
/// scattered inline with no shared weights or colours. These named styles are
/// the single source of truth — reference them instead of writing raw
/// `TextStyle(fontSize: …)`, and wire [textTheme] into the app `ThemeData` so
/// unstyled `Text` widgets inherit consistent defaults.
///
/// One family stack for everything (system sans), with a dedicated [mono] for
/// reference numbers / keys where digit alignment matters.
class AppTextStyles {
  AppTextStyles._();

  /// Fallback stack — no bundled font, so this resolves to the platform UI sans
  /// (Segoe UI on Windows, Roboto on Android/web) consistently everywhere.
  static const String fontFamily = 'Roboto';
  static const List<String> fontFamilyFallback = [
    'Segoe UI',
    'system-ui',
    'Arial',
    'sans-serif',
  ];

  // ── Display / hero numbers ─────────────────────────────────────────────────
  static const TextStyle displayLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    color: AppColors.textDark,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textDark,
  );

  // ── Titles ─────────────────────────────────────────────────────────────────
  /// Section headers ("Summary Metrics", "Planning Insights").
  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textDark,
  );

  /// Card / chart titles.
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textDark,
  );

  // ── Body ─────────────────────────────────────────────────────────────────
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textDark,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textDark,
  );

  // ── Labels / captions ──────────────────────────────────────────────────────
  /// Metric labels, legend entries, chips.
  static const TextStyle labelLarge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: AppColors.textMuted,
  );

  /// Axis ticks, small secondary labels.
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  /// Tiny uppercase eyebrows / stat captions.
  static const TextStyle caption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: AppColors.textMuted,
  );

  /// Reference numbers, canonical keys, IDs — anywhere digit alignment matters.
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    color: AppColors.textDark,
  );

  /// Maps the scale onto Material's [TextTheme] so unstyled widgets inherit it.
  static TextTheme get textTheme => const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        labelLarge: labelLarge,
        labelSmall: labelSmall,
      );
}
