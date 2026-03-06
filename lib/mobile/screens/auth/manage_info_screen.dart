// lib/mobile/screens/auth/manage_info_screen.dart
// REFACTORED: Now dynamically loads any form template from Supabase.
// No longer imports lib/resources/GIS.dart.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';

class ManageInfoScreen extends StatefulWidget {
  final String userId;
  const ManageInfoScreen({super.key, required this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  final _templateService = FormTemplateService();
  final _supabaseService = SupabaseService();

  List<FormTemplate> _templates = [];
  FormTemplate? _selectedTemplate;
  FormStateController? _formCtrl;

  bool _isLoading = true;
  bool _isSaving = false;
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🚀 ManageInfoScreen: Loading templates...');
      // 1. Load available templates
      final templates = await _templateService.fetchActiveTemplates(forceRefresh: true);
      debugPrint('📊 Received ${templates.length} templates');

      // 2. Load saved user profile for autofill
      final profileData = await _supabaseService.loadUserProfile(widget.userId);
      final username = await _supabaseService.getUsername(widget.userId);

      setState(() {
        _templates = templates;
        _username = username ?? '';
        // Default to GIS
        _selectedTemplate = templates.isNotEmpty
            ? (templates.firstWhere(
                (t) => t.formName == 'General Intake Sheet',
                orElse: () => templates.first))
            : null;
      });

      debugPrint('✅ Selected template: ${_selectedTemplate?.formName ?? "NONE"}');

      if (_selectedTemplate != null) {
        _initFormController(profileData);
      }
    } catch (e, stack) {
      debugPrint('❌ ManageInfoScreen._loadAll error: $e');
      debugPrint('Stack: $stack');
    }
    setState(() => _isLoading = false);
  }

  void _initFormController(Map<String, dynamic>? profileData) {
    _formCtrl?.dispose();
    final ctrl = FormStateController(template: _selectedTemplate!);

    if (profileData != null) {
      debugPrint('📝 Autofilling from profile...');
      // Pre-populate from saved profile
      final address = (profileData['user_addresses'] as Map<String, dynamic>?) ?? {};
      final socio = (profileData['socio_economic_data'] as Map<String, dynamic>?) ?? {};

      final autofillData = _templateService.buildAutofillMap(
        template: _selectedTemplate!,
        profile: profileData,
        address: address,
        socio: socio,
        family: [],
        supporting: [],
      );
      debugPrint('✅ Autofill data keys: ${autofillData.keys.toList()}');
      ctrl.loadFromJson(autofillData);
    }

    setState(() => _formCtrl = ctrl);

    // Load family + supporting family separately
    if (profileData?['profile_id'] != null) {
      _loadComplexData(profileData!['profile_id'], profileData);
    }
  }

  Future<void> _loadComplexData(String profileId, Map<String, dynamic> profileData) async {
    final family = await _supabaseService.loadFamilyComposition(profileId);
    final socio = (profileData['socio_economic_data'] as Map<String, dynamic>?) ?? {};
    final socioId = socio['socio_economic_id']?.toString();
    final supporting = socioId != null
        ? await _supabaseService.loadSupportingFamily(socioId)
        : <Map<String, dynamic>>[];

    if (!mounted) return;
    _formCtrl?.familyMembers = family.map((m) => {
      'name': m['name'] ?? '',
      'relationship': m['relationship_of_relative'] ?? '',
      'birthdate': m['birthdate']?.toString() ?? '',
      'age': m['age']?.toString() ?? '',
      'gender': m['gender'] ?? '',
      'civil_status': m['civil_status'] ?? '',
      'education': m['education'] ?? '',
      'occupation': m['occupation'] ?? '',
      'allowance': m['allowance']?.toString() ?? '',
    }).toList();

    _formCtrl?.supportingFamily = supporting.map((m) => {
      'name': m['name'] ?? '',
      'relationship': m['relationship'] ?? '',
      'regular_sustento': m['regular_sustento']?.toString() ?? '',
    }).toList();

    _formCtrl?.hasSupport = (socio['has_support'] as bool?) ?? false;
    _formCtrl?.housingStatus = socio['housing_status']?.toString();

    _formCtrl?.notifyListeners();
  }

  // ── Save profile to Supabase ──────────────────────────────
  Future<void> _saveProfile() async {
    if (_formCtrl == null) return;
    setState(() => _isSaving = true);
    try {
      final data = _formCtrl!.toJson();

      // Map dynamic field names back to Supabase column names
      final profileData = <String, dynamic>{};
      final addressData = <String, dynamic>{};
      final socioData = <String, dynamic>{};

      for (final field in _selectedTemplate!.allFields) {
        final src = field.autofillSource;
        if (src == null) continue;
        final val = data[field.fieldName];
        if (val == null || val.toString().isEmpty) continue;

        if (src.startsWith('address.')) {
          addressData[src.substring('address.'.length)] = val;
        } else if (src.startsWith('socio.')) {
          socioData[src.substring('socio.'.length)] = val;
        } else if (src == 'signature_data') {
          profileData['signature_data'] = val;
        } else {
          // Direct profile column
          if (src == 'age') {
            profileData[src] = int.tryParse(val.toString()) ?? 0;
          } else {
            profileData[src] = val;
          }
        }
      }

      // Membership booleans
      final membership = _formCtrl!.membershipData;
      profileData.addAll(membership);

      final profileId = await _supabaseService.saveUserProfile(
        userId: widget.userId,
        profileData: profileData,
        membershipData: membership,
      );

      await _supabaseService.saveUserAddress(profileId, addressData);
      await _supabaseService.saveFamilyComposition(
        profileId,
        _formCtrl!.familyMembers.map((m) => {
          'name': m['name'] ?? '',
          'relationship_of_relative': m['relationship'] ?? '',
          'birthdate': m['birthdate'],
          'age': int.tryParse(m['age']?.toString() ?? '0') ?? 0,
          'gender': m['gender'] ?? '',
          'civil_status': m['civil_status'] ?? '',
          'education': m['education'] ?? '',
          'occupation': m['occupation'] ?? '',
          'allowance': double.tryParse(m['allowance']?.toString().replaceAll(',', '') ?? '0') ?? 0,
        }).toList(),
      );

      if (socioData.isNotEmpty) {
        socioData['housing_status'] = _formCtrl!.housingStatus ?? '';
        socioData['has_support'] = _formCtrl!.hasSupport;
        final socioId = await _supabaseService.saveSocioEconomicData(profileId, socioData);
        await _supabaseService.saveSupportingFamily(
          socioId,
          _formCtrl!.supportingFamily,
          double.tryParse(data['monthly_alimony']?.toString() ?? '0') ?? 0,
        );
      }

      if (mounted) {
        _showFeedback('Profile saved!', Colors.green);
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) _showFeedback('Save failed: $e', Colors.red);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  // ── QR share selected fields ──────────────────────────────
  Future<void> _scanAndTransmit() async {
    if (_formCtrl == null) return;

    final dataToTransmit = _formCtrl!.toFilteredJson();

    final sessionId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          transmitData: dataToTransmit,
          userId: widget.userId,
        ),
      ),
    );

    if (sessionId != null && mounted) {
      final success = await _supabaseService.sendDataToWebSession(
        sessionId,
        dataToTransmit,
      );
      _showFeedback(
        success ? 'Data transmitted!' : 'Failed to send data.',
        success ? Colors.green : Colors.red,
      );
    }
  }

  void _showFeedback(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _formCtrl?.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FE),
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MY PROFILE',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500)),
            Text(_username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Save button
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, color: Colors.white),
            onPressed: _isSaving ? null : _saveProfile,
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                      ),
                      child: const Text('Logout', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue))
          : _selectedTemplate == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'No forms available',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please ensure the "General Intake Sheet" template is created in Supabase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ── Form selector dropdown ──────────────────
                    Container(
                      color: AppColors.primaryBlue.withOpacity(0.05),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text('Form:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFDDDDEE)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedTemplate!.templateId,
                                  items: _templates
                                      .map((t) => DropdownMenuItem(
                                            value: t.templateId,
                                            child: Text(t.formName,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ))
                                      .toList(),
                                  onChanged: (id) async {
                                    final tpl = _templates.firstWhere(
                                        (t) => t.templateId == id);
                                    setState(() {
                                      _selectedTemplate = tpl;
                                    });
                                    final profile =
                                        await _supabaseService
                                            .loadUserProfile(widget.userId);
                                    _initFormController(profile);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Dynamic form ────────────────────────────
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: AnimatedBuilder(
                          animation: _formCtrl!,
                          builder: (context, _) => DynamicFormRenderer(
                            template: _selectedTemplate!,
                            controller: _formCtrl!,
                            mode: 'mobile',
                            showCheckboxes: true,
                          ),
                        ),
                      ),
                    ),

                    // ── Bottom actions ──────────────────────────
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Select All
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                _formCtrl?.setSelectAll(!(_formCtrl?.selectAll ?? false));
                setState(() {});
              },
              icon: const Icon(Icons.select_all, size: 16),
              label: Text(
                _formCtrl?.selectAll ?? false
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Scan & Share
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _scanAndTransmit,
              icon: const Icon(Icons.qr_code_scanner,
                  color: Colors.white, size: 18),
              label: const Text('Scan & Share',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
