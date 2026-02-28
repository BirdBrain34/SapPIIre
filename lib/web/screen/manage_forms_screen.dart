import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/resources/GIS.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/resources/signature_field.dart';

class ManageFormsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;

  const ManageFormsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
  });

  @override
  State<ManageFormsScreen> createState() => _ManageFormsScreenState();
}

class _ManageFormsScreenState extends State<ManageFormsScreen> {
  List<Offset?>? _capturedSignaturePoints;
  String? _signatureBase64;
  String selectedForm = "General Intake Sheet";
  final Map<String, TextEditingController> _webControllers = {};
  String _currentSessionId = "WAITING-FOR-SESSION";
  StreamSubscription? _formSubscription;
  
  // Additional state for complex fields
  Map<String, bool> _membershipData = {
    'solo_parent': false,
    'pwd': false,
    'four_ps_member': false,
    'phic_member': false,
  };
  List<Map<String, dynamic>> _familyMembers = [];
  List<Map<String, dynamic>> _supportingFamily = [];
  bool _hasSupport = false;
  String? _housingStatus;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _createNewSession();
  }

  void _initializeControllers() {
    final List<String> allLabels = [
      "Last Name", "First Name", "Middle Name", "Date of Birth", "Age",
      "House number, street name, phase/purok", "Subdivision", "Barangay",
      "Kasarian", "Estadong Sibil", "Relihiyon", "CP Number", "Email Address",
      "Natapos o naabot sa pag-aaral", "Lugar ng Kapanganakan",
      "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
      "Buwanang Kita (A)", "Total Gross Family Income (A+B+C)=(D)",
      "Household Size (E)", "Monthly Per Capita Income (D/E)",
      "Total Monthly Expense (F)", "Net Monthly Income (D-F)",
      "Bayad sa bahay", "Food items", "Non-food items", "Utility bills",
      "Baby's needs", "School needs", "Medical needs", "Transpo expense",
      "Loans", "Gasul", "Kabuuang Tulong/Sustento kada Buwan (C)"
    ];

    for (var label in allLabels) {
      _webControllers[label] = TextEditingController();
    }
  }

  void _clearAllFields() {
    for (var controller in _webControllers.values) {
      controller.clear();
    }
    setState(() {
      _membershipData = {
        'solo_parent': false,
        'pwd': false,
        'four_ps_member': false,
        'phic_member': false,
      };
      _familyMembers = [];
      _supportingFamily = [];
      _hasSupport = false;
      _housingStatus = null;
      _signatureBase64 = null;
      _capturedSignaturePoints = null;
    });
  }

  @override
  void dispose() {
    _formSubscription?.cancel(); 
    for (final c in _webControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createNewSession() async {
    try {
      _clearAllFields(); 
      
      final response = await Supabase.instance.client
          .from('form_submission')
          .insert({
            'status': 'active', 
            'form_type': selectedForm, 
            'form_data': {}
          })
          .select()
          .single();

      setState(() {
        _currentSessionId = response['id'].toString();
      });

      _listenForMobileUpdates(_currentSessionId);
    } catch (e) {
      debugPrint("Error creating session: $e");
    }
  }

  void _listenForMobileUpdates(String sessionId) {
    _formSubscription?.cancel(); 
    
    _formSubscription = Supabase.instance.client
        .from('form_submission')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .listen((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty) {
        final Map<String, dynamic> incomingData = data.first['form_data'] ?? {};

        setState(() {
          // Handle regular text fields
          incomingData.forEach((key, value) {
            if (_webControllers.containsKey(key)) {
              if (_webControllers[key]!.text != value.toString()) {
                _webControllers[key]!.text = value.toString();
              }
            }
          });

          // Handle membership data
          if (incomingData.containsKey('__membership')) {
            final membership = incomingData['__membership'] as Map<String, dynamic>;
            _membershipData = {
              'solo_parent': membership['solo_parent'] ?? false,
              'pwd': membership['pwd'] ?? false,
              'four_ps_member': membership['four_ps_member'] ?? false,
              'phic_member': membership['phic_member'] ?? false,
            };
          }

          // Handle family composition
          if (incomingData.containsKey('__family_composition')) {
            _familyMembers = List<Map<String, dynamic>>.from(
              incomingData['__family_composition'] ?? []
            );
          }

          // Handle supporting family
          if (incomingData.containsKey('__supporting_family')) {
            _supportingFamily = List<Map<String, dynamic>>.from(
              incomingData['__supporting_family'] ?? []
            );
          }

          // Handle has_support flag
          if (incomingData.containsKey('__has_support')) {
            _hasSupport = incomingData['__has_support'] ?? false;
          }

          // Handle housing status
          if (incomingData.containsKey('__housing_status')) {
            _housingStatus = incomingData['__housing_status'];
          }

          // Handle signature
          if (incomingData.containsKey('__signature')) {
            _signatureBase64 = incomingData['__signature'];
            if (_signatureBase64 != null && _signatureBase64!.isNotEmpty) {
              _capturedSignaturePoints = [];
            }
          }
        });
      }
    });
  }

  Future<void> _finalizeEntry() async {
    final Map<String, dynamic> finalData = {};
    
    // Save all text field data
    _webControllers.forEach((key, controller) {
      finalData[key] = controller.text;
    });
    
    // Save membership data with special prefix
    if (_membershipData.isNotEmpty) {
      finalData['__membership'] = _membershipData;
    }
    
    // Save family composition
    if (_familyMembers.isNotEmpty) {
      finalData['__family_composition'] = _familyMembers;
    }
    
    // Save supporting family
    if (_supportingFamily.isNotEmpty) {
      finalData['__supporting_family'] = _supportingFamily;
    }
    
    // Save has support flag
    finalData['__has_support'] = _hasSupport;
    
    // Save housing status
    if (_housingStatus != null) {
      finalData['__housing_status'] = _housingStatus;
    }
    
    // Save signature if available
    if (_signatureBase64 != null && _signatureBase64!.isNotEmpty) {
      finalData['__signature'] = _signatureBase64;
    }

    try {
      await Supabase.instance.client.from('client_submissions').insert({
        'form_type': selectedForm,
        'data': finalData,
        'created_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client
          .from('form_submission')
          .update({'status': 'completed'})
          .eq('id', _currentSessionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Entry saved and finalized!")),
        );
      }
      
      _createNewSession(); 
    } catch (e) {
      debugPrint("Finalize Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error finalizing entry: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      _formSubscription?.cancel();
      if (_currentSessionId != "WAITING-FOR-SESSION") {
        await Supabase.instance.client
            .from('form_submission')
            .update({'status': 'closed'})
            .eq('id', _currentSessionId);
      }
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          ContentFadeRoute(page: const WorkerLoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Forms',
      pageTitle: 'Forms Management',
      pageSubtitle: 'Complete and submit client intake forms',
      onLogout: _handleLogout,
      headerActions: [
        _buildHeaderButton(
          "Reset Form / New QR",
          Icons.refresh,
          onPressed: _createNewSession,
        ),
      ],
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdown(),
            const SizedBox(height: 25),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
                ),
                child: Row(
                  children: [
                    _buildQrSidebar(),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(right: 10),
                          child: Column(
                            children: [
                              _buildWebSectionCard(
                                child: ClientInfoSection(
                                  selectAll: false,
                                  controllers: _webControllers,
                                  fieldChecks: const {},
                                  onCheckChanged: (key, val) {},
                                  membershipData: _membershipData,
                                  onMembershipChanged: (key, val) {
                                    setState(() => _membershipData[key] = val);
                                  },
                                ),
                              ),
                              _buildWebSectionCard(
                                child: FamilyTable(
                                  selectAll: false,
                                  controllers: _webControllers,
                                  familyMembers: _familyMembers,
                                  onFamilyChanged: (members) {
                                    setState(() => _familyMembers = members);
                                  },
                                ),
                              ),
                              _buildWebSectionCard(
                                child: SocioEconomicSection(
                                  selectAll: false,
                                  controllers: _webControllers,
                                  hasSupport: _hasSupport,
                                  housingStatus: _housingStatus,
                                  supportingFamily: _supportingFamily,
                                  onHasSupportChanged: (val) {
                                    setState(() => _hasSupport = val);
                                  },
                                  onHousingStatusChanged: (val) {
                                    setState(() => _housingStatus = val);
                                  },
                                  onSupportingFamilyChanged: (list) {
                                    setState(() => _supportingFamily = list);
                                  },
                                ),
                              ),
                              _buildWebSectionCard(
                                child: SignatureField(
                                  points: _capturedSignaturePoints,
                                  label: "Digital Signature",
                                  signatureImageBase64: _signatureBase64,
                                  // --- ADD THESE TWO LINES TO FIX THE ERROR ---
                                  isChecked: false, 
                                  onCheckboxChanged: (val) {}, 
                                  // --------------------------------------------
                                  onCaptured: (points) {
                                    setState(() {
                                      _capturedSignaturePoints = points;
                                      _signatureBase64 = null;
                                    });
                                  },
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _finalizeEntry,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.buttonPurple,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 60,
                                    vertical: 20,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  "FINALIZE & SAVE ENTRY",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      default:
        return; // Stay on current screen
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }

  // 🔹 Helper to create the Mobile-like White Card style
  Widget _buildWebSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildQrSidebar() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Text("Live Form QR", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Scan with SapPIIre Mobile", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(
              data: _currentSessionId,
              version: QrVersions.auto,
              size: 220.0,
            ),
          ),
          const SizedBox(height: 15),
          Text("Session: ${_currentSessionId.split('-').first}...", style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      width: 400,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.buttonOutlineBlue.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedForm,
          items: ["General Intake Sheet", "Medical Assistance", "Emergency Burial"]
              .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.w600))))
              .toList(),
          onChanged: (val) async {
            setState(() => selectedForm = val!);
            if (_currentSessionId != "WAITING-FOR-SESSION") {
               await Supabase.instance.client
                  .from('form_submission')
                  .update({'form_type': selectedForm})
                  .eq('id', _currentSessionId);
            }
          },
        ),
      ),
    );
  }

  Widget _buildHeaderButton(String label, IconData icon, {VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: AppColors.primaryBlue),
      label: Text(label, style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.buttonOutlineBlue),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}