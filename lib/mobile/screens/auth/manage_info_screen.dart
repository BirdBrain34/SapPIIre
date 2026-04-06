// Mobile Manage Info Screen
// Loads templates + profile, renders dynamic form, saves to Supabase,
// and transmits selected fields to the web portal via QR.

import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/mobile/controllers/manage_info_controller.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/screens/auth/ProfileScreen.dart';
import 'package:sappiire/mobile/screens/auth/HistoryScreen.dart';
import 'package:sappiire/models/form_template_models.dart';

class ManageInfoScreen extends StatefulWidget {
  final String userId;
  const ManageInfoScreen({super.key, required this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  final _supabaseService = SupabaseService();
  late final ManageInfoController _controller;
  int _currentNavIndex = 0;

  // Controls whether the form intro card is shown
  bool _showFormIntro = true;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _controller = ManageInfoController(userId: widget.userId);
    _loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────
  Future<void> _loadAll() async {
    await _controller.loadAll(forceRefresh: true);
    if (mounted) {
      setState(() => _showFormIntro = true);
    }
  }

  // ── Save to Supabase ──────────────────────────────────────
  Future<void> _saveProfile() async {
    final ok = await _controller.saveProfile();
    if (!mounted) return;
    if (ok) {
      _showFeedback('Profile saved!', Colors.green);
    } else {
      _showFeedback(
        'Save failed: ${_controller.errorMessage ?? 'Unknown error'}',
        Colors.red,
      );
    }
  }

  // ── Required fields validation ────────────────────────────
  /// Returns list of required fields that are still empty.
  List<FormFieldModel> _getMissingRequiredFields() {
    final template = _controller.selectedTemplate;
    final fc = _controller.formController;
    if (template == null || fc == null) return [];

    final missing = <FormFieldModel>[];
    for (final field in template.allFields) {
      if (!field.isRequired) continue;
      if (field.parentFieldId != null) continue; // skip sub-fields
      final value = fc.getValue(field.fieldName);
      if (value == null || value.toString().trim().isEmpty) {
        missing.add(field);
      }
    }
    return missing;
  }

  /// Shows the required-fields warning popup — same style as QR scanner dialog.
  Future<bool> _showRequiredFieldsDialog(
    List<FormFieldModel> missingFields,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 32,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Required Fields Incomplete',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The following required fields are still empty. '
                'Please fill them in before transmitting.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: missingFields
                        .map(
                          (f) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f.fieldLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, // Makes the button span the full width
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700, // Use a primary color to guide them
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Go Back to Form',
                    style: TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  // ── QR Transmit ───────────────────────────────────────────
  Future<void> _scanAndTransmit() async {
    final dataToTransmit = _controller.buildTransmitPayload();
    if (dataToTransmit == null) {
      _showFeedback(
        'Please select at least one field to transmit',
        AppColors.dangerRed,
      );
      return;
    }

    // Check required fields before allowing QR scan
    final missingFields = _getMissingRequiredFields();
    if (missingFields.isNotEmpty) {
      final proceed = await _showRequiredFieldsDialog(missingFields);
      if (!proceed || !mounted) return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          transmitData: dataToTransmit,
          userId: widget.userId,
          templateId: _controller.selectedTemplate?.templateId,
          formName: _controller.selectedTemplate?.formName,
          supabaseService: _supabaseService,
        ),
      ),
    );

    // After returning from QR scanner (back from HistoryScreen or back button),
    // reload form data and reset to intro card
    if (mounted) {
      await _controller.loadAll(forceRefresh: true);
      setState(() => _showFormIntro = true);
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
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _supabaseService.signOutCurrentUser();
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
        setState(() {
          _currentNavIndex = 0;
          _showFormIntro = true;
        });
        break;
      case 1:
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
    // Reload after returning from camera — scanned data may have updated fields
    if (mounted) {
      await _controller.loadAll(forceRefresh: true);
      setState(() {});
    }
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
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
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
                  child: const Text(
                    'Log Out',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            await _supabaseService.signOutCurrentUser();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBg,
          appBar: _buildAppBar(),
          floatingActionButton:
              (_controller.formController != null &&
                  _currentNavIndex == 0 &&
                  !_showFormIntro)
              ? _buildSelectAllFAB()
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: _buildBottomNav(),
          body: _currentNavIndex == 2
              ? HistoryScreen(userId: widget.userId, embedded: true)
              : _controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _controller.templates.isEmpty
              ? _buildEmptyState()
              : _showFormIntro
              ? _buildFormIntroCard()
              : _buildFormContent(),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    // FIX: use _controller.username which is loaded from DB
    final displayName = _controller.username.isNotEmpty
        ? _controller.username
        : 'User';

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
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(userId: widget.userId),
            ),
          );
          // Reload after returning from ProfileScreen — username/PII may have changed
          if (mounted) {
            await _controller.loadAll(forceRefresh: true);
            setState(() => _showFormIntro = true);
          }
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome back,',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
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
          icon: const Icon(
            Icons.camera_alt_outlined,
            color: Colors.white,
            size: 22,
          ),
          onPressed: _openCamera,
          tooltip: 'Scan ID',
        ),
        // Only show Save when the form is visible
        if (!_showFormIntro && _currentNavIndex == 0)
          IconButton(
            icon: _controller.isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.save_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
            onPressed: _controller.isSaving ? null : _saveProfile,
            tooltip: 'Save Profile',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Form Intro / Selection Card ───────────────────────────
  Widget _buildFormIntroCard() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.edit_document,
                  size: 36,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Form Setup',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ready to manage your info?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select a form type below. Your saved information will be '
                'pre-filled and ready to transmit!',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // Form Dropdown
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDDDEE)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _controller.selectedTemplate?.templateId,
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primaryBlue,
                    ),
                    items: _controller.templates
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.templateId,
                            child: Text(
                              t.formName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A2E),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) async {
                      if (id == null) return;
                      await _controller.switchTemplate(id);
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _controller.selectedTemplate == null
                      ? null
                      : () => setState(() => _showFormIntro = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primaryBlue.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
              child: _controller.formController == null
                  ? const Center(child: CircularProgressIndicator())
                  : DynamicFormRenderer(
                      template: _controller.selectedTemplate!,
                      controller: _controller.formController!,
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
                  value: _controller.selectedTemplate?.templateId,
                  isExpanded: true,
                  items: _controller.templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.templateId,
                          child: Text(
                            t.formName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) async {
                    if (id == null) return;
                    await _controller.switchTemplate(id);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Select All Button ────────────────────────────
  Widget _buildSelectAllFAB() {
    final isSelectAll = _controller.formController?.selectAll ?? false;
    return FloatingActionButton.extended(
      onPressed: () {
        _controller.formController?.setSelectAll(!isSelectAll);
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
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex == 1 ? 0 : _currentNavIndex,
      onTap: _onNavTap,
      backgroundColor: AppColors.primaryBlue,
      selectedItemColor: AppColors.highlight,
      unselectedItemColor: Colors.white60,
      selectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w400,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 10,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.edit_document, size: 24),
          label: 'Manage Info',
        ),
        BottomNavigationBarItem(
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.qr_code_scanner,
              color: _currentNavIndex == 1
                  ? AppColors.highlight
                  : AppColors.primaryBlue,
              size: 22,
            ),
          ),
          label: 'Autofill QR',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.history, size: 24),
          label: 'History',
        ),
      ],
    );
  }
}