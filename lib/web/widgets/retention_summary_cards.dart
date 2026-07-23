import 'package:flutter/material.dart';

import 'package:sappiire/config/retention_config.dart';
import 'package:sappiire/constants/app_colors.dart';

/// Horizontal row of staleness-tier summary cards (Aging / Stale / Very stale)
/// plus a leading total. Driven entirely by [RetentionConfig] so re-tuning the
/// tiers changes these cards automatically.
///
/// Shared between the dashboard summary section and the full data-retention
/// screen so both read identically.
class RetentionSummaryCards extends StatelessWidget {
  const RetentionSummaryCards({
    super.key,
    required this.counts,
    this.selectedTier,
    this.onTierTap,
  });

  /// Count per stale tier. Missing tiers render as zero.
  final Map<RetentionTier, int> counts;

  /// When set, that tier's card is drawn selected. Null = none selected.
  final RetentionTier? selectedTier;

  /// Tapping a tier card invokes this (e.g. to filter the table). Passing the
  /// already-selected tier is the caller's cue to clear the filter. Null makes
  /// the cards non-interactive (dashboard summary use).
  final void Function(RetentionTier tier)? onTierTap;

  int get _total =>
      counts.values.fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    final tiers = RetentionConfig.tiersAscending;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card(
              label: 'All stale records',
              description: '${RetentionConfig.staleFromYears.toStringAsFixed(0)}+ years old',
              value: _total,
              color: AppColors.primaryBlue,
              selected: false,
              onTap: null,
            ),
            const SizedBox(width: 12),
            for (final t in tiers) ...[
              _card(
                label: t.label,
                description: t.description,
                value: counts[t.tier] ?? 0,
                color: t.color,
                selected: selectedTier == t.tier,
                onTap: onTierTap == null ? null : () => onTierTap!(t.tier),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({
    required String label,
    required String description,
    required int value,
    required Color color,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final card = Container(
      width: 168,
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: selected ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: selected ? 0.7 : 0.25),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}
