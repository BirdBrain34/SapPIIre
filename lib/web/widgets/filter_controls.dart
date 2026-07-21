import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';

/// Shared filter-bar chrome for web admin screens.
///
/// Extracted from `audit_logs_screen.dart` so the applicants filter bar looks
/// and behaves identically rather than growing a second idiom. Appearance is
/// unchanged from the original.

/// Dropdown styled to sit inside a filter bar.
class WebDropdownFilter extends StatelessWidget {
  const WebDropdownFilter({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final List<String> items;
  final Map<String, String> labels;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          isDense: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labels[item] ?? item,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Outlined date-picker trigger. Highlights once a date is set.
class WebDateFilterButton extends StatelessWidget {
  const WebDateFilterButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.isSet,
  });

  final String label;
  final VoidCallback onTap;
  final bool isSet;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        Icons.calendar_today,
        size: 14,
        color: isSet ? AppColors.highlight : AppColors.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSet ? AppColors.highlight : AppColors.textMuted,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isSet ? AppColors.highlight : AppColors.cardBorder,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Search field styled to match the filter bar.
///
/// [onChanged] fires on every keystroke — debounce at the call site. The
/// widget deliberately does not rebuild its parent on input; the controller
/// owns the text.
class WebSearchField extends StatelessWidget {
  const WebSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        prefixIcon: const Icon(
          Icons.search,
          size: 18,
          color: AppColors.textMuted,
        ),
        filled: true,
        fillColor: AppColors.pageBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

/// Amber strip warning that a result set is incomplete.
///
/// Server-side search scans a bounded number of rows. When it hits that
/// ceiling the results are partial, and saying so is mandatory — silently
/// hiding an applicant from a PII lookup tool is a correctness failure, not a
/// performance detail.
class WebDegradedResultsBanner extends StatelessWidget {
  const WebDegradedResultsBanner({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0A63A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFB07514),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ??
                  'Showing partial results — narrow your search with filters.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A4F0B)),
            ),
          ),
        ],
      ),
    );
  }
}
