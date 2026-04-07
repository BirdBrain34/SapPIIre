// Mobile Manage Info Screen
// Loads templates + profile, renders dynamic form, saves to Supabase,
// and transmits selected fields to the web portal via QR.

import 'dart:convert';

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
  bool _hasUnsavedChanges = false;
  bool _awaitingExplicitLogoutAfterUnsavedResolution = false;
  String _savedFormFingerprint = '';
  ChangeNotifier? _listenedFormController;
  VoidCallback? _formControllerListener;

  // Controls whether the form intro card is shown
  bool _showFormIntro = true;

  // Tracks which required fields are still empty — used for red highlight
  Set<String> _highlightedMissingFields = {};

  @override
  void initState() {
    super.initState();
    _controller = ManageInfoController(userId: widget.userId);
    _loadAll();
  }

  @override
  void dispose() {
    if (_listenedFormController != null && _formControllerListener != null) {
      _listenedFormController!.removeListener(_formControllerListener!);
    }
    _controller.dispose();
    super.dispose();
  }

  void _attachFormControllerListener() {
    final formCtrl = _controller.formController;
    if (formCtrl == null) return;

    if (identical(_listenedFormController, formCtrl)) return;

    if (_listenedFormController != null && _formControllerListener != null) {
      _listenedFormController!.removeListener(_formControllerListener!);
    }

    _formControllerListener = () {
      if (!mounted) return;
      final nextUnsaved = _currentFormFingerprint() != _savedFormFingerprint;
      if (nextUnsaved != _hasUnsavedChanges) {
        setState(() => _hasUnsavedChanges = nextUnsaved);
      }
      if (nextUnsaved && _awaitingExplicitLogoutAfterUnsavedResolution) {
        setState(() => _awaitingExplicitLogoutAfterUnsavedResolution = false);
      }
    };

    formCtrl.addListener(_formControllerListener!);
    _listenedFormController = formCtrl;
  }

  String _currentFormFingerprint() {
    final formCtrl = _controller.formController;
    if (formCtrl == null) return '';
    try {
      final checkEntries = formCtrl.fieldChecks.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final checkMap = <String, bool>{
        for (final e in checkEntries) e.key: e.value,
      };
      return jsonEncode({
        'form': formCtrl.toJson(),
        'fieldChecks': checkMap,
        'selectAll': formCtrl.selectAll,
      });
    } catch (_) {
      return '';
    }
  }

  void _markCurrentFormAsSaved() {
    _savedFormFingerprint = _currentFormFingerprint();
    if (!mounted) {
      _hasUnsavedChanges = false;
      return;
    }
    if (_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = false);
    }
  }

  bool _hasPendingUnsavedChanges() {
    final hasUnsaved = _currentFormFingerprint() != _savedFormFingerprint;
    if (mounted && hasUnsaved != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = hasUnsaved);
    }
    if (hasUnsaved && _awaitingExplicitLogoutAfterUnsavedResolution && mounted) {
      setState(() => _awaitingExplicitLogoutAfterUnsavedResolution = false);
    }
    return hasUnsaved;
  }

  Future<void> _flushPendingInput() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<bool> _resolveUnsavedChangesIfAny() async {
    await _flushPendingInput();
    if (!_hasPendingUnsavedChanges()) return true;

    final result = await _showUnsavedChangesDialog();
    if (result == null) return false;
    if (result == false) {
      _markCurrentFormAsSaved();
    }

    // If save failed, there may still be pending changes; do not continue.
    return !_hasPendingUnsavedChanges();
  }

  Future<void> _loadAll() async {
    await _controller.loadAll(forceRefresh: true);
    _attachFormControllerListener();
    _savedFormFingerprint = _currentFormFingerprint();
    if (mounted) {
      setState(() {
        _showFormIntro = true;
        _highlightedMissingFields = {};
        _hasUnsavedChanges = false;
        _awaitingExplicitLogoutAfterUnsavedResolution = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final ok = await _controller.saveProfile();
    if (!mounted) return;
    if (ok) {
      _markCurrentFormAsSaved();
      _showFeedback('Profile saved!', Colors.green);
    } else {
      _showFeedback('Save failed: ${_controller.errorMessage ?? 'Unknown error'}', Colors.red);
    }
  }

  Future<bool?> _showUnsavedChangesDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: const Text(
                  'Unsaved Changes',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      'You have unsaved changes to your profile information. Would you like to save before leaving?',
                      style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1A1A2E)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Discard'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await _saveProfile();
                              if (!ctx.mounted) return;
                              if (!_hasUnsavedChanges) {
                                Navigator.pop(ctx, true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                            child: const Text('Save & Continue', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Required fields check ─────────────────────────────────
  List<FormFieldModel> _getMissingRequiredFields() {
    final template = _controller.selectedTemplate;
    final fc = _controller.formController;
    if (template == null || fc == null) return [];

    final missing = <FormFieldModel>[];
    for (final field in template.allFields) {
      if (!field.isRequired) continue;
      if (field.parentFieldId != null) continue;
      final value = fc.getValue(field.fieldName);
      if (value == null || value.toString().trim().isEmpty) {
        missing.add(field);
      }
    }
    return missing;
  }

  /// Shows the required-fields warning popup and HIGHLIGHTS the missing fields
  /// in the form so the user can see exactly what's empty.
  Future<bool> _showRequiredFieldsDialog(List<FormFieldModel> missingFields) async {
    // First: highlight the missing fields in the form
    setState(() {
      _highlightedMissingFields = missingFields.map((f) => f.fieldName).toSet();
    });

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
                child: const Icon(Icons.warning_amber_rounded, size: 32, color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text(
                'Required Fields Incomplete',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The following required fields are still empty. They are highlighted in the form below.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.circle, size: 6, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f.fieldLabel,
                                    style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w500),
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
              const SizedBox(height: 20),
              // Single button — go back to fill them in (they're highlighted)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Go Back to Fill In',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Option to still proceed despite warnings
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Proceed anyway',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // If going back to fill, keep highlights. If proceeding, clear them.
    if (result == true && mounted) {
      setState(() => _highlightedMissingFields = {});
    }

    return result ?? false;
  }

  // ── QR Transmit ───────────────────────────────────────────
  Future<String?> _scanAndTransmit() async {
    final dataToTransmit = _controller.buildTransmitPayload();
    if (dataToTransmit == null) {
      _showFeedback('Please select at least one field to transmit', AppColors.dangerRed);
      return null;
    }

    final missingFields = _getMissingRequiredFields();
    if (missingFields.isNotEmpty) {
      final proceed = await _showRequiredFieldsDialog(missingFields);
      if (!proceed || !mounted) {
        // Scroll back to form so user can see highlighted fields
        setState(() => _showFormIntro = false);
        return null;
      }
    }

    final navResult = await Navigator.push<String?>(
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

    if (mounted) {
      await _controller.loadAll(forceRefresh: true);
      _attachFormControllerListener();
      _savedFormFingerprint = _currentFormFingerprint();
      setState(() {
        _showFormIntro = true;
        _highlightedMissingFields = {};
        _hasUnsavedChanges = false;
      });
    }

    return navResult;
  }

  Future<void> _handleLogout() async {
    await _flushPendingInput();
    final hadUnsavedChanges = _hasPendingUnsavedChanges();
    if (hadUnsavedChanges) {
      final canProceed = await _resolveUnsavedChangesIfAny();
      if (!canProceed) return;
      // Unsaved changes were just resolved. Require another explicit
      // back/logout action before showing the logout confirmation.
      if (mounted) {
        setState(() => _awaitingExplicitLogoutAfterUnsavedResolution = true);
      } else {
        _awaitingExplicitLogoutAfterUnsavedResolution = true;
      }
      return;
    }

    if (_awaitingExplicitLogoutAfterUnsavedResolution) {
      if (mounted) {
        setState(() => _awaitingExplicitLogoutAfterUnsavedResolution = false);
      } else {
        _awaitingExplicitLogoutAfterUnsavedResolution = false;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
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

  Future<void> _onNavTap(int index) async {
    if (_currentNavIndex == 0 && index != 0) {
      final canProceed = await _resolveUnsavedChangesIfAny();
      if (!canProceed) return;
    }

    switch (index) {
      case 0:
        setState(() {
          _currentNavIndex = 0;
          _showFormIntro = true;
          _highlightedMissingFields = {};
        });
        break;
      case 1:
        setState(() => _currentNavIndex = 1);
        final navResult = await _scanAndTransmit();
        if (mounted) {
          setState(() => _currentNavIndex = navResult == 'history' ? 2 : 0);
        }
        break;
      case 2:
        setState(() => _currentNavIndex = 2);
        break;
    }
  }

  Future<void> _openCamera() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoScannerScreen()));
    if (mounted) {
      await _controller.loadAll(forceRefresh: true);
      _attachFormControllerListener();
      _savedFormFingerprint = _currentFormFingerprint();
      setState(() {
        _hasUnsavedChanges = false;
        _awaitingExplicitLogoutAfterUnsavedResolution = false;
      });
    }
  }

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => WillPopScope(
        onWillPop: () async {
          await _handleLogout();
          return false;
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBg,
          appBar: _buildAppBar(),
          floatingActionButton: (_controller.formController != null && _currentNavIndex == 0 && !_showFormIntro)
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

  PreferredSizeWidget _buildAppBar() {
    final displayName = _controller.username.isNotEmpty ? _controller.username : 'User';

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
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.userId)));
          if (mounted) {
            await _controller.loadAll(forceRefresh: true);
            _attachFormControllerListener();
            _savedFormFingerprint = _currentFormFingerprint();
            setState(() {
              _showFormIntro = true;
              _highlightedMissingFields = {};
              _hasUnsavedChanges = false;
              _awaitingExplicitLogoutAfterUnsavedResolution = false;
            });
          }
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.person_outline, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Welcome back,', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w400)),
                  Text(
                    displayName,
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
        if (!_showFormIntro && _currentNavIndex == 0)
          IconButton(
            icon: _controller.isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
            onPressed: _controller.isSaving ? null : _saveProfile,
            tooltip: 'Save Profile',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFormIntroCard() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(18)),
                child: Icon(Icons.edit_document, size: 36, color: AppColors.primaryBlue),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                child: Text('Form Setup', style: TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              ),
              const SizedBox(height: 16),
              const Text('Ready to manage your info?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Select a form type below. Your saved information will be pre-filled and ready to transmit!',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
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
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryBlue),
                    items: _controller.templates.map((t) => DropdownMenuItem(
                      value: t.templateId,
                      child: Text(t.formName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)), overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (id) async {
                      if (id == null) return;

                      if (_hasUnsavedChanges && !_showFormIntro) {
                        final result = await _showUnsavedChangesDialog();
                        if (result == null) return;
                        if (result == false) {
                          _markCurrentFormAsSaved();
                        }
                      }

                      await _controller.switchTemplate(id);
                      _attachFormControllerListener();
                      _savedFormFingerprint = _currentFormFingerprint();
                      setState(() {
                        _highlightedMissingFields = {};
                        _hasUnsavedChanges = false;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _controller.selectedTemplate == null ? null : () => setState(() => _showFormIntro = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primaryBlue.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
          Text('No forms available.', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Pull down to refresh', style: TextStyle(color: Colors.grey.shade400, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    return Column(
      children: [
        _buildFormSelector(),
        // Show missing fields banner if any are highlighted
        if (_highlightedMissingFields.isNotEmpty) _buildMissingFieldsBanner(),
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
                      // Pass highlighted fields so the renderer can mark them red
                      highlightedFields: _highlightedMissingFields,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMissingFieldsBanner() {
    return Container(
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_highlightedMissingFields.length} required field${_highlightedMissingFields.length == 1 ? '' : 's'} still empty — highlighted below in red',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _highlightedMissingFields = {}),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 32)),
            child: Text('Dismiss', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSelector() {
    return Container(
      color: AppColors.primaryBlue.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Form:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                  items: _controller.templates.map((t) => DropdownMenuItem(
                    value: t.templateId,
                    child: Text(t.formName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (id) async {
                    if (id == null) return;

                    if (_hasUnsavedChanges && !_showFormIntro) {
                      final result = await _showUnsavedChangesDialog();
                      if (result == null) return;
                      if (result == false) {
                        _markCurrentFormAsSaved();
                      }
                    }

                    await _controller.switchTemplate(id);
                    _attachFormControllerListener();
                    _savedFormFingerprint = _currentFormFingerprint();
                    setState(() {
                      _highlightedMissingFields = {};
                      _hasUnsavedChanges = false;
                    });
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectAllFAB() {
    final isSelectAll = _controller.formController?.selectAll ?? false;
    return FloatingActionButton.extended(
      onPressed: () {
        _controller.formController?.setSelectAll(!isSelectAll);
        setState(() {});
      },
      backgroundColor: isSelectAll ? AppColors.highlight : AppColors.primaryBlue,
      elevation: 6,
      icon: Icon(isSelectAll ? Icons.deselect_rounded : Icons.select_all_rounded, color: Colors.white, size: 20),
      label: Text(
        isSelectAll ? 'Deselect All' : 'Select All',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex == 1 ? 0 : _currentNavIndex,
      onTap: _onNavTap,
      backgroundColor: AppColors.primaryBlue,
      selectedItemColor: AppColors.highlight,
      unselectedItemColor: Colors.white60,
      selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
      type: BottomNavigationBarType.fixed,
      elevation: 10,
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.edit_document, size: 24), label: 'Manage Info'),
        BottomNavigationBarItem(
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: Icon(Icons.qr_code_scanner, color: _currentNavIndex == 1 ? AppColors.highlight : AppColors.primaryBlue, size: 22),
          ),
          label: 'Autofill QR',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.history, size: 24), label: 'History'),
      ],
    );
  }
}