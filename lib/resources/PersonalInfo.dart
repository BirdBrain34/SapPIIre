import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';
import 'package:sappiire/constants/app_colors.dart';

class PersonalInfoSection extends StatelessWidget {
  final VoidCallback onDateTap;
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
    required this.onDateTap,
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
        _buildField("First Name"), 
        _buildField("Middle Name"),
        
        // Use your custom widget here for consistency!
        _buildField("Date of Birth", isDate: true),
        
        _buildField("House number, street name, phase/purok"), 
        _buildField("Kasarian / Sex"),
        _buildField("Uri ng Dugo / Blood Type"), 
  
        _buildField("Estadong Sibil / Martial Status"), 
        _buildField("Lugar ng Kapanganakan / Place of Birth"), 
      ],
    );
  }

  // Updated helper to handle the Date Logic
  Widget _buildField(String label, {bool isDate = false}) {
    return InfoInputField(
      label: label,
      controller: controllers?[label],
      isChecked: selectAll ? true : (fieldChecks[label] ?? false),
      onCheckboxChanged: (v) => onCheckChanged(label, v ?? false),
      onTextChanged: (v) {},
      // These pass through to the TextFormField inside InfoInputField
      readOnly: isDate,
      onTap: isDate ? onDateTap : null,
    );
  }
}