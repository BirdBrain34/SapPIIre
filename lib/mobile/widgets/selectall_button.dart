import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class SelectAllButton extends StatelessWidget {
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const SelectAllButton({
    super.key,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => onChanged(!isSelected),
      backgroundColor: AppColors.primaryBlue,
      elevation: 4,
      mini: true,
      child: Icon(
        isSelected ? Icons.check : Icons.check_box_outline_blank,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}