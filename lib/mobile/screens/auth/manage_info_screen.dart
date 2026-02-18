import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart';
import 'package:sappiire/mobile/widgets/selectall_button.dart';
import 'package:sappiire/mobile/widgets/dropdown.dart';
import 'package:sappiire/mobile/widgets/save_button.dart';
import 'package:sappiire/mobile/widgets/logout_confirmation_dialog.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Your custom section widgets
import 'package:sappiire/resources/static_form_input.dart'; 

class ManageInfoScreen extends StatefulWidget {
  final String? userId;
  const ManageInfoScreen({super.key, this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  int _currentIndex = 0;
  bool _selectAll = false;
  bool _isEdited = false; 
  bool _isSaving = false;
  String _selectedForm = "General Intake Sheet";

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _fieldChecks = {};

  // All labels for UI Sections
  final List<String> _allLabels = [
    // PII (Profile)
    "Last Name", "First Name", "Middle Name", "Kasarian", "Estadong Sibil", 
    "Relihiyon", "CP Number", "Email Address", "Natapos o naabot sa pag-aaral", 
    "Lugar ng Kapanganakan", "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
    
    // Address
    "House number, street name, phase/purok", "Subdivision", "Barangay",

    // Socio-Economic (Kept for UI, but not saving yet)
    "Household Size", "Monthly Expenses", "Net Monthly Income", "Gross Family Income"
  ];

  @override
  void initState() {
    super.initState();
    // 1. Initialize Controllers
    for (final label in _allLabels) {
      _controllers[label] = TextEditingController();
      _controllers[label]!.addListener(() {
        if (!_isEdited) setState(() => _isEdited = true);
      });
      _fieldChecks[label] = false;
    }
    
    // 2. Load Existing Data
    final String? effectiveId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (effectiveId != null) {
      _loadUserProfile(effectiveId);
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    try {
      // We only strictly need profile + address for now
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('*, user_addresses(*)') 
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          // --- Load Profile ---
          _controllers["First Name"]?.text = response['firstname'] ?? '';
          _controllers["Middle Name"]?.text = response['middle_name'] ?? '';
          _controllers["Last Name"]?.text = response['lastname'] ?? '';
          _controllers["Email Address"]?.text = response['email'] ?? '';
          _controllers["CP Number"]?.text = response['cellphone_number'] ?? '';
          _controllers["Kasarian"]?.text = response['gender'] ?? '';
          _controllers["Estadong Sibil"]?.text = response['civil_status'] ?? '';
          _controllers["Relihiyon"]?.text = response['religion'] ?? '';
          _controllers["Natapos o naabot sa pag-aaral"]?.text = response['education'] ?? '';
          _controllers["Lugar ng Kapanganakan"]?.text = response['birthplace'] ?? '';
          _controllers["Trabaho/Pinagkakakitaan"]?.text = response['occupation'] ?? '';
          _controllers["Kumpanyang Pinagtratrabuhan"]?.text = response['workplace'] ?? '';

          // --- Load Address ---
          final addrList = response['user_addresses'] as List?;
          if (addrList != null && addrList.isNotEmpty) {
            final addr = addrList[0];
            _controllers["House number, street name, phase/purok"]?.text = addr['house_number'] ?? '';
            _controllers["Subdivision"]?.text = addr['subdivision'] ?? '';
            _controllers["Barangay"]?.text = addr['barangay'] ?? '';
          }
          
          _isEdited = false; 
        });
      }
    } catch (e) {
      debugPrint('Load Error: $e');
    }
  }

  Future<void> _handleSave() async {
    final supabase = Supabase.instance.client;
    final String? currentUserId = widget.userId ?? supabase.auth.currentUser?.id;

    if (currentUserId == null) {
       _showFeedback("Error: User session lost. Please login.", Colors.red);
       return;
    }

    setState(() => _isSaving = true);

    try {
      // --- 1. PREPARE PROFILE DATA ---
      final Map<String, dynamic> profileUpdate = {'user_id': currentUserId};
      final profileMap = {
        "Last Name": "lastname", "First Name": "firstname", "Middle Name": "middle_name",
        "Kasarian": "gender", "Estadong Sibil": "civil_status", "Relihiyon": "religion",
        "CP Number": "cellphone_number", "Email Address": "email",
        "Natapos o naabot sa pag-aaral": "education", "Lugar ng Kapanganakan": "birthplace",
        "Trabaho/Pinagkakakitaan": "occupation", "Kumpanyang Pinagtratrabuhan": "workplace"
      };

      // Save all fields that have content
      profileMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) profileUpdate[column] = value;
      });

      // --- SAVE PROFILE ---
      final profileRes = await supabase
          .from('user_profiles')
          .upsert(profileUpdate, onConflict: 'user_id')
          .select('profile_id')
          .single();
      
      final String profileId = profileRes['profile_id'];

      // --- 2. PREPARE ADDRESS DATA ---
      final Map<String, dynamic> addressUpdate = {'profile_id': profileId};
      final addressMap = {
        "House number, street name, phase/purok": "house_number",
        "Subdivision": "subdivision", "Barangay": "barangay"
      };

      bool saveAddress = false;
      addressMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) {
          addressUpdate[column] = value;
          saveAddress = true;
        }
      });

      if (saveAddress) {
        await supabase.from('user_addresses').upsert(addressUpdate, onConflict: 'profile_id');
      }

      if (mounted) {
        setState(() { _isEdited = false; _isSaving = false; });
        _showFeedback("Profile saved successfully!", Colors.green);
      }

    } catch (e) {
      setState(() => _isSaving = false);
      debugPrint("FULL DB ERROR: $e");

      String msg = e.toString();
      if (msg.contains("unique constraint")) {
        msg = "Database Error: Duplicate entry conflict. Check 'user_id' uniqueness.";
      } else if (msg.contains("value too long")) {
        msg = "Database Error: Text too long (e.g. Gender field).";
      } else if (msg.contains("23502")) {
        msg = "Database Error: Missing required field (Not Null).";
      }
      
      _showFeedback("Save Failed: $msg", Colors.red);
    }
  }

  void _showFeedback(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _handleLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        title: const Text("Manage Information", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => LogoutConfirmationDialog(onConfirm: _handleLogout),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryBlue.withOpacity(0.05),
            padding: const EdgeInsets.all(16),
            child: FormDropdown(
              selectedForm: _selectedForm,
              items: const ["General Intake Sheet", "Senior Citizen ID"],
              onChanged: (val) => setState(() => _selectedForm = val!),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSectionCard(child: ClientInfoSection(
                    selectAll: _selectAll,
                    controllers: _controllers,
                    fieldChecks: _fieldChecks,
                    onCheckChanged: (key, val) => setState(() {
                      _fieldChecks[key] = val;
                      _isEdited = true;
                    }),
                  )),
                  
                  // KEEPING UI VISIBLE - But data won't save yet
                  _buildSectionCard(child: FamilyTable(selectAll: _selectAll, controllers: _controllers)),
                  
                  // KEEPING UI VISIBLE - But data won't save yet
                  _buildSectionCard(child: SocioEconomicSection(
                    selectAll: _selectAll, 
                    controllers: _controllers,
                  )),
                  
                  _buildSectionCard(child: SignatureSection(controllers: _controllers)),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
             if (_isEdited) 
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _isSaving 
                  ? const FloatingActionButton(
                      onPressed: null, 
                      backgroundColor: Colors.grey, 
                      child: CircularProgressIndicator(color: Colors.white)
                    )
                  : SaveButton(onTap: _handleSave),
              ),
            SelectAllButton(
              isSelected: _selectAll,
              onChanged: (v) => setState(() {
                _selectAll = v ?? false;
                _fieldChecks.updateAll((key, val) => _selectAll);
                _isEdited = true;
              }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QrScannerScreen()),
            );
          } else {
            setState(() => _currentIndex = i);
          }
        },
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}