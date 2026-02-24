import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';
import 'package:sappiire/constants/app_colors.dart';

class PersonalInfoSection extends StatelessWidget {
  final VoidCallback onDateTap;
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;
  final Map<String, bool> fieldChecks;
  final Function(String, bool) onCheckChanged;
  final Function(String) onTextChanged;
  final String? bloodType;
  final Function(String?) onBloodTypeChanged;

  const PersonalInfoSection({
    super.key,
    required this.selectAll,
    this.controllers,
    required this.fieldChecks,
    required this.onCheckChanged,
    required this.onDateTap,
    required this.onTextChanged,
    this.bloodType,
    required this.onBloodTypeChanged,
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
        _buildField("Date of Birth", isDate: true),
        _buildField("Age", readOnly: true),
        _buildField("House number, street name, phase/purok"), 
        _buildField("Kasarian / Sex"),
        
        // Swapped Radio for Dropdown
        _buildBloodTypeDropdown(),
  
        _buildField("Estadong Sibil / Martial Status"), 
        _buildField("Lugar ng Kapanganakan / Place of Birth"), 
      ],
    );
  }

  Widget _buildField(String label, {bool isDate = false, bool readOnly = false}) {
    return InfoInputField(
      label: label,
      controller: controllers?[label],
      isChecked: selectAll ? true : (fieldChecks[label] ?? false),
      onCheckboxChanged: (v) => onCheckChanged(label, v ?? false),
      onTextChanged: onTextChanged,
      readOnly: isDate || readOnly,
      onTap: isDate ? onDateTap : null,
    );
  }

  Widget _buildBloodTypeDropdown() {
    const bloodTypes = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];
    final label = "Uri ng Dugo / Blood Type";
    final isChecked = selectAll ? true : (fieldChecks[label] ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label and Checkbox Row
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
                  onChanged: (v) => onCheckChanged(label, v ?? false),
                  activeColor: AppColors.primaryBlue,
                  side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // The Actual Dropdown
          DropdownButtonFormField<String>(
            value: bloodTypes.contains(bloodType) ? bloodType : null,
            items: bloodTypes.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              );
            }).toList(),
            onChanged: onBloodTypeChanged,
            decoration: InputDecoration(
              hintText: "Select Blood Type",
              hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppColors.pageBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.cardBorder, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
              ),
            ),
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue),
          ),
        ],
      ),
    );
  }
}