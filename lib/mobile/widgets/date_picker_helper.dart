import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class DatePickerHelper {
  /// Format a DateTime as YYYY-MM-DD string.
  static String formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Themed date-picker builder using app brand colors.
  static Widget Function(BuildContext, Widget?) get themedBuilder =>
      (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AppColors.primaryBlue,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );

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
      builder: themedBuilder,
    );

    if (pickedDate != null) {
      dateController.text = formatDate(pickedDate);

      if (ageController != null) {
        final age = DateTime.now().year - pickedDate.year;
        ageController.text = age.toString();
      }
    }
  }
}
