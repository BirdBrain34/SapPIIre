import 'package:flutter/material.dart';
import 'package:sappiire/web/components/chart_theme.dart';

/// ============================================================================
/// Pie chart whose slice colours sync with the per-form colours chosen in the
/// form card colour pickers. Falls back to the shared categorical palette for
/// any form without an assigned colour. Rendered as a donut via [PieChartView].
/// ============================================================================
class ColorSyncPieChart extends StatelessWidget {
  final String title;
  final Map<String, int> data;

  /// Map of form display name → hex colour (e.g. `{"Intake Form": "#FF6B6B"}`).
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
    if (data.isEmpty) return ChartStates.empty(title);

    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return ChartStates.empty(title);

    final items = <({String label, Color color, int value})>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final synced = _parseHex(formColors[e.key]);
      items.add((
        label: e.key,
        color: synced ?? ChartTheme.colorAt(i),
        value: e.value,
      ));
    }

    return ChartCard(
      title: title,
      child: PieChartView(items: items, showPercentage: showPercentage),
    );
  }

  /// Parses `#RRGGBB` / `RRGGBB` / `#AARRGGBB` into a [Color]; null if invalid.
  static Color? _parseHex(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}
