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

Widget _cardWrap({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(24),
}) =>
    Container(
      width: double.infinity,
      padding: padding,
      decoration: AppColors.cardDecoration(),
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
          if (trailing != null) trailing,
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
/// True custom painted pie chart
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
                child: CustomPaint(
                  painter: _PiePainter(entries, colors, total),
                  size: const Size(180, 180),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entries.asMap().entries.map((e) {
                      final idx = e.key;
                      final entry = e.value;
                      final pct = (entry.value / total) * 100;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
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
                            Text(
                              showPercentage
                                  ? '${entry.key} (${pct.toStringAsFixed(1)}%)'
                                  : '${entry.key}: ${entry.value}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
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

    // Draw border
    startAngle = -pi / 2;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < entries.length; i++) {
      final sweepAngle = (entries[i].value / total) * 2 * pi;
      canvas.drawArc(rect, startAngle, sweepAngle, true, borderPaint);
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
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entries.asMap().entries.map((e) {
                      final idx = e.key;
                      final entry = e.value;
                      final pct = (entry.value / total) * 100;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
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
                            Text(
                              showPercentage
                                  ? '${entry.key} (${pct.toStringAsFixed(1)}%)'
                                  : '${entry.key}: ${entry.value}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
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

    // Draw filled arcs
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

    // Punch hole
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
/// Simple horizontal bar chart
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
/// Line chart (CustomPaint)
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
    if (data.isEmpty) return _emptyState(title);

    final maxVal = data.values.reduce((a, b) => a > b ? a : b).toDouble();
    final entries = data.entries.toList();

    return _cardWrap(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHeader(title),
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _LineChartPainter(entries, maxVal),
            size: const Size(double.infinity, 220),
          ),
        ),
        const SizedBox(height: 12),
        // X-axis labels
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

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha:  0.15)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = 10 + (drawH / 4) * i;
      canvas.drawLine(Offset(hPad, y), Offset(hPad + drawW, y), gridPaint);
    }

    // Data points
    final pts = <Offset>[];
    for (int i = 0; i < entries.length; i++) {
      final x = hPad + (i / (entries.length - 1)) * drawW;
      final y = 10 + drawH - (entries[i].value / maxVal) * drawH;
      pts.add(Offset(x, y));
    }

    // Area fill
    if (pts.length >= 2) {
      final area = Paint()
        ..color = AppColors.highlight.withValues(alpha:  0.12)
        ..style = PaintingStyle.fill;
      final path = Path()..moveTo(pts.first.dx, 10 + drawH);
      for (final p in pts) path.lineTo(p.dx, p.dy);
      path.lineTo(pts.last.dx, 10 + drawH);
      path.close();
      canvas.drawPath(path, area);
    }

    // Line
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

    // Points
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
        // X-axis labels
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

    // Area fill
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
    for (final p in pts) path.lineTo(p.dx, p.dy);
    path.lineTo(hPad + drawW, 10 + drawH);
    path.close();
    canvas.drawPath(path, fill);

    // Line
    final line = Paint()
      ..color = AppColors.highlight
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) linePath.lineTo(pts[i].dx, pts[i].dy);
    canvas.drawPath(linePath, line);

    // Points
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
