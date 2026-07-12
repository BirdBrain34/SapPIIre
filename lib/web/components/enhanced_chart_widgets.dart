import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

/// ============================================================================
/// Enhanced Pie Chart with dynamic color syncing from form card colors.
/// Each slice color is provided by the parent based on the card color picker.
/// ============================================================================
class ColorSyncPieChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  /// Map of form display name → hex color (e.g. '{"Intake Form": "#FF6B6B"}')
  final Map<String, String> formColors;
  final bool showPercentage;

  const ColorSyncPieChart({
    super.key,
    required this.title,
    required this.data,
    required this.formColors,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: AppColors.cardDecoration(),
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
      );
    }

    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList();

    // Build colors list: for each entry, look up from formColors map.
    // Fallback to the default palette if color not found.
    final List<Color> sliceColors = entries.map((entry) {
      final hex = formColors[entry.key];
      if (hex != null && hex.isNotEmpty) {
        return _parseHexColor(hex);
      }
      return _defaultColor(entries.indexOf(entry));
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(elevation: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.highlight.withValues(alpha:  0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total: $total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.highlight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final chartSize = min<double>(constraints.maxWidth * 0.45, 200);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: chartSize + 24,
                    height: chartSize + 24,
                    child: CustomPaint(
                      painter: _EnhancedPiePainter(entries, sliceColors, total),
                      size: const Size(200, 200),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entries.asMap().entries.map((e) {
                          final idx = e.key;
                          final entry = e.value;
                          final pct = (entry.value / total) * 100;
                          final color = sliceColors[idx % sliceColors.length];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha:  0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: color.withValues(alpha:  0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(alpha:  0.4),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  showPercentage
                                      ? '${entry.key} (${pct.toStringAsFixed(1)}%)'
                                      : '${entry.key}: ${entry.value}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w500,
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
            },
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String hexColor) {
    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return AppColors.highlight;
  }

  Color _defaultColor(int index) {
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
    return palette[index % palette.length];
  }
}

class _EnhancedPiePainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final List<Color> colors;
  final int total;

  _EnhancedPiePainter(this.entries, this.colors, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha:  0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius + 2, shadowPaint);

    double startAngle = -pi / 2;

    for (int i = 0; i < entries.length; i++) {
      final sweepAngle = (entries[i].value / total) * 2 * pi;

      // Slice fill with slight gloss effect
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.fill,
      );

      // Inner highlight gradient (gloss)
      final gradientRect = Rect.fromCircle(center: center, radius: radius * 0.6);
      canvas.drawArc(
        gradientRect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha:  0.2),
              Colors.transparent,
            ],
          ).createShader(gradientRect)
          ..style = PaintingStyle.fill,
      );

      startAngle += sweepAngle;
    }

    // No border drawn between slices (Issue 5 fix)
  }

  @override
  bool shouldRepaint(covariant _EnhancedPiePainter old) =>
      old.total != total || old.entries != entries || old.colors != colors;
}

/// ============================================================================
/// Interactive Horizontal Bar Chart with Drill-Down.
/// Shows total submissions per account. Clicking a bar reveals sub-chart
/// with form type breakdown for that account.
/// ============================================================================
class InteractiveBarChart extends StatefulWidget {
  final String title;
  final Map<String, int> data;
  /// Callback when user clicks an account bar. Returns the account label.
  /// If null, drill-down is disabled.
  final Future<Map<String, int>> Function(String account)? onDrillDown;
  final Color? primaryColor;

  const InteractiveBarChart({
    super.key,
    required this.title,
    required this.data,
    this.onDrillDown,
    this.primaryColor,
  });

  @override
  State<InteractiveBarChart> createState() => _InteractiveBarChartState();
}

class _InteractiveBarChartState extends State<InteractiveBarChart> {
  String? _drilledAccount;
  Map<String, int>? _drillDownData;
  bool _isLoadingDrillDown = false;

  Future<void> _handleBarTap(String account) async {
    if (widget.onDrillDown == null) return;

    // Toggle: if same account tapped again, go back
    if (_drilledAccount == account) {
      setState(() {
        _drilledAccount = null;
        _drillDownData = null;
      });
      return;
    }

    setState(() {
      _drilledAccount = account;
      _isLoadingDrillDown = true;
      _drillDownData = null;
    });

    try {
      final subData = await widget.onDrillDown!(account);
      if (mounted) {
        setState(() {
          _drillDownData = subData;
          _isLoadingDrillDown = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDrillDown = false;
          _drillDownData = {};
        });
      }
    }
  }

  void _resetDrillDown() {
    setState(() {
      _drilledAccount = null;
      _drillDownData = null;
      _isLoadingDrillDown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: AppColors.cardDecoration(elevation: 3),
        child: Column(
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 32),
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
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
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(elevation: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button when drilled
          _buildHeader(),
          const SizedBox(height: 20),

          if (_drilledAccount != null && _isLoadingDrillDown)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_drilledAccount != null && _drillDownData != null)
            _buildSubChart()
          else
            _buildMainChart(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            children: [
              if (_drilledAccount != null) ...[
                GestureDetector(
                  onTap: _resetDrillDown,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.highlight.withValues(alpha:  0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: AppColors.highlight,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _drilledAccount != null
                          ? '$_drilledAccount → Form Breakdown'
                          : widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_drilledAccount != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Tap a form type bar to drill up',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted.withValues(alpha:  0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_drilledAccount == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (widget.primaryColor ?? AppColors.highlight)
                  .withValues(alpha:  0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${widget.data.length} accounts',
              style: TextStyle(
                fontSize: 12,
                color: widget.primaryColor ?? AppColors.highlight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMainChart() {
    final maxVal = widget.data.values
        .reduce((a, b) => a > b ? a : b);
    final color = widget.primaryColor ?? AppColors.highlight;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: max(100.0, widget.data.length * 56.0 + 16),
        minHeight: 100,
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: widget.data.entries.map((entry) {
          final pct = maxVal > 0 ? entry.value / maxVal : 0.0;
          final isActive = _drilledAccount == entry.key;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _handleBarTap(entry.key),
              child: MouseRegion(
                cursor: widget.onDrillDown != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0, end: pct),
                  builder: (context, animatedPct, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                children: [
                                  if (widget.onDrillDown != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Icon(
                                        isActive
                                            ? Icons.expand_less
                                            : Icons.arrow_forward_ios,
                                        size: 10,
                                        color: AppColors.textMuted
                                            .withValues(alpha:  0.6),
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isActive
                                            ? AppColors.textDark
                                            : AppColors.textMuted,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha:  isActive ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.value.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: animatedPct,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    gradient: LinearGradient(
                                      colors: [
                                        color.withValues(alpha:  0.8),
                                        color,
                                      ],
                                    ),
                                    boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: color.withValues(alpha:  0.4),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubChart() {
    if (_drillDownData == null || _drillDownData!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 36, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text(
                'No detailed data available',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxVal = _drillDownData!.values
        .reduce((a, b) => a > b ? a : b);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: _drillDownData!.length * 56.0 + 16,
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: _drillDownData!.entries.map((entry) {
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withValues(alpha:  0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.successGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.successGreen.withValues(alpha:  0.8),
                                AppColors.successGreen,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// ============================================================================
/// Horizontal bar chart that shows submissions per form type for a given account
/// Used by the drill-down functionality in DashboardScreen.
/// ============================================================================
class SubmissionsByFormTypeChart extends StatelessWidget {
  final String account;
  final Map<String, int> data;

  const SubmissionsByFormTypeChart({
    super.key,
    required this.account,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Form types by $account',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted.withValues(alpha:  0.8),
            ),
          ),
        ),
        ...data.entries.map((entry) {
          final pct = maxVal > 0 ? entry.value / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                        fontSize: 12,
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.successGreen,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
