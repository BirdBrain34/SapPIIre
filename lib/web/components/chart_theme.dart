import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/constants/app_text_styles.dart';

/// Shared visual language for every dashboard chart.
///
/// Centralises what used to be re-invented per widget — the categorical colour
/// order, gridline/axis ink, tooltip styling, number formatting, and the card /
/// empty / loading / error shells. All charts pull from here, so they read as
/// one system instead of each file inventing its own palette and spacing.
///
/// The categorical palette is brand-anchored (AppColors blue / teal / violet)
/// and was validated for colour-blind separation with the data-viz palette
/// checker: worst adjacent CVD ΔE 15.4, normal-vision ΔE 19.6 on the white card
/// surface. Colours are assigned by slot in a **fixed order** (never cycled by
/// rank), so a series keeps its colour when the set changes. The teal/yellow/
/// magenta slots sit below 3:1 contrast on white; every chart that uses them
/// also shows direct value labels, which is the documented relief for that.
class ChartTheme {
  ChartTheme._();

  /// Fixed categorical order. Bucket into "Other" before exceeding 8 rather than
  /// relying on the wrap-around in [colorAt].
  static const List<Color> categorical = [
    Color(0xFF4C8BF5), // 1 blue    — brand highlight
    Color(0xFFEB6834), // 2 orange
    Color(0xFF2EC4B6), // 3 teal    — brand success
    Color(0xFFEDA100), // 4 yellow
    Color(0xFFE87BA4), // 5 magenta
    Color(0xFF008300), // 6 green
    Color(0xFF673AB7), // 7 violet  — brand button
    Color(0xFFE34948), // 8 red
  ];

  /// Colour for categorical slot [index]. Wraps past 8 as a last resort.
  static Color colorAt(int index) => categorical[index % categorical.length];

  // ── Chrome & ink ─────────────────────────────────────────────────────────
  static const Color gridLine = AppColors.cardBorder; // #E8ECF4 hairline
  static const Color axisLine = Color(0xFFD5DBE8);
  static const Color axisText = AppColors.textMuted; // #8A94B0
  static const Color primaryInk = AppColors.textDark; // #1C2B4A
  static const Color tooltipBg = AppColors.textDark;

  /// Axis ticks share the app's small-label style so chart text matches the UI.
  static const TextStyle axisLabelStyle = AppTextStyles.labelSmall;

  static const TextStyle tooltipTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  // ── Number formatting ──────────────────────────────────────────────────────
  /// Compact integers for axis ticks and tooltips: 1500 → 1.5k, 2000000 → 2M.
  static String compact(num v) {
    final a = v.abs();
    if (a >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    }
    if (a >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v.toStringAsFixed(0);
  }

  static String percentOf(int count, int total) =>
      total > 0 ? '${(count / total * 100).toStringAsFixed(1)}%' : '0%';

  /// A "nice" axis top and matching tick interval for a raw max value, so the
  /// y-axis ends on a round number with ~4 gridlines instead of a ragged edge.
  static ({double maxY, double interval}) niceAxis(double rawMax) {
    if (rawMax <= 0) return (maxY: 1, interval: 1);
    const targetTicks = 4;
    final rough = rawMax / targetTicks;
    final mag = _pow10((rough).floor().toString().length - 1);
    final norm = rough / mag;
    final step = norm <= 1
        ? 1.0
        : norm <= 2
            ? 2.0
            : norm <= 5
                ? 5.0
                : 10.0;
    final interval = step * mag;
    final maxY = (rawMax / interval).ceil() * interval;
    return (maxY: maxY, interval: interval);
  }

  static double _pow10(int e) {
    var r = 1.0;
    for (var i = 0; i < e; i++) {
      r *= 10;
    }
    return r;
  }
}

/// Standard card shell shared by all charts — consistent padding, header, and
/// a fixed plot height so cards in a responsive grid line up.
class ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final double? height;

  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          if (height != null) SizedBox(height: height, child: child) else child,
        ],
      ),
    );
  }
}

/// Consistent empty / loading / error placeholders so a chart never renders as a
/// blank box or a raw exception string.
class ChartStates {
  ChartStates._();

  static Widget empty(String title, {String message = 'No data available'}) =>
      _shell(
        title,
        Icons.bar_chart_outlined,
        message,
        AppColors.textMuted,
      );

  static Widget error(String title, {String message = 'Could not load data'}) =>
      _shell(
        title,
        Icons.error_outline,
        message,
        AppColors.dangerRed,
      );

  static Widget loading(String title) => ChartCard(
        title: title,
        height: 200,
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );

  static Widget _shell(
    String title,
    IconData icon,
    String message,
    Color tint,
  ) =>
      ChartCard(
        title: title,
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: tint.withValues(alpha: 0.35)),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

/// A wrap-based legend for categorical series (dot + label + value), used by the
/// pie/donut charts where identity can't live on an axis. Keeps identity off
/// colour-alone and doubles as the direct-label relief for low-contrast slots.
class ChartLegend extends StatelessWidget {
  final List<({String label, Color color, int value})> items;
  final int total;

  const ChartLegend({super.key, required this.items, required this.total});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items.map((it) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: it.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              it.label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${it.value} · ${ChartTheme.percentOf(it.value, total)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// Reusable donut chart (fl_chart) shared by both pie charts on the dashboard.
///
/// Takes pre-coloured items so callers control identity (form-card colours or
/// the categorical palette). Renders a donut with the running total in the hole,
/// slice %-labels for large-enough slices, a hover-to-expand highlight, and a
/// legend underneath — so identity never rests on colour alone.
class PieChartView extends StatefulWidget {
  final List<({String label, Color color, int value})> items;
  final bool showPercentage;

  const PieChartView({
    super.key,
    required this.items,
    this.showPercentage = true,
  });

  @override
  State<PieChartView> createState() => _PieChartViewState();
}

class _PieChartViewState extends State<PieChartView> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final items = widget.items.where((it) => it.value > 0).toList();
    final total = items.fold<int>(0, (a, b) => a + b.value);
    if (items.isEmpty || total == 0) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, resp) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            resp == null ||
                            resp.touchedSection == null) {
                          _touched = -1;
                          return;
                        }
                        _touched = resp.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  sections: [
                    for (var i = 0; i < items.length; i++)
                      _section(items[i], i, total),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ChartTheme.compact(total),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Text(
                    'total',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ChartLegend(
          items: items,
          total: total,
        ),
      ],
    );
  }

  PieChartSectionData _section(
    ({String label, Color color, int value}) it,
    int index,
    int total,
  ) {
    final isTouched = index == _touched;
    final pct = it.value / total * 100;
    return PieChartSectionData(
      value: it.value.toDouble(),
      color: it.color,
      radius: isTouched ? 62 : 54,
      // Only label slices with room, so text never spills off a thin wedge.
      title: widget.showPercentage && pct >= 8
          ? '${pct.toStringAsFixed(0)}%'
          : '',
      titleStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      titlePositionPercentageOffset: 0.6,
    );
  }
}
