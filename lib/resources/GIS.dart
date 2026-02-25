import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/date_picker_helper.dart';
import 'package:sappiire/mobile/widgets/editable_text_field.dart';
import 'package:sappiire/mobile/widgets/editable_radio_group.dart';

// Reusable section header widget with checkbox
// Used across all form sections (Client Info, Family Composition, Socio-Economic)
class SectionHeader extends StatelessWidget {
  final String title;
  final bool isChecked;
  final ValueChanged<bool?> onChecked;

  const SectionHeader({
    super.key,
    required this.title,
    required this.isChecked,
    required this.onChecked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.bold, 
                  fontSize: 16
                ),
              ),
            ),
            Checkbox(
              value: isChecked,
              onChanged: onChecked,
              side: const BorderSide(color: AppColors.primaryBlue, width: 2),
              activeColor: AppColors.primaryBlue,
            ),
          ],
        ),
        const Divider(
          color: Colors.black12, 
          thickness: 1, 
          height: 20,
        ),
      ],
    );
  }
}

// Section A: Client's Information
// Displays basic client details like name, address, contact info, and membership status
class ClientInfoSection extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;
  final Map<String, bool> fieldChecks;
  final Function(String, bool) onCheckChanged;
  final Map<String, bool>? membershipData;
  final Function(String, bool)? onMembershipChanged;

  const ClientInfoSection({
    super.key,
    required this.selectAll,
    this.controllers,
    required this.fieldChecks,
    required this.onCheckChanged,
    this.membershipData,
    this.onMembershipChanged,
  });

  @override
  State<ClientInfoSection> createState() => _ClientInfoSectionState();
}

class _ClientInfoSectionState extends State<ClientInfoSection> {
  bool _sectionChecked = false;

  // Convert membership boolean data to Filipino Yes/No format
  Map<String, String> get membership => {
    'Solo Parent': (widget.membershipData?['solo_parent'] ?? false) ? 'Oo' : 'Hindi',
    'PWD': (widget.membershipData?['pwd'] ?? false) ? 'Oo' : 'Hindi',
    '4Ps': (widget.membershipData?['four_ps_member'] ?? false) ? 'Oo' : 'Hindi',
    'PHIC': (widget.membershipData?['phic_member'] ?? false) ? 'Oo' : 'Hindi',
  };

  Future<void> _selectDate(TextEditingController controller) async {
  await DatePickerHelper.selectDate(
    context: context,
    dateController: controller,
    ageController: widget.controllers?["Age"],
  );
  setState(() {});
}

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "A. CLIENT'S INFORMATION",
          isChecked: widget.selectAll || _sectionChecked,
          onChecked: (v) {
            setState(() => _sectionChecked = v!);
            widget.fieldChecks.forEach((key, value) {
              widget.onCheckChanged(key, v!);
            });
          },
        ),
        const SizedBox(height: 10),

        _buildField("Last Name"),
        _buildField("First Name"),
        _buildField("Middle Name"),
        _buildField("Date of Birth", isDate: true),
        _buildField("Age", readOnly: true),
        _buildField("House number, street name, phase/purok"),
        _buildField("Subdivision"),
        _buildField("Barangay"),
        _buildField("Kasarian"),
        _buildField("Estadong Sibil"),
        _buildField("Relihiyon"),
        _buildField("CP Number"),
        _buildField("Email Address"),
        _buildField("Natapos o naabot sa pag-aaral"),
        _buildField("Lugar ng Kapanganakan"),
        _buildField("Trabaho/Pinagkakakitaan"),
        _buildField("Kumpanyang Pinagtratrabuhan"),
        _buildField("Buwanang Kita (A)"),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    "Ikaw ba ay miyembro ng pamilya na:",
                    style: TextStyle(
                      color: AppColors.primaryBlue, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 14
                    ),
                  ),
                ),
                Checkbox(
                  value: widget.fieldChecks["Membership Group"] ?? false,
                  onChanged: (val) => widget.onCheckChanged("Membership Group", val ?? false),
                  activeColor: AppColors.primaryBlue,
                  side: const BorderSide(color: AppColors.primaryBlue, width: 2),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _buildMembershipRow("Solo Parent"),
            _buildMembershipRow("PWD"),
            _buildMembershipRow("4Ps"),
            _buildMembershipRow("PHIC Member"),
          ],
        )
      ],
    );
  }

Widget _buildField(String label, {bool isDate = false, bool readOnly = false}) {
  final controller = widget.controllers?[label];
  return InfoInputField(
    label: label,
    controller: controller,
    isChecked: widget.selectAll ? true : (widget.fieldChecks[label] ?? false), 
    onCheckboxChanged: (v) => widget.onCheckChanged(label, v ?? false),
    onTextChanged: (v) {},
    readOnly: isDate || readOnly,
    onTap: isDate && controller != null ? () => _selectDate(controller) : null,
  );
}

Widget _buildMembershipRow(String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        // This calls the radio button widget you provided
        _miniRadio(label, 'Oo'),
        _miniRadio(label, 'Hindi'),
      ],
    ),
  );
}

  Widget _miniRadio(String key, String value) {
    final Map<String, String> dbKeyMap = {
      'Solo Parent': 'solo_parent',
      'PWD': 'pwd',
      '4Ps': 'four_ps_member',
      'PHIC Member': 'phic_member',
    };

    final String dbKey = dbKeyMap[key] ?? key;
    
    // Get the actual boolean value from the widget's properties
    bool isTrue = widget.membershipData?[dbKey] ?? false;
    
    // A radio is selected if (value is 'Oo' and data is true) OR (value is 'Hindi' and data is false)
    bool isSelected = (value == 'Oo' && isTrue) || (value == 'Hindi' && !isTrue);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: value,
          groupValue: isSelected ? value : null, 
          onChanged: (v) {
            // Trigger the callback to the parent ManageInfoScreen
            widget.onMembershipChanged?.call(dbKey, v == 'Oo');
          },
          activeColor: AppColors.primaryBlue,
        ),
        Text(value, style: const TextStyle(color: Colors.black87, fontSize: 12)),
      ],
    );
  }
}

// Section B: Family Composition
// Manages list of family members with edit mode functionality
// Each member can be edited individually using pencil/check icons
class FamilyTable extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;
  final List<Map<String, dynamic>>? familyMembers;
  final Function(List<Map<String, dynamic>>)? onFamilyChanged;

  const FamilyTable({
    super.key, 
    required this.selectAll, 
    this.controllers,
    this.familyMembers,
    this.onFamilyChanged,
  });
  @override
  State<FamilyTable> createState() => FamilyTableState();
}

// Data model for a single family member
// Contains all fields and controllers needed for family member information
class _FamilyMemberData {
  TextEditingController nameController = TextEditingController();
  TextEditingController relationController = TextEditingController();
  TextEditingController birthdateController = TextEditingController();
  TextEditingController ageController = TextEditingController();
  String? gender;
  String? civilStatus;
  String? education;
  TextEditingController occupationController = TextEditingController();
  TextEditingController incomeController = TextEditingController();
  bool isEditing = false; // Controls whether fields are editable

  void dispose() {
    nameController.dispose();
    relationController.dispose();
    birthdateController.dispose();
    ageController.dispose();
    occupationController.dispose();
    incomeController.dispose();
  }
}

class FamilyTableState extends State<FamilyTable> {
  List<_FamilyMemberData> _members = [];
  bool _sectionChecked = false;

  @override
  void initState() {
    super.initState();
    _initializeMembers();
  }

  @override
  void didUpdateWidget(FamilyTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyMembers != widget.familyMembers) {
      _initializeMembers();
    }
  }

  // Initialize family members from database data or create empty member
  // Existing members start in read-only mode, new members start in edit mode
  void _initializeMembers() {
    if (widget.familyMembers != null && widget.familyMembers!.isNotEmpty) {
      _members = widget.familyMembers!.map((data) {
        final member = _FamilyMemberData();
        member.nameController.text = data['name']?.toString() ?? '';
        member.relationController.text = data['relationship_of_relative']?.toString() ?? '';
        member.birthdateController.text = data['birthdate']?.toString() ?? '';
        member.ageController.text = data['age']?.toString() ?? '';
        member.gender = data['gender']?.toString();
        member.civilStatus = data['civil_status']?.toString();
        member.education = data['education']?.toString();
        member.occupationController.text = data['occupation']?.toString() ?? '';
        member.incomeController.text = data['allowance']?.toString() ?? '';
        member.isEditing = false; // Existing members are read-only by default
        return member;
      }).toList();
    } else {
      // Create first member in edit mode for new users
      final newMember = _FamilyMemberData();
      newMember.isEditing = true;
      _members = [newMember];
    }
  }

  // Convert member data to format expected by database
  // Called when saving to collect all family member information
  List<Map<String, dynamic>> getFamilyData() {
    return _members.map((member) {
      return {
        'name': member.nameController.text.trim(),
        'relationship_of_relative': member.relationController.text.trim(),
        'birthdate': member.birthdateController.text.trim(),
        'age': int.tryParse(member.ageController.text) ?? 0,
        'gender': member.gender ?? '',
        'civil_status': member.civilStatus ?? '',
        'education': member.education ?? '',
        'occupation': member.occupationController.text.trim(),
        'allowance': double.tryParse(member.incomeController.text.replaceAll(',', '')) ?? 0,
      };
    }).toList();
  }

  @override
  void dispose() {
    for (var member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "B. FAMILY COMPOSITION",
          isChecked: widget.selectAll || _sectionChecked,
          onChecked: (v) => setState(() => _sectionChecked = v!),
        ),
        const SizedBox(height: 10),
        ..._members.asMap().entries.map((entry) => _buildMemberCard(entry.key)),
        TextButton.icon(
          onPressed: () {
            // Create new member in edit mode and notify parent to show save button
            final newMember = _FamilyMemberData();
            newMember.isEditing = true;
            setState(() => _members.add(newMember));
            widget.onFamilyChanged?.call(getFamilyData());
          },
          icon: const Icon(Icons.add_circle, color: Colors.green),
          label: const Text("Add Member", style: TextStyle(color: AppColors.primaryBlue)),
        ),
      ],
    );
  }

  // Build card for individual family member with edit/check/delete buttons
  Widget _buildMemberCard(int index) {
    final member = _members[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Member ${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                ),
                // Show pencil icon when not editing, check icon when editing
                if (!member.isEditing)
                  IconButton(
                    icon: const Icon(Icons.edit, color: AppColors.primaryBlue, size: 20),
                    onPressed: () {
                      setState(() => member.isEditing = true);
                    },
                  ),
                if (member.isEditing)
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green, size: 20),
                    onPressed: () {
                      // Exit edit mode and trigger save button to appear
                      setState(() => member.isEditing = false);
                      widget.onFamilyChanged?.call(getFamilyData());
                    },
                  ),
                if (_members.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        _members[index].dispose();
                        _members.removeAt(index);
                      });
                      widget.onFamilyChanged?.call(getFamilyData());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Use reusable widgets for cleaner code
            EditableTextField(
              label: "Pangalan",
              controller: member.nameController,
              isEditing: member.isEditing,
            ),
            EditableTextField(
              label: "Relasyon",
              controller: member.relationController,
              isEditing: member.isEditing,
            ),
            _buildDateField("Birthdate", member.birthdateController, index, member.isEditing),
            EditableTextField(
              label: "Edad",
              controller: member.ageController,
              isEditing: member.isEditing,
              readOnly: true,
            ),
            EditableRadioGroup(
              label: "Kasarian",
              options: ["M - Lalaki", "F - Babae"],
              groupValue: member.gender,
              isEditing: member.isEditing,
              onChanged: (v) => setState(() => member.gender = v),
            ),
            EditableRadioGroup(
              label: "Sibil Status",
              options: ["M - Kasal", "S - Single", "W - Balo", "H - Hiwalay", "C - Minor"],
              groupValue: member.civilStatus,
              isEditing: member.isEditing,
              onChanged: (v) => setState(() => member.civilStatus = v),
            ),
            EditableRadioGroup(
              label: "Edukasyon",
              options: ["UG - Undergrad", "G - Graduated", "HS - HS Grad", "OS - Hindi nag-aral", "NS - Walang Aral"],
              groupValue: member.education,
              isEditing: member.isEditing,
              onChanged: (v) => setState(() => member.education = v),
            ),
            EditableTextField(
              label: "Trabaho",
              controller: member.occupationController,
              isEditing: member.isEditing,
            ),
            EditableTextField(
              label: "Kita",
              controller: member.incomeController,
              isEditing: member.isEditing,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }

  // Date picker field with calendar icon
  // Only allows date selection when in edit mode

  Widget _buildDateField(String label, TextEditingController controller, int memberIndex, bool isEditing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        readOnly: true,
        style: TextStyle(color: isEditing ? Colors.black : Colors.black54, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
          suffixIcon: isEditing ? const Icon(Icons.calendar_today, size: 18) : null,
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isEditing ? Colors.black26 : Colors.transparent)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primaryBlue)),
          disabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
        ),
        onTap: !isEditing ? null : () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          );
          if (date != null) {
            // Format date and auto-calculate age
            controller.text = "${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}";
            final age = DateTime.now().year - date.year;
            _members[memberIndex].ageController.text = age.toString();
          }
        },
      ),
    );
  }


}

// Section C: Socio-Economic Data
// Manages household income, expenses, housing status, and supporting family members
class SocioEconomicSection extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;
  final bool? hasSupport;
  final String? housingStatus;
  final List<Map<String, dynamic>>? supportingFamily;
  final Function(bool)? onHasSupportChanged;
  final Function(String)? onHousingStatusChanged;
  final Function(List<Map<String, dynamic>>)? onSupportingFamilyChanged;
  final VoidCallback? onAddMember;

  const SocioEconomicSection({
    super.key, 
    required this.selectAll, 
    this.controllers,
    this.hasSupport,
    this.housingStatus,
    this.supportingFamily,
    this.onHasSupportChanged,
    this.onHousingStatusChanged,
    this.onSupportingFamilyChanged,
    this.onAddMember,
  });

  @override
  State<SocioEconomicSection> createState() => _SocioEconomicSectionState();
}

class _SocioEconomicSectionState extends State<SocioEconomicSection> {
  bool _sectionChecked = false;
  List<Map<String, TextEditingController>> _supportControllers = [];

  @override
  void initState() {
    super.initState();
    _initializeSupportControllers();
  }

  

  @override
  void didUpdateWidget(SocioEconomicSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supportingFamily != widget.supportingFamily && 
        widget.supportingFamily != null && 
        widget.supportingFamily!.isNotEmpty &&
        _supportControllers.isEmpty) {
      _removeListeners();
      _initializeSupportControllers();
    }
  }

  // Initialize controllers for supporting family members from database
  void _initializeSupportControllers() {
    _removeListeners();
    _supportControllers.clear();
    final family = widget.supportingFamily ?? [];
    if (family.isEmpty && (widget.hasSupport ?? false)) {
      _supportControllers.add(_createControllerSet());
    } else {
      for (var member in family) {
        _supportControllers.add(_createControllerSet(
          name: member['name'] ?? '',
          relationship: member['relationship'] ?? '',
          sustento: member['regular_sustento']?.toString() ?? '',
        ));
      }
    }
    _setupListeners();
  }

  Map<String, TextEditingController> _createControllerSet({String name = '', String relationship = '', String sustento = ''}) {
    return {
      'name': TextEditingController(text: name),
      'relationship': TextEditingController(text: relationship),
      'sustento': TextEditingController(text: sustento),
    };
  }

  void _setupListeners() {
    for (var ctrl in _supportControllers) {
      ctrl['name']?.addListener(_notifyParent);
      ctrl['relationship']?.addListener(_notifyParent);
      ctrl['sustento']?.addListener(_notifyParent);
    }
  }

  void _removeListeners() {
    for (var ctrl in _supportControllers) {
      ctrl['name']?.removeListener(_notifyParent);
      ctrl['relationship']?.removeListener(_notifyParent);
      ctrl['sustento']?.removeListener(_notifyParent);
    }
  }

  void _notifyParent() {
    final list = _collectData();
    widget.onSupportingFamilyChanged?.call(list);
  }

  void _addSupportMember() {
    setState(() {
      final newCtrl = _createControllerSet();
      _supportControllers.add(newCtrl);
      newCtrl['name']?.addListener(_notifyParent);
      newCtrl['relationship']?.addListener(_notifyParent);
      newCtrl['sustento']?.addListener(_notifyParent);
    });
    widget.onAddMember?.call();
  }

  List<Map<String, dynamic>> _collectData() {
    return _supportControllers.map((ctrl) => {
      'name': ctrl['name']!.text,
      'relationship': ctrl['relationship']!.text,
      'regular_sustento': double.tryParse(ctrl['sustento']!.text) ?? 0,
    }).toList();
  }

  @override
  void dispose() {
    _removeListeners();
    for (var ctrl in _supportControllers) {
      ctrl['name']?.dispose();
      ctrl['relationship']?.dispose();
      ctrl['sustento']?.dispose();
    }
    super.dispose();
  }

  // Convert boolean to Filipino Yes/No for UI display
  String get hasSupportValue => (widget.hasSupport ?? false) ? "Meron" : "Wala";
  String? get housingStatusValue => widget.housingStatus; 

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "C. SOCIO-ECONOMIC DATA",
          isChecked: widget.selectAll || _sectionChecked,
          onChecked: (v) => setState(() => _sectionChecked = v!),
        ),
        const SizedBox(height: 15),
        const Text("May ibang kaanak na sumusuporta sa pamilya?", style: TextStyle(color: Colors.black87)),
        Row(
          children: [
            _radioOption("Meron"),
            _radioOption("Wala"),
          ],
        ),
        if (hasSupportValue == "Meron") ...[
          const SizedBox(height: 10),
          _buildSupportTable(),
          TextButton.icon(
            onPressed: _addSupportMember,
            icon: const Icon(Icons.add_circle, color: Colors.green),
            label: const Text("Add Support Member", style: TextStyle(color: AppColors.primaryBlue, fontSize: 12)),
          ),
          _buildFormInput("Kabuuang Tulong/Sustento kada Buwan (C)"),
        ],
        const SizedBox(height: 20),
        const Text("Ikaw ba ay?", style: TextStyle(color: Colors.black87)),
        Wrap(
          children: [
            "Nagmamay-ari ng bahay", "Hinuhulugan pa ang bahay", "Nakikitira", 
            "Nangungupahan", "Informal settler", "Transient", "Nakatira sa kalye/Dislocated"
          ].map((v) => _housingOption(v)).toList(),
        ),
        const SizedBox(height: 20),
        _buildFormInput("Total Gross Family Income (A+B+C)=(D)"),
        _buildFormInput("Household Size (E)"),
        _buildFormInput("Monthly Per Capita Income (D/E)"),
        _buildFormInput("Total Monthly Expense (F)"),
        _buildFormInput("Net Monthly Income (D-F)"),
        const SizedBox(height: 25),
        const Text("Mga gastusin sa bahay:", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
        ...["Bayad sa bahay", "Food items", "Non-food items", "Utility bills", "Baby's needs", "School needs", "Medical needs", "Transpo expense", "Loans", "Gasul"].map((e) => _buildFormInput(e)).toList(),
      ],
    );
  }

  Widget _radioOption(String val) {
    return Expanded(
      child: RadioListTile<String>(
        title: Text(val, style: const TextStyle(color: Colors.black87, fontSize: 14)),
        value: val,
        groupValue: hasSupportValue,
        onChanged: (v) {
          widget.onHasSupportChanged?.call(v == "Meron");
        },
        activeColor: AppColors.primaryBlue,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _housingOption(String val) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.45,
      child: RadioListTile<String>(
        title: Text(val, style: const TextStyle(color: Colors.black87, fontSize: 11)),
        value: val,
        groupValue: housingStatusValue,
        onChanged: (v) {
          widget.onHousingStatusChanged?.call(v!);
        },
        activeColor: AppColors.primaryBlue,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSupportTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
      children: [
        TableRow(
          decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.1)),
          children: const [
            Padding(padding: EdgeInsets.all(8), child: Text("Pangalan", style: TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text("Relasyon", style: TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text("Sustento", style: TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold))),
          ],
        ),
        ..._supportControllers.asMap().entries.map((entry) => TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: TextField(
                controller: entry.value['name'],
                style: const TextStyle(color: Colors.black, fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "...",
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: TextField(
                controller: entry.value['relationship'],
                style: const TextStyle(color: Colors.black, fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "...",
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: TextField(
                controller: entry.value['sustento'],
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.black, fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "...",
                  isDense: true,
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }

  Widget _buildFormInput(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: widget.controllers?[label], 
        style: const TextStyle(color: Colors.black, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black26)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primaryBlue)),
        ),
      ),
    );
  }
  
}





