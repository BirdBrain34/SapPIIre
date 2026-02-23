import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';
import 'package:sappiire/constants/app_colors.dart';

// --- SHARED SECTION HEADER WITH CHECKBOX ---
// --- SHARED SECTION HEADER WITH CHECKBOX ---
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
        // 🔹 This is the fix: Adding a divider to separate the header from fields
        const Divider(
          color: Colors.black12, 
          thickness: 1, 
          height: 20, // This adds spacing above and below the line
        ),
      ],
    );
  }
}

// --- A. CLIENT'S INFORMATION SECTION ---
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

  Map<String, String> get membership => {
    'Solo Parent': (widget.membershipData?['solo_parent'] ?? false) ? 'Oo' : 'Hindi',
    'PWD': (widget.membershipData?['pwd'] ?? false) ? 'Oo' : 'Hindi',
    '4Ps': (widget.membershipData?['four_ps_member'] ?? false) ? 'Oo' : 'Hindi',
    'PHIC': (widget.membershipData?['phic_member'] ?? false) ? 'Oo' : 'Hindi',
  };

  // Inside _ClientInfoSectionState
Future<void> _selectDate(TextEditingController controller) async {
  final DateTime? pickedDate = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime(1900),
    lastDate: DateTime.now(),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryBlue, // Using your constant
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      );
    },
  );

  if (pickedDate != null) {
    setState(() {
      // Formats as YYYY-MM-DD
      controller.text = "${pickedDate.toLocal()}".split(' ')[0];
    });
  }
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

        const SizedBox(height: 20),
        const Text(
          "Ikaw ba ay miyembro ng pamilya na:",
          style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),

        ...membership.keys.map((key) => _buildMembershipRow(key)).toList(),
      ],
    );
  }

Widget _buildField(String label, {bool isDate = false}) {
  final controller = widget.controllers?[label];
  return InfoInputField(
    label: label,
    controller: controller,
    isChecked: widget.selectAll ? true : (widget.fieldChecks[label] ?? false), 
    onCheckboxChanged: (v) => widget.onCheckChanged(label, v ?? false),
    onTextChanged: (v) {},
    // Pass date logic to the InfoInputField
    readOnly: isDate,
    onTap: isDate && controller != null ? () => _selectDate(controller) : null,
  );
}

  Widget _buildMembershipRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          // We don't wrap individual radios in Expanded so they stay grouped
          _miniRadio(title, "Oo"),
          _miniRadio(title, "Hindi"),
        ],
      ),
    );
  }

  Widget _miniRadio(String key, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: value,
          groupValue: membership[key],
          onChanged: (v) {
            final dbKey = key == 'Solo Parent' ? 'solo_parent' 
                : key == 'PWD' ? 'pwd'
                : key == '4Ps' ? 'four_ps_member'
                : 'phic_member';
            widget.onMembershipChanged?.call(dbKey, v == 'Oo');
          },
          activeColor: AppColors.primaryBlue,
        ),
        Text(value, style: const TextStyle(color: Colors.black87, fontSize: 12)),
      ],
    );
  }
}

// --- B. FAMILY COMPOSITION TABLE ---
class FamilyTable extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers;

  const FamilyTable({super.key, required this.selectAll, this.controllers});
  @override
  State<FamilyTable> createState() => _FamilyTableState();
}

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

  void dispose() {
    nameController.dispose();
    relationController.dispose();
    birthdateController.dispose();
    ageController.dispose();
    occupationController.dispose();
    incomeController.dispose();
  }
}

class _FamilyTableState extends State<FamilyTable> {
  List<_FamilyMemberData> _members = [_FamilyMemberData()];
  bool _sectionChecked = false;

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
          onPressed: () => setState(() => _members.add(_FamilyMemberData())),
          icon: const Icon(Icons.add_circle, color: Colors.green),
          label: const Text("Add Member", style: TextStyle(color: AppColors.primaryBlue)),
        ),
      ],
    );
  }

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
                if (_members.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () => setState(() {
                      _members[index].dispose();
                      _members.removeAt(index);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField("Pangalan", member.nameController),
            _buildTextField("Relasyon", member.relationController),
            _buildDateField("Birthdate", member.birthdateController, index),
            _buildTextField("Edad", member.ageController, readOnly: true),
            _buildRadioGroup("Kasarian", ["M - Lalaki", "F - Babae"], member.gender, (v) => setState(() => member.gender = v)),
            _buildRadioGroup("Sibil Status", ["M - Kasal", "S - Single", "W - Balo", "H - Hiwalay", "C - Minor"], member.civilStatus, (v) => setState(() => member.civilStatus = v)),
            _buildRadioGroup("Edukasyon", ["UG - Undergrad", "G - Graduated", "HS - HS Grad", "OS - Hindi nag-aral", "NS - Walang Aral"], member.education, (v) => setState(() => member.education = v)),
            _buildTextField("Trabaho", member.occupationController),
            _buildTextField("Kita", member.incomeController, keyboardType: TextInputType.number),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
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

  Widget _buildDateField(String label, TextEditingController controller, int memberIndex) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        readOnly: true,
        style: const TextStyle(color: Colors.black, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black26)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primaryBlue)),
        ),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          );
          if (date != null) {
            setState(() {
              controller.text = "${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}";
              final age = DateTime.now().year - date.year;
              _members[memberIndex].ageController.text = age.toString();
            });
          }
        },
      ),
    );
  }

  Widget _buildRadioGroup(String label, List<String> options, String? groupValue, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          Wrap(
            spacing: 8,
            children: options.map((option) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<String>(
                  value: option,
                  groupValue: groupValue,
                  onChanged: onChanged,
                  activeColor: AppColors.primaryBlue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(option, style: const TextStyle(fontSize: 11)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// --- C. SOCIO-ECONOMIC SECTION ---
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

  // Computed getters that read from widget properties on every build
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