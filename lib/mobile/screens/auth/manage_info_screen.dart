// Mobile Manage Info Screen
// Main screen for mobile users to manage their personal information.
//
// Flow:
// 1. Loads form templates from Supabase
// 2. Loads user profile data and autofills form
// 3. User can edit data and save to Supabase
// 4. User can select fields and transmit via QR code to web
//
// UI Structure:
// - AppBar: Logout (left), Camera + Save buttons (right)
// - Form: Dynamic form renderer with field selection checkboxes
// - Bottom Nav: Manage Info, Autofill QR, History
// - FAB: Select All / Deselect All fields

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
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart';

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
  int _currentNavIndex = 0;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _formCtrl?.dispose();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('ManageInfoScreen: Loading templates...');
      final templates =
          await _templateService.fetchActiveTemplates(forceRefresh: true);
      debugPrint('Received ${templates.length} templates');

      final profileData =
          await _supabaseService.loadUserProfile(widget.userId);
      final username = await _supabaseService.getUsername(widget.userId);

      setState(() {
        _templates = templates;
        _username = username ?? '';
        _selectedTemplate = templates.isNotEmpty
            ? (templates.firstWhere(
                (t) => t.formName == 'General Intake Sheet',
                orElse: () => templates.first))
            : null;
      });

      debugPrint(
          'Selected template: ${_selectedTemplate?.formName ?? "NONE"}');

      if (_selectedTemplate != null) {
        _initFormController(profileData);
      }
    } catch (e, stack) {
      debugPrint('ManageInfoScreen._loadAll error: $e');
      debugPrint('Stack: $stack');
    }
    setState(() => _isLoading = false);
  }

  void _initFormController(Map<String, dynamic>? profileData) {
    _formCtrl?.dispose();
    final ctrl = FormStateController(template: _selectedTemplate!);

    if (profileData != null) {
      debugPrint('Autofilling from profile...');
      final address =
          (profileData['user_addresses'] as Map<String, dynamic>?) ?? {};
      final socio =
          (profileData['socio_economic_data'] as Map<String, dynamic>?) ?? {};

      final autofillData = _templateService.buildAutofillMap(
        template: _selectedTemplate!,
        profile: profileData,
        address: address,
        socio: socio,
        family: [],
        supporting: [],
      );
      
      // Load signature from profile
      if (profileData['signature_data'] != null) {
        autofillData['__signature'] = profileData['signature_data'];
        ctrl.signatureBase64 = profileData['signature_data'];
      }
      
      debugPrint('Autofill data keys: ${autofillData.keys.toList()}');
      ctrl.loadFromJson(autofillData);
    }

    setState(() => _formCtrl = ctrl);

    if (profileData?['profile_id'] != null) {
      _loadComplexData(profileData!['profile_id'], profileData);
    }
  }

  Future<void> _loadComplexData(
      String profileId, Map<String, dynamic> profileData) async {
    final family = await _supabaseService.loadFamilyComposition(profileId);
    final socio =
        (profileData['socio_economic_data'] as Map<String, dynamic>?) ?? {};
    final socioId = socio['socio_economic_id']?.toString();
    final supporting = socioId != null
        ? await _supabaseService.loadSupportingFamily(socioId)
        : <Map<String, dynamic>>[];

    if (!mounted) return;

    _formCtrl?.familyMembers = family
        .map((m) => {
              'name': m['name'] ?? '',
              'relationship': m['relationship_of_relative'] ?? '',
              'birthdate': m['birthdate']?.toString() ?? '',
              'age': m['age']?.toString() ?? '',
              'gender': m['gender'] ?? '',
              'civil_status': m['civil_status'] ?? '',
              'education': m['education'] ?? '',
              'occupation': m['occupation'] ?? '',
              'allowance': m['allowance']?.toString() ?? '',
            })
        .toList();

    _formCtrl?.supportingFamily = supporting
        .map((m) => {
              'name': m['name'] ?? '',
              'relationship': m['relationship'] ?? '',
              'regular_sustento': m['regular_sustento']?.toString() ?? '',
            })
        .toList();

    // Load monthly_alimony (C) from first supporting family member
    if (supporting.isNotEmpty && supporting.first['monthly_alimony'] != null) {
      final monthlyAlimony = supporting.first['monthly_alimony'].toString();
      final alimonyField = _formCtrl?.template.fieldByName('monthly_alimony');
      if (alimonyField != null && _formCtrl != null) {
        _formCtrl!.setValue('monthly_alimony', monthlyAlimony, notify: false);
      }
    }

    _formCtrl?.hasSupport = (socio['has_support'] as bool?) ?? false;
    _formCtrl?.housingStatus = socio['housing_status']?.toString();

    // Recompute fields now that family data is loaded
    _formCtrl?.recomputeFromFamilyChange();
  }

  // ── Save to Supabase ──────────────────────────────────────
  Future<void> _saveProfile() async {
    if (_formCtrl == null) return;
    setState(() => _isSaving = true);
    try {
      final data = _formCtrl!.toJson();

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
          if (src == 'age') {
            profileData[src] = int.tryParse(val.toString()) ?? 0;
          } else {
            profileData[src] = val;
          }
        }
      }

      if (data['__signature'] != null) {
        profileData['signature_data'] = data['__signature'];
        _formCtrl!.signatureBase64 = data['__signature'];
      }

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
        _formCtrl!.familyMembers
            .map((m) => {
                  'name': m['name'] ?? '',
                  'relationship_of_relative': m['relationship'] ?? '',
                  'birthdate': m['birthdate'],
                  'age': int.tryParse(m['age']?.toString() ?? '0') ?? 0,
                  'gender': m['gender'] ?? '',
                  'civil_status': m['civil_status'] ?? '',
                  'education': m['education'] ?? '',
                  'occupation': m['occupation'] ?? '',
                  'allowance': double.tryParse(m['allowance']
                              ?.toString()
                              .replaceAll(',', '') ??
                          '0') ??
                      0,
                })
            .toList(),
      );

      if (socioData.isNotEmpty) {
        socioData['housing_status'] = _formCtrl!.housingStatus ?? '';
        socioData['has_support'] = _formCtrl!.hasSupport;
        final socioId = await _supabaseService.saveSocioEconomicData(
            profileId, socioData);
        await _supabaseService.saveSupportingFamily(
          socioId,
          _formCtrl!.supportingFamily,
          double.tryParse(
                  data['monthly_alimony']?.toString() ?? '0') ??
              0,
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

  // ── QR Transmit ───────────────────────────────────────────
  Future<void> _scanAndTransmit() async {
    if (_formCtrl == null) return;

    // Check if at least one checkbox is selected
    final hasAnyChecked = _formCtrl!.selectAll || 
        _formCtrl!.fieldChecks.values.any((checked) => checked == true);
    
    if (!hasAnyChecked) {
      _showFeedback('Please select at least one field to transmit', AppColors.dangerRed);
      return;
    }

    final dataToTransmit = _formCtrl!.toFilteredJson();
    debugPrint('Data to transmit: ${dataToTransmit.keys.toList()}');
    debugPrint('Data size: ${dataToTransmit.length} fields');

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
      debugPrint('Sending to session: $sessionId');
      final success = await _supabaseService.sendDataToWebSession(
        sessionId,
        dataToTransmit,
      );
      debugPrint('Transmission result: $success');
      _showFeedback(
        success ? 'Data transmitted!' : 'Failed to send data.',
        success ? Colors.green : Colors.red,
      );
    }
  }

  // ── Logout ────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerRed,
            ),
            child: const Text('Log Out',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ── Navigation ────────────────────────────────────────────
  void _onNavTap(int index) {
    switch (index) {
      case 0:
        setState(() => _currentNavIndex = 0);
        break;
      case 1:
        // AutoFill QR — transmit selected fields
        setState(() => _currentNavIndex = 1);
        _scanAndTransmit().then((_) {
          if (mounted) setState(() => _currentNavIndex = 0);
        });
        break;
      case 2:
        // Form History — placeholder until screen is built
        setState(() => _currentNavIndex = 2);
        _showFeedback('Form History coming soon!', AppColors.primaryBlue);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _currentNavIndex = 0);
        });
        break;
    }
  }

  // ── Camera Scanner ────────────────────────────────────────
  Future<void> _openCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
    );
  }

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: _buildAppBar(),
      floatingActionButton: _formCtrl != null ? _buildSelectAllFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _buildEmptyState()
              : _buildFormContent(),
    );
  }

  // ── AppBar: logout left, camera + save right ──────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 22),
        onPressed: _handleLogout,
        tooltip: 'Log out',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Welcome back,',
                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w400),
              ),
              Text(
                _username.isEmpty ? 'User' : _username,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 22),
          onPressed: _openCamera,
          tooltip: 'Scan ID',
        ),
        IconButton(
          icon: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
          onPressed: _isSaving ? null : _saveProfile,
          tooltip: 'Save Profile',
        ),
        const SizedBox(width: 8),
      ],
    );
  }



  // ── Empty / error state ───────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'No forms available.',
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
    );
  }

  // ── Main form content ─────────────────────────────────────
  Widget _buildFormContent() {
    return Column(
      children: [
        _buildFormSelector(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            child: _formCtrl == null
                ? const Center(child: CircularProgressIndicator())
                : AnimatedBuilder(
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
      ],
    );
  }

  Widget _buildFormSelector() {
    return Container(
      color: AppColors.primaryBlue.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Form:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDDDDEE)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTemplate?.templateId,
                  items: _templates
                      .map((t) => DropdownMenuItem(
                            value: t.templateId,
                            child: Text(
                              t.formName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ))
                      .toList(),
                  onChanged: (id) async {
                    final tpl =
                        _templates.firstWhere((t) => t.templateId == id);
                    setState(() => _selectedTemplate = tpl);
                    final profile =
                        await _supabaseService.loadUserProfile(widget.userId);
                    _initFormController(profile);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Select All Button ────────────────────────────────
  Widget _buildSelectAllFAB() {
    final isSelectAll = _formCtrl?.selectAll ?? false;
    return FloatingActionButton.extended(
      onPressed: () {
        _formCtrl?.setSelectAll(!isSelectAll);
        setState(() {});
      },
      backgroundColor: isSelectAll ? AppColors.highlight : AppColors.primaryBlue,
      elevation: 6,
      icon: Icon(
        isSelectAll ? Icons.deselect_rounded : Icons.select_all_rounded,
        color: Colors.white,
        size: 20,
      ),
      label: Text(
        isSelectAll ? 'Deselect All' : 'Select All',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── Bottom nav: 3 items with increased height ─────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.edit_document, 'Manage Info'),
              _buildNavItem(1, Icons.qr_code_scanner, 'Autofill QR'),
              _buildNavItem(2, Icons.history, 'History'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentNavIndex == index;
    return InkWell(
      onTap: () => _onNavTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == 1)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  icon,
                  color: isActive ? AppColors.highlight : AppColors.primaryBlue,
                  size: 24,
                ),
              )
            else
              Icon(
                icon,
                color: isActive ? AppColors.highlight : Colors.white60,
                size: 24,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.highlight : Colors.white60,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}