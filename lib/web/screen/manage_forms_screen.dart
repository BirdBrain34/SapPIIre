import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/side_menu.dart';
import 'package:sappiire/resources/static_form_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageFormsScreen extends StatefulWidget {
  const ManageFormsScreen({super.key});

  @override
  State<ManageFormsScreen> createState() => _ManageFormsScreenState();
}

class _ManageFormsScreenState extends State<ManageFormsScreen> {
  String selectedForm = "General Intake Sheet";
  final Map<String, TextEditingController> _webControllers = {};
  String _currentSessionId = "WAITING-FOR-SESSION";
  StreamSubscription? _formSubscription;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _createNewSession();
  }

  void _initializeControllers() {
    final List<String> allLabels = [
      "Last Name", "First Name", "Middle Name",
      "House number, street name, phase/purok", "Subdivision", "Barangay",
      "Kasarian", "Estadong Sibil", "Relihiyon", "CP Number", "Email Address",
      "Natapos o naabot sa pag-aaral", "Lugar ng Kapanganakan",
      "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
      "Buwanang Kita (A)", "Total Gross Family Income (A+B+C)=(D)",
      "Household Size (E)", "Monthly Per Capita Income (D/E)",
      "Total Monthly Expense (F)", "Net Monthly Income (D-F)",
      "Bayad sa bahay", "Food items", "Non-food items", "Utility bills",
      "Baby's needs", "School needs", "Medical needs", "Transpo expense",
      "Loans", "Gasul"
    ];

    for (var label in allLabels) {
      _webControllers[label] = TextEditingController();
    }
  }

  // 🔹 FIX: Clear UI when starting a new session
  void _clearAllFields() {
    for (var controller in _webControllers.values) {
      controller.clear();
    }
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
      _clearAllFields(); // 🔹 Clear the screen for the new client
      
      final response = await Supabase.instance.client
          .from('form_sessions')
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
        .from('form_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .listen((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty) {
        final Map<String, dynamic> incomingData = data.first['form_data'] ?? {};

        setState(() {
          incomingData.forEach((key, value) {
            if (_webControllers.containsKey(key)) {
              if (_webControllers[key]!.text != value.toString()) {
                _webControllers[key]!.text = value.toString();
              }
            }
          });
        });
      }
    });
  }

  Future<void> _finalizeEntry() async {
    final Map<String, String> finalData = {};
    _webControllers.forEach((key, controller) {
      finalData[key] = controller.text;
    });

    try {
      await Supabase.instance.client.from('client_submissions').insert({
        'form_type': selectedForm,
        'data': finalData,
        'created_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client
          .from('form_sessions')
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FE),
      body: Row(
        children: [
          const SideMenu(activePath: "Forms"),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(35.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Forms Management",
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                      ),
                      _buildHeaderButton(
                        "Reset Form / New QR",
                        Icons.refresh,
                        onPressed: _createNewSession,
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
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
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(vertical: 30),
                                child: Column(
                                  children: [
                                    ClientInfoSection(selectAll: false, controllers: _webControllers),
                                    const SizedBox(height: 40),
                                    FamilyTable(selectAll: false, controllers: _webControllers),
                                    const SizedBox(height: 40),
                                    SocioEconomicSection(selectAll: false, controllers: _webControllers),
                                    const SizedBox(height: 40),
                                    const SignatureSection(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: ElevatedButton(
                      onPressed: _finalizeEntry, // 🔹 FIXED: Connected the logic
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("FINALIZE & SAVE ENTRY",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
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
            
            // 🔹 FIX: Update session in database so Mobile knows form type changed
            if (_currentSessionId != "WAITING-FOR-SESSION") {
               await Supabase.instance.client
                  .from('form_sessions')
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