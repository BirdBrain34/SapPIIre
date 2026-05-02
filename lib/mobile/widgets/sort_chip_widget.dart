import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDesc;
  final VoidCallback onTap;

  const SortChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isDesc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryBlue.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? AppColors.primaryBlue.withOpacity(0.4) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? AppColors.primaryBlue : Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppColors.primaryBlue : Colors.grey.shade600)),
            if (isActive) ...[
              const SizedBox(width: 3),
              Icon(isDesc ? Icons.arrow_downward : Icons.arrow_upward, size: 11, color: AppColors.primaryBlue),
            ],
          ],
        ),
      ),
    );
  }
}
