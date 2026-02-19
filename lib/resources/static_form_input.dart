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

  Widget _buildField(String label) {
    return InfoInputField(
      label: label,
      controller: widget.controllers?[label],
      isChecked: widget.selectAll ? true : (widget.fieldChecks[label] ?? false), 
      onCheckboxChanged: (v) {
        widget.onCheckChanged(label, v ?? false);
      },
      onTextChanged: (v) {},
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

class _FamilyTableState extends State<FamilyTable> {
  List<int> rows = [0];
  bool _sectionChecked = false;

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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(130),
            border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
            children: [
              _buildHeader(),
              ...rows.map((index) => _buildInputRow(index)),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => rows.add(rows.length)),
          icon: const Icon(Icons.add_circle, color: Colors.green),
          label: const Text("Add Member", style: TextStyle(color: AppColors.primaryBlue)),
        ),
      ],
    );
  }

  TableRow _buildHeader() {
    final headers = ["Pangalan", "Relasyon", "Birthdate", "Edad", "Kasarian", "Sibil Status", "Edukasyon", "Trabaho", "Kita"];
    return TableRow(
      decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.1)),
      children: headers.map((h) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(h, style: const TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.bold)),
      )).toList(),
    );
  }

  TableRow _buildInputRow(int rowIndex) {
    return TableRow(
      children: List.generate(9, (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          style: const TextStyle(color: Colors.black, fontSize: 12),
          decoration: const InputDecoration(
            border: InputBorder.none, 
            hintText: "...",
            hintStyle: TextStyle(color: Colors.grey)
          ),
        ),
      )),
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

// --- SIGNATURE SECTION ---
class SignatureSection extends StatelessWidget {
  final Map<String, TextEditingController>? controllers; 
  const SignatureSection({super.key, this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Signature", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignatureDialog())),
          child: Container(
            height: 120, width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.5)), 
              borderRadius: BorderRadius.circular(8), 
              color: Colors.grey.withOpacity(0.05)
            ),
            child: const Center(child: Text("Tap to provide digital signature", style: TextStyle(color: Colors.black54, fontSize: 12))),
          ),
        ),
      ],
    );
  }
}

// ... (SignatureDialog and SignaturePainter remain the same as they use Scaffold background)
class SignatureDialog extends StatefulWidget {
  const SignatureDialog({super.key});
  @override State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  List<Offset?> points = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue, title: const Text("Digital Signature", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.undo, color: Colors.white), onPressed: () => setState(() => points.clear())),
          IconButton(icon: const Icon(Icons.check, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (details) => setState(() => points.add(details.localPosition)),
        onPanEnd: (details) => points.add(null),
        child: CustomPaint(painter: SignaturePainter(points), size: Size.infinite),
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  SignaturePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = Colors.black..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) canvas.drawLine(points[i]!, points[i + 1]!, paint);
    }
  }
  @override bool shouldRepaint(SignaturePainter oldDelegate) => true;
}