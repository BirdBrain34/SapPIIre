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
import 'package:sappiire/mobile/widgets/InfoScannerButton.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/resources/GIS.dart';
import 'package:sappiire/resources/PersonalInfo.dart';


class ManageInfoScreen extends StatefulWidget {
  final String? userId;
  final IdInformation? initialData;

  const ManageInfoScreen({
    super.key,
    this.userId,
    this.initialData,
  });

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
  final Map<String, bool> _membershipData = {
    'solo_parent': false,
    'pwd': false,
    'four_ps_member': false,
    'phic_member': false,
  };
  bool _hasSupport = false;
  String? _housingStatus;
  List<Map<String, dynamic>> _supportingFamily = [];
  String? _socioEconomicId;

  // All labels for UI Sections
  final List<String> _allLabels = [
    // PII
    "Last Name", "First Name", "Middle Name", "Date of Birth","Kasarian", "Estadong Sibil",
    "Relihiyon", "CP Number", "Email Address", "Natapos o naabot sa pag-aaral",
    "Lugar ng Kapanganakan", "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
    "Buwanang Kita (A)",

    // Address
    "House number, street name, phase/purok", "Subdivision", "Barangay",

    // Socio-Economic
    "Kabuuang Tulong/Sustento kada Buwan (C)",
    "Total Gross Family Income (A+B+C)=(D)",
    "Household Size (E)",
    "Monthly Per Capita Income (D/E)",
    "Total Monthly Expense (F)",
    "Net Monthly Income (D-F)",
    "Bayad sa bahay",
    "Food items",
    "Non-food items",
    "Utility bills",
    "Baby's needs",
    "School needs",
    "Medical needs",
    "Transpo expense",
    "Loans",
    "Gasul"
  ];

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    for (final label in _allLabels) {
      _controllers[label] = TextEditingController();
      _controllers[label]!.addListener(() {
        if (!_isEdited) setState(() => _isEdited = true);
      });
      _fieldChecks[label] = false;
    }

    // Autofill from scanner if available
    if (widget.initialData != null) {
      _controllers["Last Name"]?.text = widget.initialData!.lastName;
      _controllers["First Name"]?.text = widget.initialData!.firstName;
      _controllers["Middle Name"]?.text = widget.initialData!.middleName;
      _controllers["House number, street name, phase/purok"]?.text = widget.initialData!.address;
    }

    // Load existing user profile if userId exists
    final String? effectiveId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (effectiveId != null) {
      _loadUserProfile(effectiveId);
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('*, user_addresses(*), socio_economic_data(*)')
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          // --- Profile ---
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
          _controllers["Buwanang Kita (A)"]?.text = response['monthly_allowance']?.toString() ?? '';

          // Membership
          _membershipData['solo_parent'] = response['solo_parent'] ?? false;
          _membershipData['pwd'] = response['pwd'] ?? false;
          _membershipData['four_ps_member'] = response['four_ps_member'] ?? false;
          _membershipData['phic_member'] = response['phic_member'] ?? false;

          // Address
          final addrData = response['user_addresses'];
          if (addrData != null && addrData is Map) {
            _controllers["House number, street name, phase/purok"]?.text = addrData['house_number'] ?? '';
            _controllers["Subdivision"]?.text = addrData['subdivision'] ?? '';
            _controllers["Barangay"]?.text = addrData['barangay'] ?? '';
          }

          // Socio-economic
          final socioData = response['socio_economic_data'];
          if (socioData != null && socioData is Map) {
            _hasSupport = socioData['has_support'] ?? false;
            _housingStatus = socioData['housing_status'];
            _socioEconomicId = socioData['socio_economic_id']?.toString();

            _controllers["Total Gross Family Income (A+B+C)=(D)"]?.text = socioData['gross_family_income']?.toString() ?? '';
            _controllers["Household Size (E)"]?.text = socioData['household_size']?.toString() ?? '';
            _controllers["Monthly Per Capita Income (D/E)"]?.text = socioData['monthly_per_capita']?.toString() ?? '';
            _controllers["Total Monthly Expense (F)"]?.text = socioData['monthly_expenses']?.toString() ?? '';
            _controllers["Net Monthly Income (D-F)"]?.text = socioData['net_monthly_income']?.toString() ?? '';
            _controllers["Bayad sa bahay"]?.text = socioData['house_rent']?.toString() ?? '';
            _controllers["Food items"]?.text = socioData['food_items']?.toString() ?? '';
            _controllers["Non-food items"]?.text = socioData['non_food_items']?.toString() ?? '';
            _controllers["Utility bills"]?.text = socioData['utility_bills']?.toString() ?? '';
            _controllers["Baby's needs"]?.text = socioData['baby_needs']?.toString() ?? '';
            _controllers["School needs"]?.text = socioData['school_needs']?.toString() ?? '';
            _controllers["Medical needs"]?.text = socioData['medical_needs']?.toString() ?? '';
            _controllers["Transpo expense"]?.text = socioData['transport_expenses']?.toString() ?? '';
            _controllers["Loans"]?.text = socioData['loans']?.toString() ?? '';
            _controllers["Gasul"]?.text = socioData['gas']?.toString() ?? '';

            // 1. Assign the ID to the class field first
            _socioEconomicId = socioData['socio_economic_id']?.toString();

            // 2. Create the local "shadow" variable for promotion
            final socioId = _socioEconomicId;

            // Load supporting family
            if (socioId != null) {
              _loadSupportingFamily(socioId);
            }
          }

          _isEdited = false;
        });
      }
    } catch (e) {
      debugPrint('Load Error: $e');
    }
  }

  Future<void> _loadSupportingFamily(String socioEconomicId) async {
    try {
      final response = await Supabase.instance.client
          .from('supporting_family')
          .select()
          .eq('socio_economic_id', socioEconomicId)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _supportingFamily = List<Map<String, dynamic>>.from(response);
          if (_supportingFamily.isNotEmpty && _supportingFamily[0]['monthly_alimony'] != null) {
            _controllers["Kabuuang Tulong/Sustento kada Buwan (C)"]?.text =
                _supportingFamily[0]['monthly_alimony'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Load Supporting Family Error: $e');
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
      // --- PROFILE ---
      final Map<String, dynamic> profileUpdate = {'user_id': currentUserId};
      final profileMap = {
        "Last Name": "lastname", "First Name": "firstname", "Middle Name": "middle_name",
        "Kasarian": "gender", "Estadong Sibil": "civil_status", "Relihiyon": "religion",
        "CP Number": "cellphone_number", "Email Address": "email",
        "Natapos o naabot sa pag-aaral": "education", "Lugar ng Kapanganakan": "birthplace",
        "Trabaho/Pinagkakakitaan": "occupation", "Kumpanyang Pinagtratrabuhan": "workplace",
        "Buwanang Kita (A)": "monthly_allowance"
      };
      profileMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) profileUpdate[column] = value;
      });
      profileUpdate.addAll(_membershipData);

      final profileRes = await supabase
          .from('user_profiles')
          .upsert(profileUpdate, onConflict: 'user_id')
          .select('profile_id')
          .single();

      final String profileId = profileRes['profile_id'];

      // --- ADDRESS ---
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

      // --- SOCIO-ECONOMIC ---
      final Map<String, dynamic> socioUpdate = {
        'profile_id': profileId,
        'has_support': _hasSupport,
        'housing_status': _housingStatus,
      };
      final socioMap = {
        "Total Gross Family Income (A+B+C)=(D)": "gross_family_income",
        "Household Size (E)": "household_size",
        "Monthly Per Capita Income (D/E)": "monthly_per_capita",
        "Total Monthly Expense (F)": "monthly_expenses",
        "Net Monthly Income (D-F)": "net_monthly_income",
        "Bayad sa bahay": "house_rent",
        "Food items": "food_items",
        "Non-food items": "non_food_items",
        "Utility bills": "utility_bills",
        "Baby's needs": "baby_needs",
        "School needs": "school_needs",
        "Medical needs": "medical_needs",
        "Transpo expense": "transport_expenses",
        "Loans": "loans",
        "Gasul": "gas"
      };
      socioMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) {
          socioUpdate[column] = (column == 'household_size') ? int.tryParse(value) ?? 1 : double.tryParse(value) ?? 0;
        }
      });

      final socioRes = await supabase
          .from('socio_economic_data')
          .upsert(socioUpdate, onConflict: 'profile_id')
          .select('socio_economic_id')
          .single();
      _socioEconomicId = socioRes['socio_economic_id']?.toString();

      // --- SUPPORTING FAMILY ---
      final currentSocioId = _socioEconomicId;
      if (currentSocioId != null) {
        if (_hasSupport && _supportingFamily.isNotEmpty) {
          // Use 'currentSocioId' instead of '_socioEconomicId'
          await supabase.from('supporting_family').delete().eq('socio_economic_id', currentSocioId);
          
          final monthlyAlimony = double.tryParse(_controllers["Kabuuang Tulong/Sustento kada Buwan (C)"]?.text.trim() ?? '') ?? 0;
          
          final supportList = _supportingFamily.asMap().entries.map((entry) {
            return {
              'socio_economic_id': currentSocioId, // Use local copy here too
              'name': entry.value['name'],
              'relationship': entry.value['relationship'],
              'regular_sustento': entry.value['regular_sustento'],
              'monthly_alimony': monthlyAlimony,
              'sort_order': entry.key,
            };
          }).where((item) => item['name'].toString().isNotEmpty).toList();

          if (supportList.isNotEmpty) {
            await supabase.from('supporting_family').insert(supportList);
          }
        } else if (!_hasSupport) {
          await supabase.from('supporting_family').delete().eq('socio_economic_id', currentSocioId);
        }
      }

      if (mounted) {
        setState(() { _isEdited = false; _isSaving = false; });
        _showFeedback("Profile saved successfully!", Colors.green);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      debugPrint("DB ERROR: $e");
      _showFeedback("Save Failed: ${e.toString()}", Colors.red);
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
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
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
              items: const ["Personal Info","General Intake Sheet", "Senior Citizen ID"],
              onChanged: (val) => setState(() => _selectedForm = val!),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_selectedForm == "Personal Info")
                  _buildSectionCard(
                    child: PersonalInfoSection(
                      selectAll: _selectAll,
                      controllers: _controllers,
                      fieldChecks: _fieldChecks,
                      onCheckChanged: (key, val) => setState(() {
                        _fieldChecks[key] = val;
                        _isEdited = true;
                      }),
                    ),
                  )
                  else ...[
                  _buildSectionCard(
                    child: ClientInfoSection(
                      selectAll: _selectAll,
                      controllers: _controllers,
                      fieldChecks: _fieldChecks,
                      membershipData: _membershipData,
                      onCheckChanged: (key, val) => setState(() { _fieldChecks[key] = val; _isEdited = true; }),
                      onMembershipChanged: (key, val) => setState(() { _membershipData[key] = val; _isEdited = true; }),
                    ),
                  ),
                  _buildSectionCard(child: FamilyTable(selectAll: _selectAll, controllers: _controllers)),
                  _buildSectionCard(
                    child: SocioEconomicSection(
                      selectAll: _selectAll,
                      controllers: _controllers,
                      hasSupport: _hasSupport,
                      housingStatus: _housingStatus,
                      supportingFamily: _supportingFamily,
                      onHasSupportChanged: (val) => setState(() {
                        _hasSupport = val;
                        if (!val) _supportingFamily.clear();
                        _isEdited = true;
                      }),
                      onHousingStatusChanged: (val) => setState(() { _housingStatus = val; _isEdited = true; }),
                      onSupportingFamilyChanged: (list) => setState(() { _supportingFamily = list; _isEdited = true; }),
                      onAddMember: () => setState(() => _isEdited = true),
                    ),
                  ),
                  _buildSectionCard(child: SignatureSection(controllers: _controllers)),
                  const SizedBox(height: 120),
                  ],
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
            // 1. ADD THE SCANNER BUTTON HERE
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoScannerButton(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
                  );
                },
              ),
            ),

            if (_isEdited)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _isSaving
                    ? const FloatingActionButton(
                        onPressed: null,
                        backgroundColor: Colors.grey,
                        child: CircularProgressIndicator(color: Colors.white),
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
        onTap: (i) async {
          if (i == 1) {
            final String? sessionId = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const QrScannerScreen()),
            );
            if (sessionId != null) {
              // You can call syncDataToWeb(sessionId) here if needed
            }
          } else {
            setState(() => _currentIndex = i);
          }
        },
      ),
    );
  }
}
