import 'package:flutter/material.dart';

class FormDropdown extends StatelessWidget {
  final String selectedForm;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const FormDropdown({
    super.key,
    required this.selectedForm,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.primaryColor, width: 1.2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedForm,
          isExpanded: true,
          dropdownColor: theme.colorScheme.surface,
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
          iconEnabledColor: theme.primaryColor,
          items: items
              .map(
                (val) => DropdownMenuItem(
                  value: val,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(val),
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