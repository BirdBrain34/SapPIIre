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
import 'package:sappiire/resources/signature_field.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/mobile/widgets/date_picker_helper.dart';
import 'package:sappiire/mobile/widgets/signature_helper.dart';
import 'package:sappiire/mobile/widgets/NextButton.dart';


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
  String _username = "Loading...";
  int _currentStep = 0;
  final ScrollController _scrollController = ScrollController();
  final SupabaseService _supabaseService = SupabaseService();
  int _currentIndex = 0;
  bool _selectAll = false;
  bool _isEdited = false;
  bool _isSaving = false;
  List<Offset?>? _capturedSignaturePoints;
  String? _savedSignatureBase64;
  String _selectedForm = "General Intake Sheet";
  List<Map<String, dynamic>> _familyMembers = [];
  final GlobalKey<FamilyTableState> _familyTableKey = GlobalKey<FamilyTableState>();

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
  String? _bloodType;

  // All labels for UI Sections
  final List<String> _allLabels = [
    "Last Name", "First Name", "Middle Name", "Date of Birth", "Age", "Kasarian", "Estadong Sibil",
    "Relihiyon", "CP Number", "Email Address", "Natapos o naabot sa pag-aaral",
    "Lugar ng Kapanganakan", "Lugar ng Kapanganakan / Place of Birth", "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
    "Buwanang Kita (A)",
    "House number, street name, phase/purok", "Subdivision", "Barangay",
    "Kasarian / Sex", "Uri ng Dugo / Blood Type", "Estadong Sibil / Martial Status",
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

  // This is the getter that tells Flutter which "Step" to show
// This is the getter that tells Flutter which "Step" to show
  List<Widget> get _formSections {
    if (_selectedForm == "General Intake Sheet") {
      return [
        // Index 0: Client Information
        ClientInfoSection(
          selectAll: _selectAll,
          controllers: _controllers,
          fieldChecks: _fieldChecks,
          onCheckChanged: (key, val) {
            setState(() {
              _fieldChecks[key] = val;
              _isEdited = true;
            });
          },
          membershipData: _membershipData,
          onMembershipChanged: (key, val) {
            setState(() {
              _membershipData[key] = val;
              _isEdited = true;
            });
          },
        ),

        // Index 1: Family Composition
        FamilyTable(
          key: _familyTableKey,
          selectAll: _selectAll,
          familyMembers: _familyMembers,
          onFamilyChanged: (newData) {
            setState(() {
              _familyMembers = newData;
              _isEdited = true;
            });
          },
        ),

        // Index 2: Socio-Economic Data
        SocioEconomicSection(
          selectAll: _selectAll,
          controllers: _controllers,
          hasSupport: _hasSupport,
          housingStatus: _housingStatus,
          supportingFamily: _supportingFamily,
          onHasSupportChanged: (val) => setState(() { _hasSupport = val; _isEdited = true; }),
          onHousingStatusChanged: (val) => setState(() { _housingStatus = val; _isEdited = true; }),
          onSupportingFamilyChanged: (newData) {
            setState(() {
              _supportingFamily = newData;
              _isEdited = true;
            });
          },
        ),
      ];
    } else if (_selectedForm == "Personal Info") {
      return [
        PersonalInfoSection(
          controllers: _controllers,
          selectAll: _selectAll,
          fieldChecks: _fieldChecks,
          onCheckChanged: (key, val) { 
            setState(() {
              _fieldChecks[key] = val;
              _isEdited = true;
            });
          },
          onDateTap: () => _selectDate(),
          onTextChanged: (val) {
            if (!_isEdited) setState(() => _isEdited = true);
          },
          onBloodTypeChanged: (val) {
            setState(() {
              _bloodType = val;
              _isEdited = true;
            });
          },
        )
      ];
    }
    return [const Center(child: Text("Select a form to begin"))];
  }



Future<void> _selectDate() async {
  await DatePickerHelper.selectDate(
    context: context,
    dateController: _controllers["Date of Birth"]!,
    ageController: _controllers["Age"],
  );
  setState(() => _isEdited = true);
}

void _changeStep(int newStep) {
  setState(() {
    _currentStep = newStep;
  });
  
  // Use postFrameCallback to wait for the new section to render, 
  // then scroll to the very top (position 0).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.fastOutSlowIn,
      );
    }
  });
}

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
      final data = widget.initialData!;

      _controllers["Last Name"]?.text = data.lastName;
      _controllers["First Name"]?.text = data.firstName;
      _controllers["Middle Name"]?.text = data.middleName;
      _controllers["Date of Birth"]?.text = data.dateOfBirth;
      _controllers["Kasarian"]?.text = data.sex;
      _controllers["Estadong Sibil"]?.text = data.maritalStatus;
      _controllers["Lugar ng Kapanganakan"]?.text = data.placeOfBirth;
      _controllers["House number, street name, phase/purok"]?.text = data.address;
    }

    // Load existing user profile if userId exists
    final String? effectiveId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (effectiveId != null) {
      _loadUserProfile(effectiveId);
    }
  }

  Future<void> _loadUserProfile(String userId) async {
  try {
    // 1. Fetch the username via the service
    final name = await _supabaseService.getUsername(userId);
    if (name != null && mounted) {
      setState(() => _username = name);
    }

      final response = await _supabaseService.loadUserProfile(userId);

      if (response != null && mounted) {
        setState(() {
          _controllers["First Name"]?.text = response['firstname'] ?? '';
          _controllers["Middle Name"]?.text = response['middle_name'] ?? '';
          _controllers["Last Name"]?.text = response['lastname'] ?? '';
          _controllers["Date of Birth"]?.text = response['birthdate'] ?? '';
          _controllers["Age"]?.text = response['age']?.toString() ?? '';
          _controllers["Email Address"]?.text = response['email'] ?? '';
          _controllers["CP Number"]?.text = response['cellphone_number'] ?? '';
          _controllers["Kasarian"]?.text = response['gender'] ?? '';
          _controllers["Kasarian / Sex"]?.text = response['gender'] ?? '';
          _bloodType = response['blood_type'];
          _controllers["Estadong Sibil"]?.text = response['civil_status'] ?? '';
          _controllers["Estadong Sibil / Martial Status"]?.text = response['civil_status'] ?? '';
          _controllers["Relihiyon"]?.text = response['religion'] ?? '';
          _controllers["Natapos o naabot sa pag-aaral"]?.text = response['education'] ?? '';
          _controllers["Lugar ng Kapanganakan"]?.text = response['birthplace'] ?? '';
          _controllers["Lugar ng Kapanganakan / Place of Birth"]?.text = response['birthplace'] ?? '';
          _controllers["Trabaho/Pinagkakakitaan"]?.text = response['occupation'] ?? '';
          _controllers["Kumpanyang Pinagtratrabuhan"]?.text = response['workplace'] ?? '';
          _controllers["Buwanang Kita (A)"]?.text = response['monthly_allowance']?.toString() ?? '';

          _membershipData['solo_parent'] = response['solo_parent'] ?? false;
          _membershipData['pwd'] = response['pwd'] ?? false;
          _membershipData['four_ps_member'] = response['four_ps_member'] ?? false;
          _membershipData['phic_member'] = response['phic_member'] ?? false;

          final addrData = response['user_addresses'];
          if (addrData != null && addrData is Map) {
            _controllers["House number, street name, phase/purok"]?.text = addrData['address_line'] ?? '';
            _controllers["Subdivision"]?.text = addrData['subdivision'] ?? '';
            _controllers["Barangay"]?.text = addrData['barangay'] ?? '';
          }

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

            _socioEconomicId = socioData['socio_economic_id']?.toString();
            final socioId = _socioEconomicId;
            

            if (socioId != null) {
              _loadSupportingFamily(socioId);
            }
          }

          _isEdited = false;
        });

        // Load signature if exists
        if (response['signature_data'] != null) {
          _savedSignatureBase64 = response['signature_data'];
          _capturedSignaturePoints = [];
          debugPrint('Signature loaded from database');
        }

        final String? profileId = response['profile_id'];
        if (profileId != null) {
          _loadFamilyComposition(profileId);
        }
      }
    } catch (e) {
      debugPrint('Load Error: $e');
    }
  }

  Future<void> _loadFamilyComposition(String profileId) async {
    try {
      final response = await _supabaseService.loadFamilyComposition(profileId);

      if (mounted) {
        setState(() {
          _familyMembers = response;
        });
      }
    } catch (e) {
      debugPrint('Load Family Composition Error: $e');
    }
  }

  Future<void> _loadSupportingFamily(String socioEconomicId) async {
    try {
      final response = await _supabaseService.loadSupportingFamily(socioEconomicId);

      if (mounted) {
        setState(() {
          _supportingFamily = response;
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
    final String? currentUserId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;

    if (currentUserId == null) {
      _showFeedback("Error: User session lost. Please login.", Colors.red);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final profileMap = {
        "Last Name": "lastname", "First Name": "firstname", "Middle Name": "middle_name",
        "Date of Birth": "birthdate", "Age": "age",
        "Kasarian": "gender", "Kasarian / Sex": "gender",
        "Estadong Sibil": "civil_status", "Estadong Sibil / Martial Status": "civil_status",
        "Relihiyon": "religion",
        "CP Number": "cellphone_number", "Email Address": "email",
        "Natapos o naabot sa pag-aaral": "education", "Lugar ng Kapanganakan": "birthplace", "Lugar ng Kapanganakan / Place of Birth": "birthplace",
        "Trabaho/Pinagkakakitaan": "occupation", "Kumpanyang Pinagtratrabuhan": "workplace",
        "Buwanang Kita (A)": "monthly_allowance"
      };
      final Map<String, dynamic> profileData = {};
      profileMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) {
          if (column == 'age') {
            profileData[column] = int.tryParse(value) ?? 0;
          } else {
            profileData[column] = value;
          }
        }
      });
      if (_bloodType != null) profileData['blood_type'] = _bloodType;

      final String profileId = await _supabaseService.saveUserProfile(
        userId: currentUserId,
        profileData: profileData,
        membershipData: _membershipData,
      );

      final addressMap = {
        "House number, street name, phase/purok": "address_line",
        "Subdivision": "subdivision", "Barangay": "barangay"
      };
      final Map<String, dynamic> addressData = {};
      addressMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) addressData[column] = value;
      });
      await _supabaseService.saveUserAddress(profileId, addressData);

      try {
        final familyData = _familyTableKey.currentState?.getFamilyData() ?? _familyMembers;
        final validFamilyRows = familyData.where((member) {
          final name = member['name']?.toString().trim() ?? '';
          final relationship = member['relationship_of_relative']?.toString().trim() ?? '';
          return name.isNotEmpty || relationship.isNotEmpty;
        }).toList();

        if (validFamilyRows.isNotEmpty) {
          final familyPayload = validFamilyRows.map((member) => {
            'name': member['name']?.toString().trim() ?? '',
            'relationship_of_relative': member['relationship_of_relative']?.toString().trim() ?? '',
            'birthdate': member['birthdate']?.toString().trim().isEmpty ?? true ? null : member['birthdate'],
            'age': member['age'] is int ? member['age'] : int.tryParse(member['age']?.toString() ?? '0') ?? 0,
            'gender': member['gender']?.toString().trim() ?? '',
            'civil_status': member['civil_status']?.toString().trim() ?? '',
            'education': member['education']?.toString().trim() ?? '',
            'occupation': member['occupation']?.toString().trim() ?? '',
            'allowance': member['allowance'] is num ? member['allowance'] : double.tryParse(member['allowance']?.toString().replaceAll(',', '') ?? '0') ?? 0,
          }).toList();

          await _supabaseService.saveFamilyComposition(profileId, familyPayload);
        }
      } catch (e) {
        debugPrint('Family Composition Save Error: $e');
      }

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
      final Map<String, dynamic> socioData = {
        'has_support': _hasSupport,
        'housing_status': _housingStatus,
      };
      socioMap.forEach((label, column) {
        final value = _controllers[label]?.text.trim() ?? '';
        if (value.isNotEmpty) {
          socioData[column] = (column == 'household_size') ? int.tryParse(value) ?? 1 : double.tryParse(value) ?? 0;
        }
      });

      _socioEconomicId = await _supabaseService.saveSocioEconomicData(profileId, socioData);

      if (_socioEconomicId != null && _hasSupport && _supportingFamily.isNotEmpty) {
        final monthlyAlimony = double.tryParse(_controllers["Kabuuang Tulong/Sustento kada Buwan (C)"]?.text.trim() ?? '') ?? 0;
        await _supabaseService.saveSupportingFamily(_socioEconomicId!, _supportingFamily, monthlyAlimony);
      }

      // Save signature
      try {
        if (_capturedSignaturePoints != null && _capturedSignaturePoints!.isNotEmpty) {
          final signatureBase64 = await SignatureHelper.convertToBase64(_capturedSignaturePoints!);
          
          if (signatureBase64 != null) {
            await Supabase.instance.client
                .from('user_profiles')
                .update({'signature_data': signatureBase64})
                .eq('profile_id', profileId);
            
            debugPrint('Signature saved successfully');
          }
        }
      } catch (e) {
        debugPrint('Signature save error: $e');
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
        toolbarHeight: 70, // Slightly taller to fit two lines comfortably
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 20),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => LogoutConfirmationDialog(onConfirm: _handleLogout),
            );
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Manage Information".toUpperCase(),
              style: const TextStyle(
                color: Colors.white70, 
                fontSize: 12, 
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500
              ),
            ),
            Text(
              _username,
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 18, 
                fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryBlue.withOpacity(0.05),
            padding: const EdgeInsets.all(16),
            child: FormDropdown(
              selectedForm: _selectedForm,
              items: const ["Personal Info", "General Intake Sheet", "Senior Citizen ID"],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedForm = val;
                    _currentStep = 0;
                    
                    // 1. Reset the Select All toggle
                    _selectAll = false;

                    // 2. Clear all previous checkboxes
                    // This ensures checks from "Personal Info" don't bleed into "GIS"
                    _fieldChecks.updateAll((key, value) => false);

                    _isEdited = true;
                  });
                }
              },
            ),
          ),
// Inside your build method:
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                // 1. Top Navigation & Progress
                if (_formSections.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Top BACK arrow
                        Opacity(
                          opacity: _currentStep > 0 ? 1.0 : 0.0, // Hidden but keeps spacing
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                            color: AppColors.primaryBlue,
                            onPressed: _currentStep > 0 ? () => _changeStep(_currentStep - 1) : null,
                          ),
                        ),
                        
                        const SizedBox(width: 15),
                        
                        Text(
                          "Page ${_currentStep + 1} of ${_formSections.length}",
                          style: TextStyle(
                            color: AppColors.primaryBlue, 
                            fontWeight: FontWeight.bold,
                            fontSize: 16
                          ),
                        ),

                        const SizedBox(width: 15),

                        // Top NEXT arrow
                        Opacity(
                          opacity: _currentStep < _formSections.length - 1 ? 1.0 : 0.0,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 20),
                            color: AppColors.primaryBlue,
                            onPressed: _currentStep < _formSections.length - 1 
                                ? () => _changeStep(_currentStep + 1) 
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Show ONLY the current section
                  _buildSectionCard(
                      child: _currentStep < _formSections.length 
                          ? _formSections[_currentStep] 
                          : _formSections[0] // Fallback to first step if index is out of bounds
                    ),

                  // 3. Navigation Row (Bottom Left)
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Bottom BACK arrow
                      if (_currentStep > 0)
                        IconButton(
                          onPressed: () => _changeStep(_currentStep - 1),
                          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                          color: AppColors.primaryBlue,
                        )
                      else
                        const SizedBox(width: 48),

                      const SizedBox(width: 10),

                      // Bottom NEXT arrow
                      if (_currentStep < _formSections.length - 1)
                        IconButton(
                          onPressed: () => _changeStep(_currentStep + 1),
                          icon: const Icon(Icons.arrow_forward_ios, size: 20),
                          color: AppColors.primaryBlue,
                        ),
                    ],
                  ),
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
              onChanged: (v) {
                setState(() {
                  _selectAll = v ?? false;
                  
                  // Get the keys that belong to the CURRENTLY visible section only
                  // This prevents background data from being modified accidentally
                  for (final label in _allLabels) {
                    _fieldChecks[label] = _selectAll;
                  }
                  
                  _isEdited = true;
                });
              },
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