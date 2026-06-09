import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

/// Form card widget for the dashboard showing submission count and card color
class DashboardFormCard extends StatefulWidget {
  final String formName;
  final int submissionCount;
  final String cardColor;
  final bool isSelected;
  final VoidCallback onTap;
  final Future<void> Function(String color) onColorChanged;

  const DashboardFormCard({
    super.key,
    required this.formName,
    required this.submissionCount,
    required this.cardColor,
    required this.isSelected,
    required this.onTap,
    required this.onColorChanged,
  });

  @override
  State<DashboardFormCard> createState() => _DashboardFormCardState();
}

class _DashboardFormCardState extends State<DashboardFormCard> {
  late String _displayColor;
  bool _isShowingColorPicker = false;

  // 12 preset colors for quick selection
  static const _presetColors = [
    '#4C8BF5', // Default blue
    '#2EC4B6', // Green
    '#FF6B6B', // Red
    '#FFA500', // Orange
    '#FFD700', // Gold
    '#7C7FFF', // Indigo
    '#FF69B4', // Pink
    '#20C997', // Teal
    '#FF8C42', // Coral
    '#6366F1', // Purple
    '#0EA5E9', // Cyan
    '#F43F5E', // Rose
  ];

  @override
  void initState() {
    super.initState();
    _displayColor = widget.cardColor;
  }

  @override
  void didUpdateWidget(DashboardFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardColor != widget.cardColor) {
      _displayColor = widget.cardColor;
    }
  }

  Color _parseHexColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      return Color(int.parse('FF$hexColor', radix: 16));
    }
    return AppColors.highlight;
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Choose Card Color',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Preset colors
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetColors
                    .map(
                      (hexColor) => _buildColorSwatch(
                        hexColor,
                        onTap: () async {
                          setState(() => _displayColor = hexColor);
                          await widget.onColorChanged(hexColor);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              // Custom color option
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showCustomColorPicker();
                },
                icon: const Icon(Icons.palette),
                label: const Text('Custom Color'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pageBg,
                  foregroundColor: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomColorPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Custom Color',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _parseHexColor(_displayColor),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Hex Color (e.g., #FF6B6B)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: _displayColor,
                ),
                onSubmitted: (value) async {
                  if (value.isEmpty || !value.startsWith('#')) {
                    return;
                  }
                  setState(() => _displayColor = value);
                  await widget.onColorChanged(value);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorSwatch(
    String hexColor, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _parseHexColor(hexColor),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _displayColor == hexColor
                ? AppColors.textDark
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (_displayColor == hexColor)
              BoxShadow(
                color: _parseHexColor(hexColor).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: _displayColor == hexColor
            ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 24,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBgColor = _parseHexColor(_displayColor);
    final isLight = _isLightColor(cardBgColor);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        decoration: BoxDecoration(
          // Color now persists permanently — always visible, with opacity
          // when not selected and full opacity when selected
          color: widget.isSelected
              ? cardBgColor.withValues(alpha: 0.95)
              : cardBgColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? cardBgColor
                : cardBgColor.withValues(alpha: 0.4),
            width: widget.isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (widget.isSelected)
              BoxShadow(
                color: cardBgColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: cardBgColor.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Form name
                  Text(
                    widget.formName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: widget.isSelected
                          ? (isLight ? Colors.black87 : Colors.white)
                          : AppColors.textDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Submission count
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        widget.submissionCount.toString(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: widget.isSelected
                              ? (isLight ? Colors.black87 : Colors.white)
                              : AppColors.textDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'submissions',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isSelected
                              ? (isLight
                                  ? Colors.black54
                                  : Colors.white70)
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Color picker button (top-right)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  _showColorPicker();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? (isLight ? Colors.white : Colors.black26)
                        : AppColors.pageBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.transparent
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Icon(
                    Icons.palette,
                    size: 16,
                    color: widget.isSelected
                        ? (isLight ? Colors.black87 : Colors.white)
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isLightColor(Color color) {
    // Calculate luminance using modern API
    final luminance =
        (0.299 * (color.r * 255) + 0.587 * (color.g * 255) + 0.114 * (color.b * 255)) /
            255;
    return luminance > 0.5;
  }
}
