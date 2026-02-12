import 'package:flutter/material.dart';
import 'package:sappiire/mobile/widgets/info_input_field.dart';

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
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Checkbox(
          value: isChecked,
          onChanged: onChecked,
          side: const BorderSide(color: Colors.white, width: 2),
          activeColor: const Color(0xFF4A69D4),
        ),
      ],
    );
  }
}

// --- A. CLIENT'S INFORMATION SECTION ---
class ClientInfoSection extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers; 

  const ClientInfoSection({super.key, required this.selectAll, this.controllers});

  @override
  State<ClientInfoSection> createState() => _ClientInfoSectionState();
}

class _ClientInfoSectionState extends State<ClientInfoSection> {
  bool _sectionChecked = false;
  
  Map<String, String> membership = {
    'Solo Parent': 'Hindi',
    'PWD': 'Hindi',
    '4Ps': 'Hindi',
    'PHIC': 'Hindi',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "A. CLIENT'S INFORMATION",
          isChecked: widget.selectAll || _sectionChecked,
          onChecked: (v) => setState(() => _sectionChecked = v!),
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
        const Text("Ikaw ba ay miyembro ng pamilya na:", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        
        ...membership.keys.map((key) => _buildMembershipRow(key)).toList(),
      ],
    );
  }

  Widget _buildField(String label) {
    return InfoInputField(
      label: label,
      controller: widget.controllers?[label], // Link to shared controller
      isChecked: widget.selectAll || _sectionChecked,
      onCheckboxChanged: (v) {},
      onTextChanged: (v) {},
    );
  }

  Widget _buildMembershipRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13))),
          Expanded(child: _miniRadio(title, "Oo")),
          Expanded(child: _miniRadio(title, "Hindi")),
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
          onChanged: (v) => setState(() => membership[key] = v!),
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            return states.contains(WidgetState.selected) ? Colors.white : Colors.white.withOpacity(0.8);
          }),
        ),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

// --- B. FAMILY COMPOSITION TABLE ---
class FamilyTable extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers; // Added for handshake

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
            border: TableBorder.all(color: Colors.white.withOpacity(0.5)),
            children: [
              _buildHeader(),
              ...rows.map((_) => _buildInputRow()),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => rows.add(rows.length)),
          icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
          label: const Text("Add Member", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  TableRow _buildHeader() {
    final headers = ["Pangalan", "Relasyon", "Birthdate", "Edad", "Kasarian", "Sibil Status", "Edukasyon", "Trabaho", "Kita"];
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFF0A1E5E)),
      children: headers.map((h) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(h, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      )).toList(),
    );
  }

  TableRow _buildInputRow() {
    return TableRow(
      children: List.generate(9, (index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          style: TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(border: InputBorder.none, hintText: "..."),
        ),
      )),
    );
  }
}

// --- C. SOCIO-ECONOMIC SECTION ---
class SocioEconomicSection extends StatefulWidget {
  final bool selectAll;
  final Map<String, TextEditingController>? controllers; // FIXED: Added to class

  const SocioEconomicSection({
    super.key, 
    required this.selectAll, 
    this.controllers, // FIXED: Added to constructor
  });

  @override
  State<SocioEconomicSection> createState() => _SocioEconomicSectionState();
}

class _SocioEconomicSectionState extends State<SocioEconomicSection> {
  String? _hasSupport = "Wala";
  String? _housingStatus;
  bool _sectionChecked = false;
  List<int> _supportRows = [0]; 

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
        const Text("May ibang kaanak na sumusuporta sa pamilya?", style: TextStyle(color: Colors.white)),
        Row(
          children: [
            _radioOption("Meron"),
            _radioOption("Wala"),
          ],
        ),
        if (_hasSupport == "Meron") ...[
          const SizedBox(height: 10),
          _buildSupportTable(),
          TextButton.icon(
            onPressed: () => setState(() => _supportRows.add(_supportRows.length)),
            icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
            label: const Text("Add Support Member", style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
          _buildFormInput("Kabuuang Tulong/Sustento kada Buwan (C)"),
        ],
        const SizedBox(height: 20),
        const Text("Ikaw ba ay?", style: TextStyle(color: Colors.white)),
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
        const Text("Mga gastusin sa bahay:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ...["Bayad sa bahay", "Food items", "Non-food items", "Utility bills", "Baby's needs", "School needs", "Medical needs", "Transpo expense", "Loans", "Gasul"].map((e) => _buildFormInput(e)).toList(),
      ],
    );
  }

  Widget _radioOption(String val) {
    return Expanded(
      child: RadioListTile<String>(
        title: Text(val, style: const TextStyle(color: Colors.white, fontSize: 14)),
        value: val,
        groupValue: _hasSupport,
        onChanged: (v) => setState(() => _hasSupport = v),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.white.withOpacity(0.8)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _housingOption(String val) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.45,
      child: RadioListTile<String>(
        title: Text(val, style: const TextStyle(color: Colors.white, fontSize: 11)),
        value: val,
        groupValue: _housingStatus,
        onChanged: (v) => setState(() => _housingStatus = v),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.white.withOpacity(0.8)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSupportTable() {
    return Table(
      border: TableBorder.all(color: Colors.white.withOpacity(0.5)),
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFF0A1E5E)),
          children: [
            Padding(padding: EdgeInsets.all(8), child: Text("Pangalan", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text("Relasyon", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text("Sustento", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          ],
        ),
        ..._supportRows.map((_) => TableRow(
          children: List.generate(3, (i) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: TextField(style: TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(border: InputBorder.none, hintText: "...")),
          )),
        )),
      ],
    );
  }

  Widget _buildFormInput(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: widget.controllers?[label], // FIXED: Using the controller
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        ),
      ),
    );
  }
}

// --- SIGNATURE SECTION ---
class SignatureSection extends StatelessWidget {
  final Map<String, TextEditingController>? controllers; // Added
  const SignatureSection({super.key, this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Signature", style: TextStyle(color: Colors.white)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignatureDialog())),
          child: Container(
            height: 120, width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(8), color: Colors.white.withOpacity(0.05)),
            child: const Center(child: Text("Tap to provide digital signature", style: TextStyle(color: Colors.white54, fontSize: 12))),
          ),
        ),
      ],
    );
  }
}
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
        backgroundColor: const Color(0xFF0A1E5E), title: const Text("Digital Signature"),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: () => setState(() => points.clear())),
          IconButton(icon: const Icon(Icons.check), onPressed: () => Navigator.pop(context)),
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