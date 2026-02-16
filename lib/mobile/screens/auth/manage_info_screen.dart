import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart';
import 'package:sappiire/mobile/widgets/selectall_button.dart';
import 'package:sappiire/mobile/widgets/dropdown.dart';
import 'package:sappiire/mobile/widgets/save_button.dart';
import 'package:sappiire/resources/static_form_input.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageInfoScreen extends StatefulWidget {
  final String? userId;

  const ManageInfoScreen({super.key, this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  int _currentIndex = 0;
  bool _selectAll = false;
  bool _isEdited = false; // Tracks if user has changed anything
  String _selectedForm = "General Intake Sheet";
  String? _activeSessionId;
  Timer? _debounce;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _fieldChecks = {};

  final List<String> _allLabels = [
    "Last Name",
    "First Name",
    "Middle Name",
    "House number, street name, phase/purok",
    "Subdivision",
    "Barangay",
    "Kasarian",
    "Estadong Sibil",
    "Relihiyon",
    "CP Number",
    "Email Address",
    "Natapos o naabot sa pag-aaral",
    "Lugar ng Kapanganakan",
    "Trabaho/Pinagkakakitaan",
    "Kumpanyang Pinagtratrabuhan",
  ];

  @override
  void initState() {
    super.initState();

    for (final label in _allLabels) {
      _controllers[label] = TextEditingController();
      // Listen for changes to show the Save Button
      _controllers[label]!.addListener(_handleTextChange);
      _fieldChecks[label] = false;
    }

    if (widget.userId != null) {
      _loadUserProfile(widget.userId!);
    }
  }

  // Detects typing and triggers the Save Button appearance
  void _handleTextChange() {
    if (!_isEdited) {
      setState(() => _isEdited = true);
    }
    
    // Original sync logic
    if (_activeSessionId == null) return;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_activeSessionId != null) {
        syncDataToWeb(_activeSessionId!);
      }
    });
  }

  Future<void> _loadUserProfile(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();

      if (mounted) {
        setState(() {
          _controllers["First Name"]?.text = response['firstname'] ?? '';
          _controllers["Middle Name"]?.text = response['middle_name'] ?? '';
          _controllers["Last Name"]?.text = response['lastname'] ?? '';
          _controllers["Email Address"]?.text = response['email'] ?? '';
          _controllers["CP Number"]?.text = response['cellphone_number'] ?? '';
          // Reset edited state after initial load
          _isEdited = false; 
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> syncDataToWeb(String sessionId) async {
    final Map<String, String> formData = {};
    _controllers.forEach((key, controller) {
      formData[key] = controller.text;
    });

    try {
      await Supabase.instance.client
          .from('form_sessions')
          .update({'form_data': formData})
          .eq('id', sessionId);
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  Future<void> _logout() async {
    setState(() => _activeSessionId = null);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in _controllers.values) {
      controller.removeListener(_handleTextChange);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _logout,
        ),
        title: const Text(
          "Manage Information",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Column(
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
                      _buildSectionCard(
                        child: ClientInfoSection(
                          selectAll: _selectAll,
                          controllers: _controllers,
                          fieldChecks: _fieldChecks,
                          onCheckChanged: (key, val) {
                            setState(() {
                              _fieldChecks[key] = val;
                              _isEdited = true;
                            });
                          },
                        ),
                      ),
                      _buildSectionCard(
                        child: FamilyTable(
                          selectAll: _selectAll,
                          controllers: _controllers,
                        ),
                      ),
                      _buildSectionCard(
                        child: SocioEconomicSection(
                          selectAll: _selectAll,
                          controllers: _controllers,
                        ),
                      ),
                      _buildSectionCard(
                        child: SignatureSection(
                          controllers: _controllers,
                        ),
                      ),
                      const SizedBox(height: 100), // Space for floating buttons
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // 🔹 FLOATING BUTTON LAYER
          Positioned(
            bottom: 25,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isEdited) ...[
                  SaveButton(
                    onTap: () {
                      // No function for now as requested
                      setState(() => _isEdited = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Changes recognized (Functionality pending)"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                SelectAllButton(
                  isSelected: _selectAll,
                  onChanged: (v) {
                    setState(() {
                      _selectAll = v ?? false;
                      _fieldChecks.updateAll((key, value) => _selectAll);
                      _isEdited = true; 
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == 1) {
            final String? sessionId = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const QrScannerScreen()),
            );

            if (sessionId != null) {
              setState(() => _activeSessionId = sessionId);
              await syncDataToWeb(sessionId);
            }
          } else {
            setState(() => _currentIndex = index);
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
}