import 'package:flutter/material.dart';

/// Staleness classification for finalized applicant records.
///
/// A record's "age" is measured from the last time it changed —
/// `COALESCE(last_edited_at, created_at)` on `client_submissions` — not from
/// when it was first created. A record edited last month is not stale even if
/// it was first filed years ago.
///
/// Tiers are intentionally defined as ordinary data in [RetentionConfig.tiers]
/// so the thresholds can be re-tuned in one place without touching the service,
/// the dashboard, or the retention screen. Change the year boundaries there and
/// everything downstream follows.
enum RetentionTier {
  /// Recently created or updated — not a candidate for archival.
  fresh,

  /// 3–5 years since last update.
  aging,

  /// 5–10 years since last update.
  stale,

  /// 10+ years since last update.
  veryStale,
}

/// A single staleness band: its inclusive lower bound in years, its exclusive
/// upper bound (null = open-ended), and how it should read on screen.
class RetentionThreshold {
  const RetentionThreshold({
    required this.tier,
    required this.label,
    required this.description,
    required this.minYears,
    required this.maxYears,
    required this.color,
  });

  final RetentionTier tier;

  /// Short badge/label text, e.g. "Stale".
  final String label;

  /// One-line explanation of the band, e.g. "5–10 years since last update".
  final String description;

  /// Inclusive lower bound, in years.
  final double minYears;

  /// Exclusive upper bound, in years. `null` means open-ended (10+).
  final double? maxYears;

  /// Accent colour used for the tier's cards, badges, and chart segments.
  final Color color;
}

/// Central, easy-to-adjust definition of the staleness tiers.
///
/// To re-tune the policy, edit the [tiers] list below — e.g. move "stale" to
/// start at 6 years, or add a fourth band. Nothing else needs to change: the
/// classifier, the dashboard summary, and the retention table all read from
/// here.
class RetentionConfig {
  RetentionConfig._();

  /// Days per year used when converting an age in days to years. 365.25
  /// absorbs leap years so a record does not flicker between tiers around an
  /// anniversary.
  static const double _daysPerYear = 365.25;

  /// The staleness bands, ordered oldest-first. Only the "stale" bands are
  /// listed — anything younger than the first band's [RetentionThreshold.minYears]
  /// is treated as [RetentionTier.fresh] and is never surfaced as a candidate
  /// for archival.
  ///
  /// Adjust the year boundaries here to change the policy.
  static const List<RetentionThreshold> tiers = [
    RetentionThreshold(
      tier: RetentionTier.veryStale,
      label: 'Very stale',
      description: '10+ years since last update',
      minYears: 10,
      maxYears: null,
      color: Color(0xFFE63946), // dangerRed
    ),
    RetentionThreshold(
      tier: RetentionTier.stale,
      label: 'Stale',
      description: '5–10 years since last update',
      minYears: 5,
      maxYears: 10,
      color: Color(0xFFF4A261), // warningAmber
    ),
    RetentionThreshold(
      tier: RetentionTier.aging,
      label: 'Aging',
      description: '3–5 years since last update',
      minYears: 3,
      maxYears: 5,
      color: Color(0xFFE9C46A), // muted gold
    ),
  ];

  /// The stale tiers in ascending age order (aging → stale → very stale),
  /// convenient for building filter dropdowns and left-to-right summaries.
  static List<RetentionThreshold> get tiersAscending =>
      tiers.reversed.toList(growable: false);

  /// Threshold metadata for [tier], or `null` for [RetentionTier.fresh].
  static RetentionThreshold? thresholdFor(RetentionTier tier) {
    for (final t in tiers) {
      if (t.tier == tier) return t;
    }
    return null;
  }

  /// The age, in years, at which a record first becomes a candidate for
  /// archival review (the youngest stale band's lower bound).
  static double get staleFromYears =>
      tiers.map((t) => t.minYears).reduce((a, b) => a < b ? a : b);

  /// Classifies an age expressed in whole days into a [RetentionTier].
  static RetentionTier classifyDays(int ageDays) {
    final years = ageDays / _daysPerYear;
    for (final t in tiers) {
      final aboveMin = years >= t.minYears;
      final belowMax = t.maxYears == null || years < t.maxYears!;
      if (aboveMin && belowMax) return t.tier;
    }
    return RetentionTier.fresh;
  }

  /// Classifies a record by its effective last-updated timestamp.
  static RetentionTier classify(DateTime lastUpdated, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final ageDays = reference.difference(lastUpdated).inDays;
    if (ageDays < 0) return RetentionTier.fresh;
    return classifyDays(ageDays);
  }

  /// A record is a candidate for archival if it falls in any stale band.
  static bool isStale(RetentionTier tier) => tier != RetentionTier.fresh;

  /// Human-readable age, e.g. "4 yr 2 mo" or "7 mo", for table display.
  static String formatAge(int ageDays) {
    if (ageDays < 0) return '—';
    if (ageDays < 30) return '$ageDays d';
    final years = ageDays ~/ 365;
    final months = (ageDays % 365) ~/ 30;
    if (years <= 0) return '$months mo';
    if (months <= 0) return '$years yr';
    return '$years yr $months mo';
  }
}
