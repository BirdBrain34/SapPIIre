import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class InfoInputField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final IconData? icon; // Changed to IconData for easier usage
  final bool isChecked;
  final Function(bool?) onCheckboxChanged;
  final Function(String) onTextChanged;

  const InfoInputField({
    super.key,
    required this.label,
    this.controller,
    this.icon,
    required this.isChecked,
    required this.onCheckboxChanged,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 🔹 FIX 1: Wrap label in Expanded so long text doesn't cause overflow
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black87, // Changed from white
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: isChecked,
                  onChanged: onCheckboxChanged,
                  activeColor: AppColors.primaryBlue,
                  // 🔹 FIX 2: Dark border for the checkbox
                  side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            onChanged: onTextChanged,
            // 🔹 FIX 3: Dark text color for typing
            style: const TextStyle(color: Colors.black, fontSize: 15), 
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              // 🔹 FIX 4: Darker borders for visibility
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.3), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}