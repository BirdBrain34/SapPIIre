import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sappiire/constants/app_colors.dart';

/// Simple bar chart widget for displaying key-value data horizontally
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
    if (data.isEmpty) {
      return _buildEmptyState();
    }

    final max = maxValue > 0 ? maxValue : _calculateMaxValue(data);
    final entries = data.entries.toList();
    final barColor = primaryColor ?? AppColors.highlight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${data.length} categories',
                  style: TextStyle(
                    fontSize: 12,
                    color: barColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (max * 1.15).toDouble(),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= entries.length) return const SizedBox();
                        final label = entries[index].key;
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        );
                      },
                      reservedSize: 60,
                    ),
                  ),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(entries.length, (i) {
                  final val = entries[i].value.toDouble();
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: val,
                      color: barColor,
                      width: 18,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: [],
                    ),
                  ]);
                }),
                
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Value labels on top of bars
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: entries.map((e) {
              return Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12));
            }).toList(),
          ),
        ],
      ),
    );
  }

  

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.data_exploration,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  'No data available',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  int _calculateMaxValue(Map<String, int> data) {
    return data.values.isEmpty
        ? 1
        : data.values.reduce((a, b) => a > b ? a : b);
  }
}

/// Simple pie-like distribution widget showing proportions
class SimpleDistributionPie extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final bool showPercentage;

  const SimpleDistributionPie({
    super.key,
    required this.title,
    required this.data,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _buildEmptyState();
    }

    final total = data.values.fold<int>(0, (sum, val) => sum + val);
    final colors = _generateColors(data.length);
    final entries = data.entries.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Total: $total',
                  style: TextStyle(fontSize: 12, color: AppColors.highlight, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sections: List.generate(entries.length, (i) {
                  final e = entries[i];
                  final value = e.value.toDouble();
                  final percent = (value / total) * 100;
                  return PieChartSectionData(
                    value: value,
                    color: colors[i],
                    title: showPercentage ? '${percent.toStringAsFixed(0)}%' : '',
                    radius: 70,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  );
                }),
                sectionsSpace: 2,
                centerSpaceRadius: 36,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(entries.length, (i) {
              final e = entries[i];
              final percent = (e.value / total) * 100;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, color: colors[i]),
                  const SizedBox(width: 8),
                  Text('${e.key}: ${e.value} (${percent.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.data_exploration,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  'No data available',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  List<Color> _generateColors(int count) {
    final colors = [
      AppColors.highlight,
      AppColors.successGreen,
      const Color(0xFFFF6B6B),
      const Color(0xFFFFA500),
      const Color(0xFF4ECDC4),
      const Color(0xFF95E1D3),
      const Color(0xFFF38181),
      const Color(0xFFAA96DA),
      const Color(0xFFFCBCD2),
      const Color(0xFF9BE8D8),
    ];

    while (colors.length < count) {
      colors.addAll(colors);
    }

    return colors.take(count).toList();
  }

}

/// Counter card for displaying a single metric
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
        padding: const EdgeInsets.all(24),
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
            // Icon and subtitle row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                if (subtitle != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
            const SizedBox(height: 16),
            // Label
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: labelColor ?? AppColors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            // Value
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 40,
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

    if (expand) {
      return Expanded(child: card);
    }
    return card;
  }
}

/// Horizontal bar chart optimized for long labels
class SimpleHorizontalBarChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  final Color? primaryColor;

  const SimpleHorizontalBarChart({
    super.key,
    required this.title,
    required this.data,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
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
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
            ),
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(Icons.data_exploration, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No data available', style: TextStyle(fontSize: 14, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    }
    final entries = data.entries.toList();
    final max = entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    final color = primaryColor ?? AppColors.highlight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
          const SizedBox(height: 8),
          Column(
            children: List.generate(entries.length, (i) {
              final e = entries[i];
              final ratio = max > 0 ? e.value / max : 0.0;
              final bgColor = i.isEven ? Colors.white : Colors.grey.shade50;
              return Container(
                color: bgColor,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 180,
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(height: 18, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6))),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(width: 64, child: Text(e.value.toString(), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Simple paginated data table
class SimpleDataTable extends StatefulWidget {
  final String title;
  final Map<String, int> data;

  const SimpleDataTable({super.key, required this.title, required this.data});

  @override
  State<SimpleDataTable> createState() => _SimpleDataTableState();
}

class _SimpleDataTableState extends State<SimpleDataTable> {
  int _page = 0;
  static const int _perPage = 10;

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    final pages = (entries.length / _perPage).ceil();

    final start = _page * _perPage;
    final pageEntries = entries.skip(start).take(_perPage).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FixedColumnWidth(48),
              1: FlexColumnWidth(3),
              2: FixedColumnWidth(80),
              3: FixedColumnWidth(120),
            },
            border: TableBorder.symmetric(inside: BorderSide(color: AppColors.cardBorder)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: const [
                  Padding(padding: EdgeInsets.all(8), child: Text('Rank', style: TextStyle(fontWeight: FontWeight.w700))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Category', style: TextStyle(fontWeight: FontWeight.w700))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Count', style: TextStyle(fontWeight: FontWeight.w700))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Percentage', style: TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
              for (var i = 0; i < pageEntries.length; i++)
                TableRow(
                  decoration: BoxDecoration(color: i.isEven ? Colors.white : Colors.grey.shade50),
                  children: [
                    Padding(padding: const EdgeInsets.all(8), child: Text((start + i + 1).toString())),
                    Padding(padding: const EdgeInsets.all(8), child: Text(pageEntries[i].key)),
                    Padding(padding: const EdgeInsets.all(8), child: Text(pageEntries[i].value.toString())),
                    Padding(padding: const EdgeInsets.all(8), child: Text('${(pageEntries[i].value / (total == 0 ? 1 : total) * 100).toStringAsFixed(1)}%')),
                  ],
                ),
              // total row
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: [
                  const Padding(padding: EdgeInsets.all(8), child: Text('')),
                  const Padding(padding: EdgeInsets.all(8), child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
                  Padding(padding: const EdgeInsets.all(8), child: Text(total.toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
                  const Padding(padding: EdgeInsets.all(8), child: Text('100%')),
                ],
              ),
            ],
          ),
          if (pages > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  child: const Text('Prev'),
                ),
                const SizedBox(width: 8),
                Text('Page ${_page + 1} of $pages', style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _page >= pages - 1 ? null : () => setState(() => _page++),
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
