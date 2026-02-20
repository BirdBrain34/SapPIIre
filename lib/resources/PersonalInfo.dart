import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';
import 'package:sappiire/constants/app_colors.dart';

class PersonalInfoSection extends StatelessWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;
  final Map<String, bool> fieldChecks;
  final Function(String, bool) onCheckChanged;

  const PersonalInfoSection({
    super.key,
    required this.selectAll,
    this.controllers,
    required this.fieldChecks,
    required this.onCheckChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "PERSONAL INFORMATION",
          style: TextStyle(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const Divider(color: Colors.black12, thickness: 1, height: 20),
        
        _buildField("Last Name"),
        _buildField("First Name"), // Mapping "Given Name" to "First Name" for scanner compatibility
        _buildField("Middle Name"),
        _buildField("Date of Birth"),
        _buildField("House number, street name, phase/purok"), // Mapping "Address"
        _buildField("Kasarian"), // Mapping "Sex"
        _buildField("Estadong Sibil"), // Mapping "Marital Status"
        _buildField("Lugar ng Kapanganakan"), // Mapping "Place of Birth"
      ],
    );
  }

  Widget _buildField(String label) {
    return InfoInputField(
      label: label,
      controller: controllers?[label],
      isChecked: selectAll ? true : (fieldChecks[label] ?? false),
      onCheckboxChanged: (v) => onCheckChanged(label, v ?? false),
      onTextChanged: (v) {},
    );
  }
}