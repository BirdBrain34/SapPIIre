import 'package:fl_chart/fl_chart.dart';
// Prefixed alias: this file declares its own `LineChart`, which shadows
// fl_chart's widget of the same name — `flc.LineChart` reaches the real one.
import 'package:fl_chart/fl_chart.dart' as flc;
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/components/chart_theme.dart';

/// Dashboard chart widgets. Visuals are unified through [ChartTheme] /
/// [ChartCard] / [ChartStates] and the plots are drawn with fl_chart so axes,
/// labels and tooltips stay aligned and responsive. Public constructor
/// signatures are unchanged so the dashboard needs no edits.

/// ============================================================================
/// Metric card — headline KPI tile.
/// ============================================================================
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool expand;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final Color? valueColor;
  final Color? labelColor;
  final Color? subtitleColor;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.subtitle,
    this.onTap,
    this.expand = true,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.valueColor,
    this.labelColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor ?? AppColors.cardBorder,
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (subtitle != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subtitleColor ?? color,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: labelColor ?? AppColors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? AppColors.textDark,
                    letterSpacing: -1,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    if (expand) return Expanded(child: card);
    return card;
  }
}

/// Shared fl_chart building blocks so every cartesian chart uses the same grid,
/// axes and label treatment.
class _Cartesian {
  _Cartesian._();

  static FlGridData hGrid(double interval) => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: ChartTheme.gridLine, strokeWidth: 1),
      );

  static FlBorderData get noBorder => FlBorderData(show: false);

  /// Left (value) axis titles, compact-formatted.
  static AxisTitles leftValueTitles(double interval) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: interval,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            space: 6,
            child: Text(ChartTheme.compact(value), style: ChartTheme.axisLabelStyle),
          ),
        ),
      );

  static AxisTitles get hidden =>
      const AxisTitles(sideTitles: SideTitles(showTitles: false));

  /// Bottom (category) axis titles. Long labels are truncated and rotated so
  /// they never overlap regardless of how many categories there are.
  static AxisTitles bottomCategoryTitles(List<String> labels) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 46,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            var text = labels[i];
            if (text.length > 12) text = '${text.substring(0, 11)}…';
            return SideTitleWidget(
              meta: meta,
              space: 6,
              angle: -0.5,
              child: Text(text, style: ChartTheme.axisLabelStyle, maxLines: 1),
            );
          },
        ),
      );
}

/// ============================================================================
/// Pie / donut chart.
/// ============================================================================
class SimplePieChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final bool showPercentage;

  const SimplePieChart({
    super.key,
    required this.title,
    required this.data,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return ChartStates.empty(title);

    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return ChartStates.empty(title);

    final items = <({String label, Color color, int value})>[
      for (var i = 0; i < entries.length; i++)
        (label: entries[i].key, color: ChartTheme.colorAt(i), value: entries[i].value),
    ];

    return ChartCard(
      title: title,
      child: PieChartView(items: items, showPercentage: showPercentage),
    );
  }
}

/// ============================================================================
/// Vertical bar chart (single series, category on the x-axis).
/// ============================================================================
class SimpleVerticalBarChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final Color? primaryColor;

  const SimpleVerticalBarChart({
    super.key,
    required this.title,
    required this.data,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return ChartStates.empty(title);

    final entries = data.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return ChartStates.empty(title);

    final labels = entries.map((e) => e.key).toList();
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    final rawMax = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final axis = ChartTheme.niceAxis(rawMax.toDouble());
    final color = primaryColor ?? ChartTheme.colorAt(0);

    return ChartCard(
      title: title,
      height: 260,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: axis.maxY,
          gridData: _Cartesian.hGrid(axis.interval),
          borderData: _Cartesian.noBorder,
          titlesData: FlTitlesData(
            leftTitles: _Cartesian.leftValueTitles(axis.interval),
            bottomTitles: _Cartesian.bottomCategoryTitles(labels),
            topTitles: _Cartesian.hidden,
            rightTitles: _Cartesian.hidden,
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ChartTheme.tooltipBg,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${labels[group.x]}\n',
                ChartTheme.tooltipTextStyle,
                children: [
                  TextSpan(
                    text:
                        '${rod.toY.round()} · ${ChartTheme.percentOf(rod.toY.round(), total)}',
                    style: ChartTheme.tooltipTextStyle
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < entries.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: entries[i].value.toDouble(),
                    color: color,
                    width: 22,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(5)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// Horizontal bar chart — best for many categories or long labels (barangays).
/// Widget-based (fl_chart has no horizontal mode); always shows value + %.
/// ============================================================================
class SimpleBarChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final Color? primaryColor;
  final int maxValue;

  const SimpleBarChart({
    super.key,
    required this.title,
    required this.data,
    this.primaryColor,
    this.maxValue = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return ChartStates.empty(title);

    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return ChartStates.empty(title);

    final total = entries.fold<int>(0, (a, b) => a + b.value);
    final rawMax = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxVal = maxValue > 0 ? maxValue : rawMax;
    final color = primaryColor ?? ChartTheme.colorAt(0);

    return ChartCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final frac = maxVal > 0 ? e.value / maxVal : 0.0;
                        return Stack(
                          children: [
                            Container(
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.pageBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            Container(
                              height: 22,
                              width: (c.maxWidth * frac).clamp(2.0, c.maxWidth),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${e.value} · ${ChartTheme.percentOf(e.value, total)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// Histogram — contiguous vertical bars for a numeric distribution, with a stat
/// summary row (average / median / min / max) above it.
/// ============================================================================
class HistogramChart extends StatelessWidget {
  final String title;
  final Map<String, int> buckets;
  final double? average;
  final double? median;
  final double? minVal;
  final double? maxVal;

  const HistogramChart({
    super.key,
    required this.title,
    required this.buckets,
    this.average,
    this.median,
    this.minVal,
    this.maxVal,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return ChartStates.empty(title);

    final entries = buckets.entries.toList();
    final labels = entries.map((e) => e.key).toList();
    final rawMax = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final axis = ChartTheme.niceAxis(rawMax.toDouble());

    final stats = <({String label, double? value})>[
      (label: 'Average', value: average),
      (label: 'Median', value: median),
      (label: 'Min', value: minVal),
      (label: 'Max', value: maxVal),
    ].where((s) => s.value != null).toList();

    return ChartCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats.isNotEmpty) ...[
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final s in stats)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ChartTheme.compact(s.value!),
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                maxY: axis.maxY,
                gridData: _Cartesian.hGrid(axis.interval),
                borderData: _Cartesian.noBorder,
                titlesData: FlTitlesData(
                  leftTitles: _Cartesian.leftValueTitles(axis.interval),
                  bottomTitles: _Cartesian.bottomCategoryTitles(labels),
                  topTitles: _Cartesian.hidden,
                  rightTitles: _Cartesian.hidden,
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => ChartTheme.tooltipBg,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${labels[group.x]}\n${rod.toY.round()}',
                      ChartTheme.tooltipTextStyle,
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < entries.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: entries[i].value.toDouble(),
                          color: ChartTheme.colorAt(0),
                          width: 26,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// Line chart — trend over ordered categories (e.g. monthly submissions).
/// fl_chart keeps the points, the value axis and the category labels on a single
/// coordinate system, so data always lines up with its labels.
/// ============================================================================
class LineChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final String xAxisLabel;
  final String yAxisLabel;

  const LineChart({
    super.key,
    required this.title,
    required this.data,
    this.xAxisLabel = '',
    this.yAxisLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return ChartStates.empty(title);

    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final labels = entries.map((e) => e.key).toList();
    final rawMax = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final axis = ChartTheme.niceAxis(rawMax.toDouble());

    // Thin out x labels so ~6 show at most, evenly spaced.
    final labelStep = (labels.length / 6).ceil().clamp(1, labels.length);

    return ChartCard(
      title: title,
      height: 260,
      child: flc.LineChart(
        LineChartData(
          minY: 0,
          maxY: axis.maxY,
          minX: 0,
          maxX: (entries.length - 1).toDouble().clamp(0, double.infinity),
          gridData: _Cartesian.hGrid(axis.interval),
          borderData: _Cartesian.noBorder,
          titlesData: FlTitlesData(
            leftTitles: _Cartesian.leftValueTitles(axis.interval),
            topTitles: _Cartesian.hidden,
            rightTitles: _Cartesian.hidden,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  if (i % labelStep != 0 && i != labels.length - 1) {
                    return const SizedBox.shrink();
                  }
                  var text = labels[i];
                  if (text.length > 12) text = '${text.substring(0, 11)}…';
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    angle: -0.5,
                    child:
                        Text(text, style: ChartTheme.axisLabelStyle, maxLines: 1),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => ChartTheme.tooltipBg,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final label = (i >= 0 && i < labels.length) ? labels[i] : '';
                return LineTooltipItem(
                  '$label\n${s.y.round()}',
                  ChartTheme.tooltipTextStyle,
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < entries.length; i++)
                  FlSpot(i.toDouble(), entries[i].value.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.28,
              color: ChartTheme.colorAt(0),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeColor: ChartTheme.colorAt(0),
                  strokeWidth: 2,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: ChartTheme.colorAt(0).withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
