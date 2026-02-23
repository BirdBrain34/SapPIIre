import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

// Reusable text field widget for Family Composition
// Supports edit mode where field is read-only until user enables editing
class EditableTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isEditing;
  final bool readOnly;
  final TextInputType? keyboardType;

  const EditableTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.isEditing,
    this.readOnly = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        readOnly: readOnly || !isEditing,
        keyboardType: keyboardType,
        style: TextStyle(
          color: isEditing ? Colors.black : Colors.black54,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: isEditing ? Colors.black26 : Colors.transparent,
            ),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryBlue),
          ),
          disabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.transparent),
          ),
        ),
      ),
    );
  }
}
