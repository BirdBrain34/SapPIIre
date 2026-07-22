import 'package:flutter/material.dart';

/// A colored status badge chip for submission review status.
///
/// Displays:
///   🟡 Pending (yellow)
///   ✅ Approved (green)
///   ❌ Denied (red)
///   🔵 Scanned (blue)
///   ⚪ Completed (gray)
class StatusBadgeWidget extends StatelessWidget {
  final String status;
  final double fontSize;
  final bool compact;

  const StatusBadgeWidget({
    super.key,
    required this.status,
    this.fontSize = 11,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _configFor(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: config.color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 6 : 8,
            height: compact ? 6 : 8,
            decoration: BoxDecoration(
              color: config.color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            config.label,
            style: TextStyle(
              color: config.color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _configFor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return _StatusConfig(
          label: 'Pending',
          color: const Color(0xFFF59E0B), // amber
        );
      case 'approved':
        return _StatusConfig(
          label: 'Approved',
          color: const Color(0xFF10B981), // emerald
        );
      case 'denied':
        return _StatusConfig(
          label: 'Denied',
          color: const Color(0xFFEF4444), // red
        );
      case 'scanned':
        return _StatusConfig(
          label: 'Received',
          color: const Color(0xFF3B82F6), // blue
        );
      case 'completed':
        return _StatusConfig(
          label: 'Saved',
          color: const Color(0xFF6B7280), // gray
        );
      case 'active':
        return _StatusConfig(
          label: 'Active',
          color: const Color(0xFF10B981), // green
        );
      case 'closed':
        return _StatusConfig(
          label: 'Closed',
          color: const Color(0xFF9CA3AF), // light gray
        );
      default:
        return _StatusConfig(
          label: status,
          color: const Color(0xFF9CA3AF),
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final Color color;

  const _StatusConfig({required this.label, required this.color});
}