import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sappiire/constants/app_colors.dart';

class InfoInputField extends StatelessWidget {
  final String label;
  final TextEditingController? controller; // ADDED
  final List<List<dynamic>>? icon;
  final bool isChecked;
  final Function(bool?) onCheckboxChanged;
  final Function(String) onTextChanged;

  const InfoInputField({
    super.key,
    required this.label,
    this.controller, // ADDED
    this.icon,
    required this.isChecked,
    required this.onCheckboxChanged,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white, 
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: isChecked,
                  onChanged: onCheckboxChanged,
                  activeColor: AppColors.buttonPurple,
                  side: const BorderSide(color: Colors.white70, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller, // UPDATED: Linked the controller here
            onChanged: onTextChanged,
            style: const TextStyle(color: Colors.white, fontSize: 16), 
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: icon != null
                  ? Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: HugeIcon(icon: icon!, color: Colors.white70, size: 18),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white54, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}