import 'package:flutter/material.dart';

/// A vertical timeline widget showing the status progression of a submission.
///
/// Steps are shown chronologically with a colored dot, connecting line,
/// label, timestamp, and optional description.
class ReviewTimelineWidget extends StatelessWidget {
  final List<TimelineStep> steps;

  const ReviewTimelineWidget({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length * 2 - 1, (index) {
        // Odd indices are connectors
        if (index.isOdd) {
          final stepIndex = index ~/ 2;
          final isActive = stepIndex < steps.length - 1 &&
              _isStepCompleted(steps[stepIndex]);
          return _buildConnector(isActive);
        }
        // Even indices are steps
        return _buildStepRow(steps[index ~/ 2]);
      }),
    );
  }

  bool _isStepCompleted(TimelineStep step) =>
      step.status != 'inactive' && step.status != 'upcoming';

  Widget _buildStepRow(TimelineStep step) {
    final isCompleted = _isStepCompleted(step);
    final isActive = step.status == 'active';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: isCompleted ? 14 : (isActive ? 12 : 10),
                  height: isCompleted ? 14 : (isActive ? 12 : 10),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? step.color
                        : isActive
                            ? step.color.withValues(alpha: 0.3)
                            : const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                    border: isActive && !isCompleted
                        ? Border.all(color: step.color, width: 2)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCompleted || isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isCompleted || isActive
                                ? const Color(0xFF1A1A2E)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                      if (step.timestamp != null)
                        Text(
                          step.timestamp!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                  if (step.description != null &&
                      step.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnector(bool isActive) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Container(
        width: 2,
        height: 24,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF10B981)
              : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }
}

/// A single step in the review timeline.
class TimelineStep {
  final String label;
  final String status; // 'completed', 'active', 'inactive', 'upcoming'
  final Color color;
  final String? timestamp;
  final String? description;

  const TimelineStep({
    required this.label,
    required this.status,
    this.color = const Color(0xFF10B981),
    this.timestamp,
    this.description,
  });
}