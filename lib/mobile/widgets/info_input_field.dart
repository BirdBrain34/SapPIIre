import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
class InfoInputField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final IconData? icon; 
  final bool isChecked;
  final Function(bool?) onCheckboxChanged;
  final Function(String) onTextChanged;
  final bool readOnly;       
  final VoidCallback? onTap; // 1. Declared here

  const InfoInputField({
    super.key,
    required this.label,
    this.controller,
    this.icon,
    required this.isChecked,
    required this.onCheckboxChanged,
    required this.onTextChanged,
    this.readOnly = false,
    this.onTap, // 2. ADD THIS LINE to initialize it
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
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black87,
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
            readOnly: readOnly, // 3. Use the property here
            onTap: onTap,       // 4. Use the property here
            style: const TextStyle(color: Colors.black, fontSize: 15), 
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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