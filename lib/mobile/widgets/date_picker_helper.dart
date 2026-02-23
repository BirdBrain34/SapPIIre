import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class DatePickerHelper {
  static Future<void> selectDate({
    required BuildContext context,
    required TextEditingController dateController,
    TextEditingController? ageController,
  }) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      dateController.text = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
      
      if (ageController != null) {
        final age = DateTime.now().year - pickedDate.year;
        ageController.text = age.toString();
      }
    }
  }
}
