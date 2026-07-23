import 'package:flutter/material.dart';

import 'package:sappiire/config/retention_config.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/retention_analytics_service.dart';
import 'package:sappiire/web/widgets/retention_summary_cards.dart';

/// Dashboard section that summarises how many finalized records have gone stale
/// and offers a jump into the full data-retention screen.
///
/// Admin-only — the caller is responsible for gating it behind a role check.
/// Fetches its own summary so it stays self-contained; a failed or empty fetch
/// simply renders zeroed cards rather than an error.
class DashboardRetentionSummary extends StatefulWidget {
  const DashboardRetentionSummary({
    super.key,
    required this.onReview,
    this.refreshToken = 0,
  });

  /// Invoked by the "Review stale records" action to open the full screen.
  final VoidCallback onReview;

  /// Bump to force a re-fetch (e.g. after a date-range change upstream).
  final int refreshToken;

  @override
  State<DashboardRetentionSummary> createState() =>
      _DashboardRetentionSummaryState();
}

class _DashboardRetentionSummaryState extends State<DashboardRetentionSummary> {
  final _service = RetentionAnalyticsService();

  Map<RetentionTier, int> _counts = {
    for (final t in RetentionConfig.tiersAscending) t.tier: 0,
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardRetentionSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final counts = await _service.fetchStaleSummary();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _loading = false;
    });
  }

  int get _total => _counts.values.fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppColors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.warningAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.warningAmber,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Data Retention',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Old records that may be due for archival review',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onReview,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Review stale records'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.highlight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (_total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: AppColors.successGreen.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'No stale records — everything has been updated recently.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            )
          else
            RetentionSummaryCards(counts: _counts),
        ],
      ),
    );
  }
}
