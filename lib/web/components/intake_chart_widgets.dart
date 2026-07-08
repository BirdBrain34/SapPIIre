import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

/// ============================================================================
/// Helper utilities
/// ============================================================================

List<Color> _chartPalette(int count) {
  const palette = [
    Color(0xFF4C8BF5),
    Color(0xFF2EC4B6),
    Color(0xFFFF6B6B),
    Color(0xFFFFA500),
    Color(0xFF4ECDC4),
    Color(0xFF95E1D3),
    Color(0xFFF38181),
    Color(0xFFAA96DA),
    Color(0xFFFCBCD2),
    Color(0xFF9BE8D8),
  ];
  final result = <Color>[];
  for (int i = 0; i < count; i++) {
    result.add(palette[i % palette.length]);
  }
  return result;
}

/// Shared tooltip text builder for chart hover tooltips.
/// [delta] is optional and shown only for line/trend charts.
String buildChartTooltipText(String label, int count, int total, {int? delta}) {
  final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
  final deltaStr = delta != null
      ? '${delta >= 0 ? '+' : ''}$delta vs last period'
      : '';
  return deltaStr.isNotEmpty
      ? '$label\n$count ($pct%)\n$deltaStr'
      : '$label\n$count ($pct%)';
}

/// Card wrapper with consistent spacing and card styling.
Widget _cardWrap({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  int elevation = 1,
}) =>
    Container(
      width: double.infinity,
      padding: padding,
      decoration: AppColors.cardDecoration(elevation: elevation),
      child: child,
    );

Widget _cardHeader(String title, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );

Widget _emptyState(String title) => _cardWrap(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 32),
          Icon(Icons.data_exploration, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No data available',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );

/// ============================================================================
/// Metric card
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
              color: Colors.black.withValues(alpha:  0.06),
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
                    color: color.withValues(alpha:  0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (subtitle != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:  0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: subtitleColor ?? color),
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
                        fontWeight: FontWeight.w500),
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

/// ============================================================================
/// True custom painted pie chart with hover tooltip showing percentage
/// ============================================================================
class SimplePieChart extends StatefulWidget {
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
  State<SimplePieChart> createState() => _SimplePieChartState();
}

class _SimplePieChartState extends State<SimplePieChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return _emptyState(widget.title);
    final total = widget.data.values.fold<int>(0, (a, b) => a + b);
    final colors = _chartPalette(widget.data.length);
    final entries = widget.data.entries.toList();

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(
          widget.title,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.highlight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Total: $total',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.highlight,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final chartSize = min<double>(constraints.maxWidth * 0.45, 180);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: chartSize + 20,
                height: chartSize + 20,
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _PiePainter(entries, colors, total),
                      size: const Size(180, 180),
                    ),
                    // Invisible hover zones over pie slices
                    MouseRegion(
                      onHover: (event) {
                        final center = const Offset(90, 90);
                        final dx = event.localPosition.dx - center.dx;
                        final dy = event.localPosition.dy - center.dy;
                        final dist = sqrt(dx * dx + dy * dy);
                        if (dist > 80) {
                          setState(() => _hoveredIndex = null);
                          return;
                        }
                        var angle = atan2(dy, dx) + pi / 2;
                        if (angle < 0) angle += 2 * pi;
                        var cumulative = 0.0;
                        for (int i = 0; i < entries.length; i++) {
                          final sweep = (entries[i].value / total) * 2 * pi;
                          cumulative += sweep;
                          if (angle <= cumulative) {
                            setState(() => _hoveredIndex = i);
                            return;
                          }
                        }
                        setState(() => _hoveredIndex = null);
                      },
                      onExit: (_) => setState(() => _hoveredIndex = null),
                      child: SizedBox(
                        width: chartSize + 20,
                        height: chartSize + 20,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    // Tooltip overlay
                    if (_hoveredIndex != null && _hoveredIndex! < entries.length)
                      Positioned(
                        left: 10,
                        top: 4,
                        child: _TooltipCard(
                          text: buildChartTooltipText(
                            entries[_hoveredIndex!].key,
                            entries[_hoveredIndex!].value,
                            total,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Vertical legend
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.asMap().entries.map((e) {
                      final idx = e.key;
                      final entry = e.value;
                      final pct = (entry.value / total) * 100;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colors[idx],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.showPercentage
                                    ? '${entry.key} (${pct.toStringAsFixed(1)}%)'
                                    : '${entry.key}: ${entry.value}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          );
        }),
      ]),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final List<Color> colors;
  final int total;
  _PiePainter(this.entries, this.colors, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    double startAngle = -pi / 2;

    for (int i = 0; i < entries.length; i++) {
      final sweepAngle = (entries[i].value / total) * 2 * pi;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.fill,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.total != total || old.entries != entries;
}

/// ============================================================================
/// Donut chart (CustomPaint with hole)
/// ============================================================================
class DonutChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final bool showPercentage;

  const DonutChart({
    super.key,
    required this.title,
    required this.data,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _emptyState(title);
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final colors = _chartPalette(data.length);
    final entries = data.entries.toList();

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(
          title,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.highlight.withValues(alpha:  0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Total: $total',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.highlight,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final chartSize = min<double>(constraints.maxWidth * 0.45, 180);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: chartSize + 20,
                height: chartSize + 20,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    painter: _DonutPainter(entries, colors, total),
                    size: const Size(200, 200),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(total.toString(),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                      Text('Total',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.asMap().entries.map((e) {
                      final idx = e.key;
                      final entry = e.value;
                      final pct = (entry.value / total) * 100;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colors[idx],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                showPercentage
                                    ? '${entry.key} (${pct.toStringAsFixed(1)}%)'
                                    : '${entry.key}: ${entry.value}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          );
        }),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final List<Color> colors;
  final int total;
  _DonutPainter(this.entries, this.colors, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = min(size.width, size.height) / 2 - 4;
    final innerRadius = outerRadius * 0.55;
    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    double startAngle = -pi / 2;

    for (int i = 0; i < entries.length; i++) {
      final sweepAngle = (entries[i].value / total) * 2 * pi;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.fill,
      );
      startAngle += sweepAngle;
    }

    canvas.drawCircle(
        center,
        innerRadius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.total != total || old.entries != entries;
}

/// ============================================================================
/// Simple vertical bar chart (column chart) with hover tooltips
/// ============================================================================
class SimpleVerticalBarChart extends StatefulWidget {
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
  State<SimpleVerticalBarChart> createState() => _SimpleVerticalBarChartState();
}

class _SimpleVerticalBarChartState extends State<SimpleVerticalBarChart> {
  int? _hoveredIndex;
  final GlobalKey _chartKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return _emptyState(widget.title);

    final total = widget.data.values.fold<int>(0, (a, b) => a + b);
    final maxVal = widget.data.values.reduce((a, b) => a > b ? a : b).toDouble();
    final color = widget.primaryColor ?? AppColors.highlight;
    final colors = _chartPalette(widget.data.length);
    final entries = widget.data.entries.toList();

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(
          widget.title,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${widget.data.length} categories',
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        SizedBox(
          height: 220,
          child: LayoutBuilder(builder: (context, constraints) {
            final barCount = entries.length;
            final drawW = constraints.maxWidth - 48;
            final barWidth = (drawW / barCount) * 0.65;
            final gap = (drawW / barCount) * 0.35;
            final hPad = 24.0;

            return Stack(
              key: _chartKey,
              children: [
                CustomPaint(
                  painter: _VerticalBarPainter(entries, maxVal, colors,
                      hoveredIndex: _hoveredIndex),
                  size: Size(constraints.maxWidth, 220),
                ),
                // Invisible hover zones over each bar
                MouseRegion(
                  onHover: (event) {
                    final localX = event.localPosition.dx - hPad;
                    final index = (localX / (barWidth + gap)).floor();
                    if (index >= 0 && index < barCount) {
                      setState(() => _hoveredIndex = index);
                    } else {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 220,
                    child: const SizedBox.expand(),
                  ),
                ),
                // Tooltip overlay
                if (_hoveredIndex != null && _hoveredIndex! < entries.length)
                  Positioned(
                    left: hPad +
                        _hoveredIndex! * (barWidth + gap) +
                        gap / 2 +
                        barWidth / 2 -
                        60,
                    top: 4,
                    child: _TooltipCard(
                      text: buildChartTooltipText(
                        entries[_hoveredIndex!].key,
                        entries[_hoveredIndex!].value,
                        total,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
        // Vertical legend for bar chart
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.map((e) {
              final idx = e.key;
              final entry = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[idx],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${entry.key}: ${entry.value}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

/// Small tooltip card shown on chart hover.
class _TooltipCard extends StatelessWidget {
  final String text;
  const _TooltipCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.textDark,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _VerticalBarPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final double maxVal;
  final List<Color> colors;
  final int? hoveredIndex;
  _VerticalBarPainter(this.entries, this.maxVal, this.colors, {this.hoveredIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty || maxVal <= 0) return;
    final hPad = 24.0;
    final vPad = 16.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - vPad * 2 - 20;
    final barCount = entries.length;
    if (barCount == 0) return;
    final barWidth = (drawW / barCount) * 0.65;
    final gap = (drawW / barCount) * 0.35;

    final baselineY = vPad + drawH;
    final baselinePaint = Paint()
      ..color = Colors.grey.withValues(alpha:  0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(hPad, baselineY), Offset(hPad + drawW, baselineY), baselinePaint);

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha:  0.08)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 4; i++) {
      final y = vPad + (drawH / 4) * i;
      canvas.drawLine(Offset(hPad, y), Offset(hPad + drawW, y), gridPaint);
    }

    for (int i = 0; i < barCount; i++) {
      final entry = entries[i];
      final barH = (entry.value / maxVal) * drawH;
      final x = hPad + i * (barWidth + gap) + gap / 2;
      final y = baselineY - barH;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, max(2.0, barH)),
        const Radius.circular(4),
      );
      final color = colors[i % colors.length];
      canvas.drawRRect(rect, Paint()
        ..color = color
        ..style = PaintingStyle.fill);

      // Value label above bar
      final valueText = entry.value.toString();
      final textPainter = TextPainter(
        text: TextSpan(
          text: valueText,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWidth + 8);
      final labelX = (x + barWidth / 2) - textPainter.width / 2;
      final labelY = y - textPainter.height - 2;
      textPainter.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalBarPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

/// ============================================================================
/// Simple horizontal bar chart (categorical list style)
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
    if (data.isEmpty) return _emptyState(title);

    final maxVal = maxValue > 0 ? maxValue : data.values.reduce((a, b) => a > b ? a : b);
    final color = primaryColor ?? AppColors.highlight;

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(
          title,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha:  0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${data.length} categories',
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: data.length * 48.0 + 16),
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: data.entries.map((entry) {
              final pct = maxVal > 0 ? entry.value / maxVal : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

/// ============================================================================
/// Histogram chart for numeric fields (Issue 7.2)
/// Buckets raw values into ranges and shows a horizontal bar per bucket
/// with stat summary cards above.
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
    if (buckets.isEmpty) return _emptyState(title);

    final maxBucketCount = buckets.values.reduce((a, b) => a > b ? a : b);

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(title),
        // Stat summary row
        if (average != null || minVal != null || maxVal != null || median != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                if (average != null)
                  _statPill('Avg', average!.toStringAsFixed(1), AppColors.highlight),
                if (median != null)
                  _statPill('Med', median!.toStringAsFixed(1), AppColors.successGreen),
                if (minVal != null)
                  _statPill('Min', minVal!.toStringAsFixed(0), AppColors.textMuted),
                if (maxVal != null)
                  _statPill('Max', maxVal!.toStringAsFixed(0), AppColors.warningAmber),
              ],
            ),
          ),
        // Bucket bars
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: max(buckets.length * 44.0 + 8, 80.0),
          ),
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: buckets.entries.map((entry) {
              final pct = maxBucketCount > 0 ? entry.value / maxBucketCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// Simple data table
/// ============================================================================
class SimpleDataTable extends StatelessWidget {
  final String title;
  final Map<String, int> data;

  const SimpleDataTable({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _emptyState(title);

    final rows = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(
          title,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.highlight.withValues(alpha:  0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${rows.length} rows',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.highlight,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStatePropertyAll(AppColors.highlight.withValues(alpha:  0.08)),
              columnSpacing: 32,
              columns: const [
                DataColumn(label: Text('Label')),
                DataColumn(label: Text('Count')),
              ],
              rows: rows
                  .map((entry) => DataRow(cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.6),
                            child: Text(entry.key,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(Text(entry.value.toString())),
                      ]))
                  .toList(),
            ),
          );
        }),
      ]),
    );
  }
}

/// ============================================================================
/// Line chart (CustomPaint) with hover tooltips showing delta
/// ============================================================================
class LineChart extends StatefulWidget {
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
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return _emptyState(widget.title);

    final total = widget.data.values.fold<int>(0, (a, b) => a + b);
    final maxVal = widget.data.values.reduce((a, b) => a > b ? a : b).toDouble();
    final sortedEntries = widget.data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(widget.title),
        SizedBox(
          height: 220,
          child: LayoutBuilder(builder: (context, constraints) {
            final barCount = sortedEntries.length;
            final drawW = constraints.maxWidth - 32;
            final hPad = 16.0;
            final zoneWidth = barCount > 1 ? drawW / (barCount - 1) : drawW;

            return Stack(
              children: [
                CustomPaint(
                  painter: _LineChartPainter(sortedEntries, maxVal),
                  size: Size(constraints.maxWidth, 220),
                ),
                // Invisible hover zones over each data point
                MouseRegion(
                  onHover: (event) {
                    final localX = event.localPosition.dx - hPad;
                    final index = barCount > 1
                        ? (localX / zoneWidth).round().clamp(0, barCount - 1)
                        : 0;
                    setState(() => _hoveredIndex = index);
                  },
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 220,
                    child: const SizedBox.expand(),
                  ),
                ),
                // Tooltip overlay
                if (_hoveredIndex != null && _hoveredIndex! < sortedEntries.length)
                  Positioned(
                    left: hPad +
                        (_hoveredIndex! / max(1, barCount - 1)) * drawW -
                        60,
                    top: 4,
                    child: _TooltipCard(
                      text: buildChartTooltipText(
                        sortedEntries[_hoveredIndex!].key,
                        sortedEntries[_hoveredIndex!].value,
                        total,
                        delta: _hoveredIndex! > 0
                            ? sortedEntries[_hoveredIndex!].value -
                                sortedEntries[_hoveredIndex! - 1].value
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sortedEntries.asMap().entries.map((e) {
              final show = e.key % max<int>(1, sortedEntries.length ~/ 6) == 0 ||
                  e.key == sortedEntries.length - 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  show ? e.value.key : '',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final double maxVal;
  _LineChartPainter(this.entries, this.maxVal);

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;
    final hPad = 16.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - 20;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha:  0.15)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = 10 + (drawH / 4) * i;
      canvas.drawLine(Offset(hPad, y), Offset(hPad + drawW, y), gridPaint);
    }

    final pts = <Offset>[];
    for (int i = 0; i < entries.length; i++) {
      final x = hPad + (i / (entries.length - 1)) * drawW;
      final y = 10 + drawH - (entries[i].value / maxVal) * drawH;
      pts.add(Offset(x, y));
    }

    if (pts.length >= 2) {
      final area = Paint()
        ..color = AppColors.highlight.withValues(alpha:  0.12)
        ..style = PaintingStyle.fill;
      final path = Path()..moveTo(pts.first.dx, 10 + drawH);
      for (final p in pts) {
        path.lineTo(p.dx, p.dy);
      }
      path.lineTo(pts.last.dx, 10 + drawH);
      path.close();
      canvas.drawPath(path, area);
    }

    final line = Paint()
      ..color = AppColors.highlight
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(linePath, line);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = AppColors.highlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in pts) {
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

/// ============================================================================
/// Area chart (filled line chart)
/// ============================================================================
class AreaChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;

  const AreaChart({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _emptyState(title);

    final maxVal = data.values.reduce((a, b) => a > b ? a : b).toDouble();
    final entries = data.entries.toList();

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(title),
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _AreaChartPainter(entries, maxVal),
            size: const Size(double.infinity, 220),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: entries.asMap().entries.map((e) {
              final show = e.key % max<int>(1, entries.length ~/ 6) == 0 ||
                  e.key == entries.length - 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  show ? e.value.key : '',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final double maxVal;
  _AreaChartPainter(this.entries, this.maxVal);

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;
    final hPad = 16.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - 20;

    final pts = <Offset>[];
    for (int i = 0; i < entries.length; i++) {
      final x = hPad + (i / (entries.length - 1)) * drawW;
      final y = 10 + drawH - (entries[i].value / maxVal) * drawH;
      pts.add(Offset(x, y));
    }

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.highlight.withValues(alpha:  0.35),
          AppColors.highlight.withValues(alpha:  0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path()..moveTo(hPad, 10 + drawH);
    for (final p in pts) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(hPad + drawW, 10 + drawH);
    path.close();
    canvas.drawPath(path, fill);

    final line = Paint()
      ..color = AppColors.highlight
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(linePath, line);

    for (final p in pts) {
      canvas.drawCircle(
          p, 3, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(
          p,
          3,
          Paint()
            ..color = AppColors.highlight
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

/// ============================================================================
/// Stacked bar chart
/// ============================================================================
class StackedBarChart extends StatelessWidget {
  final String title;
  final Map<String, Map<String, int>> data;

  const StackedBarChart({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _emptyState(title);

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(title),
        ...data.entries.map((group) {
          final total =
              group.value.values.fold<int>(0, (a, b) => a + b);
          if (total <= 0) return const SizedBox.shrink();
          final colors = _chartPalette(group.value.length);
          final items = group.value.entries.toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.key,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: double.infinity,
                    height: 28,
                    child: Row(
                      children: items.map((item) {
                        final pct = item.value / total;
                        final color =
                            colors[items.indexOf(item) % colors.length];
                        return Expanded(
                          flex: (pct * 1000).round().clamp(1, 1000),
                          child: Container(
                            color: color,
                            alignment: Alignment.center,
                            child: pct > 0.08
                                ? Text(
                                    '${(pct * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ]),
    );
  }
}

/// ============================================================================
/// Funnel chart
/// ============================================================================
class FunnelChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;

  const FunnelChart({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _emptyState(title);

    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.first.value.toDouble();
    final colors = _chartPalette(sorted.length);

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(title),
        ...sorted.asMap().entries.map((e) {
          final idx = e.key;
          final entry = e.value;
          final pct = (entry.value / maxVal) * 100;
          final color = colors[idx % colors.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(entry.key,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.value} (${pct.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:  0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: pct / 100,
                      child: Container(color: color),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ]),
    );
  }
}