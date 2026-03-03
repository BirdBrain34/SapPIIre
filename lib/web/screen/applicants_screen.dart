
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/side_menu.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/widget/web_shell.dart';

class ApplicantsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;

  const ApplicantsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
  });

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _selectedSubmission;
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _clientInfoFields = [
    "Last Name", "First Name", "Middle Name",
    "Date of Birth", "Age",
    "House number, street name, phase/purok", "Subdivision", "Barangay",
    "Kasarian", "Estadong Sibil", "Relihiyon",
    "CP Number", "Email Address",
    "Natapos o naabot sa pag-aaral",
    "Lugar ng Kapanganakan",
    "Trabaho/Pinagkakitaan",
    "Kumpanyang Pinagtratrabuhan",
    "Buwanang Kita (A)",
  ];

  static const List<String> _socioEconomicFields = [
    "Kabuuang Tulong/Sustento kada Buwan (C)",
    "Total Gross Family Income (A+B+C)=(D)",
    "Household Size (E)",
    "Monthly Per Capita Income (D/E)",
    "Total Monthly Expense (F)",
    "Net Monthly Income (D-F)",
    "Bayad sa bahay", "Food items", "Non-food items",
    "Utility bills", "Baby's needs", "School needs",
    "Medical needs", "Transpo expense", "Loans", "Gasul",
  ];

  static const List<String> _familyHeaders = [
    "Pangalan", "Relasyon", "Birthdate", "Edad",
    "Kasarian", "Sibil Status", "Edukasyon", "Trabaho", "Kita"
  ];

  @override
  void initState() {
    super.initState();
    _fetchSubmissions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

    void _navigateToScreen(BuildContext context, String screenPath) {
    // Map screen paths to actual navigation
    Widget nextScreen;
switch (screenPath) {
    case 'Dashboard':
      nextScreen = DashboardScreen(
        cswd_id: widget.cswd_id,
        role: widget.role,
        onLogout: _handleLogout,
        
         // Ensure you have a logout method defined
      );
      break;
    case 'Forms':
      nextScreen = ManageFormsScreen(
        cswd_id: widget.cswd_id,
        role: widget.role,
      );
      break;
    case 'Staff':
      nextScreen = ManageStaffScreen(
        cswd_id: widget.cswd_id,
        role: widget.role,
      );
      break;
    case 'CreateStaff':
      nextScreen = CreateStaffScreen(
        cswd_id: widget.cswd_id,
        role: widget.role,
      );
      break;
    case 'Applicants':
      return; // Already here, do nothing
    default:
      return;
  }
    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }

  Future<void> _fetchSubmissions() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('client_submissions')
          .select('id, form_type, data, created_at')
          .order('created_at', ascending: false);

      setState(() {
        _submissions = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching submissions: $e');
      setState(() => _isLoading = false);
    }
  }

  String _getApplicantName(Map<String, dynamic> submission) {
    final data = submission['data'] as Map<String, dynamic>? ?? {};
    final first = data['First Name'] ?? '';
    final middle = data['Middle Name'] ?? '';
    final last = data['Last Name'] ?? '';
    if (first.isEmpty && last.isEmpty) return 'Unknown Applicant';
    return '$last, $first${middle.isNotEmpty ? ' ${middle[0]}.' : ''}'.trim();
  }

  String _getFormattedDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  List<Map<String, dynamic>> get _filteredSubmissions {
    if (_searchQuery.isEmpty) return _submissions;
    final q = _searchQuery.toLowerCase();
    return _submissions.where((s) {
      return _getApplicantName(s).toLowerCase().contains(q) ||
          (s['form_type'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  String _fieldValue(String key) {
    if (_selectedSubmission == null) return '—';
    final data = _selectedSubmission!['data'] as Map<String, dynamic>? ?? {};
    final val = data[key];
    if (val == null || val.toString().isEmpty) return '—';
    return val.toString();
  }

  List<Map<String, dynamic>> get _familyRows {
    if (_selectedSubmission == null) return [];
    final data = _selectedSubmission!['data'] as Map<String, dynamic>? ?? {};
    final raw = data['family_composition'];
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (raw as List).map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> get _socioExtra {
    if (_selectedSubmission == null) return {};
    final data = _selectedSubmission!['data'] as Map<String, dynamic>? ?? {};
    return Map<String, dynamic>.from(data['socio_economic'] ?? {});
  }

  /// look up possible signature keys in submitted data
  /// return either String or Uint8List, or null if absent
  dynamic _extractSignature(Map<String, dynamic> data) {
    const candidates = [
      'digital_signature',
      'signature',
      'Digital Signature',
      'sig',
      'digitalSignature',
    ];
    for (final k in candidates) {
      if (data.containsKey(k)) {
        final val = data[k];
        if (val != null) {
          debugPrint('signature key found: $k -> $val');
          return val;
        }
      }
    }
    // nothing found
    debugPrint('no signature key present; available keys: ${data.keys.toList()}');
    return null;
  }

  Future<void> _handleLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }

@override
Widget build(BuildContext context) {
  return WebShell(
    activePath: "Applicants",
    pageTitle: "Applicants",
    pageSubtitle: "Manage and review submitted applications",
    onLogout: _handleLogout,
    // This connects the Sidebar clicks to your logic
    onNavigate: (path) => _navigateToScreen(context, path), 
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Action Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _fetchSubmissions,
              icon: const Icon(Icons.refresh, color: AppColors.primaryBlue),
              label: const Text(
                "Refresh",
                style: TextStyle(
                  color: AppColors.primaryBlue, 
                  fontWeight: FontWeight.bold
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.buttonOutlineBlue),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        // Main Content Area (The Two Panels)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildApplicantListPanel(),
              const SizedBox(width: 24),
              Expanded(child: _buildGisDetailPanel()),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildApplicantListPanel() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search applicants...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade400, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF4F7FE),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_filteredSubmissions.length} submission${_filteredSubmissions.length != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSubmissions.isEmpty
                    ? Center(
                        child: Text(
                          'No submissions found.',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredSubmissions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sub = _filteredSubmissions[index];
                          final isSelected = _selectedSubmission?['id'] == sub['id'];
                          final name = _getApplicantName(sub);
                          final date = _getFormattedDate(sub['created_at'] as String?);
                          final formType = sub['form_type'] as String? ?? 'GIS';

                          return InkWell(
                            onTap: () => setState(() => _selectedSubmission = sub),
                            child: Container(
                              color: isSelected
                                  ? AppColors.primaryBlue.withOpacity(0.08)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isSelected
                                        ? AppColors.primaryBlue
                                        : const Color(0xFFE8EDF8),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppColors.primaryBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isSelected
                                                ? AppColors.primaryBlue
                                                : const Color(0xFF1A1A2E),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          formType,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                        Text(
                                          date,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.chevron_right,
                                        color: AppColors.primaryBlue, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGisDetailPanel() {
    if (_selectedSubmission == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Select an applicant to view their form',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final data = _selectedSubmission!['data'] as Map<String, dynamic>? ?? {};
    final name = _getApplicantName(_selectedSubmission!);
    final date = _getFormattedDate(_selectedSubmission!['created_at'] as String?);
    final formType = _selectedSubmission!['form_type'] as String? ?? 'General Intake Sheet';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(formType,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white70)),
                    ],
                  ),
                ),
                Text(date,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Client Information'),
                  _buildFieldGrid(_clientInfoFields),
                  const SizedBox(height: 16),

                  _buildSectionTitle('Membership / Education / Assistance'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final key in ['4Ps?', 'Kababaihan?', 'Senior Citizen?', 'PWD?'])
                        Chip(
                          label: Text(_fieldValue(key)),
                          backgroundColor: const Color(0xFFE8EDF8),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildSectionTitle('Family Composition'),
                  _buildFamilyGrid(),
                  const SizedBox(height: 16),

                  _buildSectionTitle('Socio-Economic'),
                  ..._socioEconomicFields.map((k) => _buildSocioRow(k, k)),
                  const SizedBox(height: 16),

                  _buildSectionTitle('Digital Signature'),
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      child: Container(
                        height: 120,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Builder(builder: (context) {
                          final rawSig = _extractSignature(data);
                          if (rawSig == null) {
                            return Text('No signature provided',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12));
                          }

                          if (rawSig is Uint8List) {
                            debugPrint('rendering signature as bytes (${rawSig.length} bytes)');
                            return Image.memory(rawSig, fit: BoxFit.contain);
                          }

                          final strSig = rawSig.toString();
                          if (strSig.isEmpty) {
                            return Text('No signature provided',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12));
                          }

                          // attempt Base64 decode first
                          try {
                            final bytes = base64Decode(strSig);
                            return Image.memory(bytes, fit: BoxFit.contain);
                          } catch (e) {
                            // not valid base64, show raw text so we can inspect
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Could not render signature (invalid format):\n$strSig',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
    );
  }

  Widget _buildFieldGrid(List<String> keys) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 12, childAspectRatio: 4),
      itemBuilder: (ctx, idx) {
        final key = keys[idx];
        return Row(
          children: [
            Expanded(
                flex: 3,
                child: Text('$key:',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
            const SizedBox(width: 6),
            Expanded(
                flex: 5,
                child: Text(_fieldValue(key),
                    style: const TextStyle(fontSize: 13))),
          ],
        );
      },
    );
  }

  Widget _buildFamilyGrid() {
    final rows = _familyRows;
    if (rows.isEmpty) {
      return Text('No family members entered',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13));
    }
    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1.2),
        6: FlexColumnWidth(1.5),
        7: FlexColumnWidth(1.5),
        8: FlexColumnWidth(1),
      },
      children: [
        TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: _familyHeaders
                .map((h) => Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text(h,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ))
                .toList()),
        ...rows.map((r) => TableRow(children: [
              for (var h in _familyHeaders)
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(r[h] ?? '—',
                      style: const TextStyle(fontSize: 12)),
                )
            ]))
      ],
    );
  }

  Widget _buildSocioRow(String label, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text('$label:',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
          const SizedBox(width: 6),
          Expanded(
              flex: 5, child: Text(_fieldValue(key), style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
