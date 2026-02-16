import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class SelectAllButton extends StatelessWidget {
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const SelectAllButton({
    super.key,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue, // Solid Blue Background
        borderRadius: BorderRadius.circular(30), // Rounded pill shape
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Select All",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.9,
            child: Checkbox(
              value: isSelected,
              onChanged: onChanged,
              activeColor: Colors.white,
              checkColor: AppColors.primaryBlue,
              side: const BorderSide(color: Colors.white, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}