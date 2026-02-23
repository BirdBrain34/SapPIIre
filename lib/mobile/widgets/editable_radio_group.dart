import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

// Reusable radio button group widget
// Displays multiple radio options in a horizontal wrap layout
// Only allows selection when isEditing is true
class EditableRadioGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? groupValue;
  final bool isEditing;
  final Function(String?) onChanged;

  const EditableRadioGroup({
    super.key,
    required this.label,
    required this.options,
    required this.groupValue,
    required this.isEditing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isEditing ? Colors.black54 : Colors.black38,
              fontSize: 12,
            ),
          ),
          Wrap(
            spacing: 8,
            children: options.map((option) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<String>(
                  value: option,
                  groupValue: groupValue,
                  onChanged: isEditing ? onChanged : null,
                  activeColor: AppColors.primaryBlue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(
                  option,
                  style: TextStyle(
                    fontSize: 11,
                    color: isEditing ? Colors.black : Colors.black54,
                  ),
                ),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }
}
