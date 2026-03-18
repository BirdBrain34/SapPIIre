// Mobile Manage Info Screen
// Loads templates + profile, renders dynamic form, saves to Supabase,
// and transmits selected fields to the web portal via QR.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/supabase_service.dart';
import '../../../services/field_value_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart';
import 'package:sappiire/mobile/screens/auth/ProfileScreen.dart';
import 'package:sappiire/mobile/screens/auth/HistoryScreen.dart';

class ManageInfoScreen extends StatefulWidget {
  final String userId;
  const ManageInfoScreen({super.key, required this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  final _templateService = FormTemplateService();
  final _supabaseService = SupabaseService();
  final _fieldValueService = FieldValueService();

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
    final previousTemplateId = _selectedTemplate?.templateId;
    // Only show full-screen spinner on first load, not on pull-to-refresh
    final isFirstLoad = _templates.isEmpty && _selectedTemplate == null;
    if (isFirstLoad) setState(() => _isLoading = true);
    try {
      debugPrint('ManageInfoScreen: Loading templates...');
      final templates =
          await _templateService.fetchActiveTemplates(forceRefresh: true);
      debugPrint('Received ${templates.length} templates');

      final profileData =
          await _supabaseService.loadUserProfile(widget.userId);
      final username = await _supabaseService.getUsername(widget.userId);

      if (!mounted) return;
      setState(() {
        _templates = templates;
        _username = username ?? '';
        if (templates.isEmpty) {
          _selectedTemplate = null;
        } else if (previousTemplateId != null &&
            templates.any((t) => t.templateId == previousTemplateId)) {
          // Stay on the same template after refresh
          _selectedTemplate = templates
              .firstWhere((t) => t.templateId == previousTemplateId);
        } else {
          // First load — default to General Intake Sheet
          _selectedTemplate = templates.firstWhere(
              (t) => t.formName == 'General Intake Sheet',
              orElse: () => templates.first);
        }
      });

      debugPrint(
          'Selected template: ${_selectedTemplate?.formName ?? "NONE"}');

      if (_selectedTemplate != null) {
        await _initFormController(profileData);
      }
    } catch (e, stack) {
      debugPrint('ManageInfoScreen._loadAll error: $e');
      debugPrint('Stack: $stack');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Build form controller from user_field_values ──
  Future<void> _initFormController(Map<String, dynamic>? profileData) async {
    _formCtrl?.dispose();
    final ctrl = FormStateController(template: _selectedTemplate!);

    final loaded = await _fieldValueService.loadUserFieldValues(
      userId: widget.userId,
      template: _selectedTemplate!,
    );
    ctrl.loadFromJson(loaded);
    if (loaded['__signature'] != null) {
      ctrl.signatureBase64 = loaded['__signature'].toString();
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
              'relationship_of_relative': m['relationship_of_relative'] ?? '',
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

    // Load alimony from first supporting family row
    if (supporting.isNotEmpty && supporting.first['monthly_alimony'] != null) {
      final monthlyAlimony = supporting.first['monthly_alimony'].toString();
      if (_formCtrl != null) {
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

      if (data['__signature'] != null) {
        _formCtrl!.signatureBase64 = data['__signature'];
      }

      // Pass 1: Save all flat fields by field_id for any template (GIS included)
      await _fieldValueService.saveUserFieldValues(
        userId: widget.userId,
        template: _selectedTemplate!,
        formData: data,
      );

      // Pass 2: Route system blocks (family/supporting-family) via interceptor
      final profile = await _supabaseService.loadUserProfile(widget.userId);
      final profileId = profile?['profile_id']?.toString();
      if (profileId != null && profileId.isNotEmpty) {
        await _supabaseService.interceptAndRouteSystemFields(
          profileId: profileId,
          template: _selectedTemplate!,
          formData: data,
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

    // Require at least one checkbox selected
    final hasAnyChecked = _formCtrl!.selectAll || 
        _formCtrl!.fieldChecks.values.any((checked) => checked == true);
    
    if (!hasAnyChecked) {
      _showFeedback('Please select at least one field to transmit', AppColors.dangerRed);
      return;
    }

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
      // Push field values + JSONB to web session
      final success = await _fieldValueService.pushToSubmission(
        sessionId: sessionId,
        template: _selectedTemplate!,
        formData: dataToTransmit,
      );
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
          setState(() => _currentNavIndex = 2);
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
      floatingActionButton: (_formCtrl != null && _currentNavIndex == 0) ? _buildSelectAllFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
      body: _currentNavIndex == 2
          ? HistoryScreen(userId: widget.userId, embedded: true)
          : _isLoading
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
    title: GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(userId: widget.userId),
        ),
      ),
      child: Row(
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
          Expanded(
            child: Column(
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
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'No forms available.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
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
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: AppColors.primaryBlue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                  isExpanded: true,
                  items: _templates
                      .map((t) => DropdownMenuItem(
                            value: t.templateId,
                            child: Text(
                              t.formName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (id) async {
                    final tpl =
                        _templates.firstWhere((t) => t.templateId == id);
                    setState(() => _selectedTemplate = tpl);
                    final profile =
                        await _supabaseService.loadUserProfile(widget.userId);
                    await _initFormController(profile);
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