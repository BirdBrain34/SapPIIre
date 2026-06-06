/// Mobile manage-info screen for loading profiles, editing dynamic forms,
/// and transmitting selected fields to the web portal through QR.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/form_template_notification_service.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/mobile/controllers/manage_info_controller.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/screens/auth/ProfileScreen.dart';
import 'package:sappiire/mobile/screens/auth/HistoryScreen.dart';
import 'package:sappiire/mobile/widgets/unsaved_changes_dialog.dart';
import 'package:sappiire/mobile/widgets/logout_confirmation_dialog.dart';
import 'package:sappiire/mobile/widgets/TermsandCondition.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/mobile/screens/auth/NotificationScreen.dart';


class ManageInfoScreen extends StatefulWidget {
  final String userId;

  /// Pass `true` when navigating here immediately after a successful sign-up.
  /// The T&C acceptance dialog will be shown automatically on first render.
  final bool isNewAccount;

  const ManageInfoScreen({
    super.key,
    required this.userId,
    this.isNewAccount = false,
  });

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  final _supabaseService = SupabaseService();
  final _notificationService = FormTemplateNotificationService();
  late final ManageInfoController _controller;
  StreamSubscription<TemplateNotification>? _templateNotificationSubscription;
  int _currentNavIndex = 0;
  bool _logoutFlowInProgress = false;
  bool _logoutDialogOpen = false;
  bool _hasUnsavedChanges = false;
  String _savedFormFingerprint = '';
  ChangeNotifier? _listenedFormController;
  VoidCallback? _formControllerListener;

  // Track whether the intro card is still visible.
  bool _showFormIntro = true;

  //Track user if they read the notif
  int _unreadNotifCount = 0;

  // Track which required fields are still empty so they can be highlighted.
  Set<String> _highlightedMissingFields = {};

  @override
  void initState() {
    super.initState();
    _controller = ManageInfoController(userId: widget.userId);
    _loadAll();
    _loadUnreadCount();
    _startTemplateNotifications();

    // Show T&C acceptance dialog once the screen is fully rendered,
    // but only for users who just completed sign-up.
    if (widget.isNewAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await TermsAndConditionsDialog.showForAcceptance(context);
        // The user is already registered at this point, so we don't gate
        // access on acceptance. If your product requires mandatory acceptance,
        // check the return value here and sign the user out on decline.
      });
    }
  }

  @override
  void dispose() {
    if (_listenedFormController != null && _formControllerListener != null) {
      _listenedFormController!.removeListener(_formControllerListener!);
    }
    _templateNotificationSubscription?.cancel();
    _notificationService.stopListening();
    _controller.dispose();
    super.dispose();
  }

  // ── Form change-detection ─────────────────────────────────────────────────

  void _attachFormControllerListener() {
    final formCtrl = _controller.formController;
    if (formCtrl == null) return;

    // Already listening to the exact same instance — skip.
    if (identical(_listenedFormController, formCtrl)) return;

    // Detach from previous instance.
    if (_listenedFormController != null && _formControllerListener != null) {
      _listenedFormController!.removeListener(_formControllerListener!);
    }

    _formControllerListener = () {
      if (!mounted) return;
      final nextUnsaved = _currentFormFingerprint() != _savedFormFingerprint;
      if (nextUnsaved != _hasUnsavedChanges) {
        debugPrint('[ManageInfoScreen/_attachFormControllerListener] Action: Unsaved state changed Value: $nextUnsaved');
        setState(() => _hasUnsavedChanges = nextUnsaved);
      }
    };

    formCtrl.addListener(_formControllerListener!);
    _listenedFormController = formCtrl;
  }

  /// Produces a stable JSON string representing the current form field VALUES.
  ///
  /// Intentionally excludes [fieldChecks] and [selectAll] — those control
  /// which fields are transmitted via QR and are not part of the saved profile.
  /// Including them would cause the unsaved-changes dialog to fire every time
  /// the user ticks a checkbox or presses Select All, which is wrong.
  String _currentFormFingerprint() {
    final formCtrl = _controller.formController;
    if (formCtrl == null) return '';
    try {
      return jsonEncode({'form': formCtrl.toJson()});
    } catch (_) {
      return '';
    }
  }

  void _markCurrentFormAsSaved() {
    _savedFormFingerprint = _currentFormFingerprint();
    debugPrint('[ManageInfoScreen/_markCurrentFormAsSaved] Action: Form baseline updated');
    if (!mounted) {
      _hasUnsavedChanges = false;
      return;
    }
    if (_hasUnsavedChanges) setState(() => _hasUnsavedChanges = false);
  }

  bool _hasPendingUnsavedChanges() {
    final hasUnsaved = _currentFormFingerprint() != _savedFormFingerprint;
    if (mounted && hasUnsaved != _hasUnsavedChanges) {
      debugPrint('[ManageInfoScreen/_hasPendingUnsavedChanges] Action: Pending unsaved Value: $hasUnsaved');
      setState(() => _hasUnsavedChanges = hasUnsaved);
    }
    return hasUnsaved;
  }

  Future<void> _flushPendingInput() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  /// Resolves any pending unsaved changes by showing the UnsavedChangesDialog.
  /// Returns true when it is safe to continue with the intended navigation.
  Future<bool> _resolveUnsavedChangesIfAny() async {
    await _flushPendingInput();

    var attempt = 0;
    while (_hasPendingUnsavedChanges()) {
      attempt++;
      debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: Unsaved dialog attempt Count: $attempt');

      final result = await _showUnsavedChangesDialog();
      if (!mounted) return false;

      if (result != true) {
        debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: Unsaved dialog result Discard');
        await _discardPendingChangesAndRefresh();
      } else {
        debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: Unsaved dialog result Save');
      }

      final stillUnsaved = _hasPendingUnsavedChanges();
      debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: Pending unsaved after dialog Value: $stillUnsaved');
      if (!stillUnsaved) return true;

      debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: Reopen unsaved dialog');
    }

    debugPrint('[ManageInfoScreen/_resolveUnsavedChangesIfAny] Action: No pending unsaved changes');
    return true;
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await _controller.loadAll(forceRefresh: true);
    _attachFormControllerListener();
    _savedFormFingerprint = _currentFormFingerprint();
    if (mounted) {
      setState(() {
        _showFormIntro = true;
        _highlightedMissingFields = {};
        _hasUnsavedChanges = false;
      });
    }
  }

  Future<void> _discardPendingChangesAndRefresh() async {
    final preserveShowFormIntro = _showFormIntro;
    final preserveNavIndex = _currentNavIndex;
    debugPrint('[ManageInfoScreen/_discardPendingChangesAndRefresh] Action: Refresh latest saved data');

    await _controller.loadAll(forceRefresh: true);
    _attachFormControllerListener();
    _savedFormFingerprint = _currentFormFingerprint();

    if (!mounted) {
      _hasUnsavedChanges = false;
      return;
    }

    setState(() {
      _showFormIntro = preserveShowFormIntro;
      _currentNavIndex = preserveNavIndex;
      _highlightedMissingFields = {};
      _hasUnsavedChanges = false;
    });
  }

// ── Notif Read Count ──────────────────────────────────────
    Future<void> _loadUnreadCount() async {
    final count =
        await _supabaseService.fetchUnreadNotificationCount(widget.userId);
    if (mounted) setState(() => _unreadNotifCount = count);
  }

    Future<void> _openNotifications() async {
    final returnedReadIds = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationScreen(userId: widget.userId),
      ),
    );
    // Recalculate badge after returning from notification screen.
    if (mounted) await _loadUnreadCount();
    // Also reload if the user read items (form templates may have changed).
    if (returnedReadIds != null && returnedReadIds.isNotEmpty && mounted) {
      await _loadAll();
    }
  }

  // ── Real-time template notifications ──────────────────────────────────────

  void _startTemplateNotifications() {
    _notificationService.startListening();
    _templateNotificationSubscription =
        _notificationService.notificationStream.listen((notification) {
      if (!mounted) return;

      final changeType = notification.changeType;
      final message = notification.changeSummary;

      // Classify the notification so the UI can choose the right icon and color.
      final isFieldChange = changeType == 'field_added'
          || changeType == 'field_updated'
          || changeType == 'field_deleted';

      // Treat pushed or added templates as new form notifications.
      final isNewForm = changeType == 'pushed_to_mobile'
          || changeType == 'added';

      // Treat archived or deleted templates as removal notifications.
      final isRemoval = changeType == 'archived'
          || changeType == 'deleted';

      final IconData notifIcon;
      if (isFieldChange) {
        notifIcon = Icons.edit_note_rounded;
      } else if (isNewForm) {
        notifIcon = Icons.new_releases_outlined;
      } else if (isRemoval) {
        notifIcon = Icons.remove_circle_outline;
      } else {
        notifIcon = Icons.update_outlined;
      }

      final Color bgColor;
      if (isFieldChange) {
        bgColor = const Color(0xFF0277BD);
      } else if (isNewForm) {
        bgColor = const Color(0xFF0D47A1);
      } else if (isRemoval) {
        bgColor = const Color(0xFFC62828);
      } else {
        bgColor = const Color(0xFF1565C0);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(notifIcon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'RELOAD',
            textColor: Colors.white,
            onPressed: _loadAll,
          ),
        ),
      );
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    final ok = await _controller.saveProfile();
    if (!mounted) return;
    if (ok) {
      _markCurrentFormAsSaved();
      _showFeedback('Profile saved!', Colors.green);
    } else {
      _showFeedback(
        'Save failed: ${_controller.errorMessage ?? 'Unknown error'}',
        Colors.red,
      );
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<bool?> _showUnsavedChangesDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UnsavedChangesDialog(
        onDiscard: () {
            debugPrint('[ManageInfoScreen/_showUnsavedChangesDialog] Action: Unsaved dialog button Discard');
          Navigator.pop(ctx, false);
        },
        onSaveAndContinue: () async {
            debugPrint('[ManageInfoScreen/_showUnsavedChangesDialog] Action: Unsaved dialog button SaveAndContinue');
          await _saveProfile();
          if (!ctx.mounted) return;
          // Only close the dialog if the save actually cleared the unsaved flag.
          if (!_hasUnsavedChanges) Navigator.pop(ctx, true);
        },
      ),
    );
  }

  // Required fields check.
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

  Future<bool> _showRequiredFieldsDialog(
      List<FormFieldModel> missingFields) async {
    // Highlight the missing fields in the form first.
    setState(() {
      _highlightedMissingFields =
          missingFields.map((f) => f.fieldName).toSet();
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
                child: const Icon(Icons.warning_amber_rounded,
                    size: 32, color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text(
                'Required Fields Incomplete',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The following required fields are still empty. '
                'They are highlighted in the form below.',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: missingFields
                        .map((f) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.circle,
                                      size: 6, color: Colors.red),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      f.fieldLabel,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.red,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Go Back to Fill In',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Proceed anyway',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _highlightedMissingFields = {});
    }
    return result ?? false;
  }

  // ── QR Transmit ───────────────────────────────────────────────────────────

  Future<String?> _scanAndTransmit() async {
    final dataToTransmit = _controller.buildTransmitPayload();
    if (dataToTransmit == null) {
      _showFeedback(
          'Please select at least one field to transmit', AppColors.dangerRed);
      return null;
    }

    final missingFields = _getMissingRequiredFields();
    if (missingFields.isNotEmpty) {
      final proceed = await _showRequiredFieldsDialog(missingFields);
      if (!proceed || !mounted) {
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

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    if (_logoutFlowInProgress) return;
    _logoutFlowInProgress = true;

    try {
      await _flushPendingInput();
      final hasPendingUnsaved = _hasPendingUnsavedChanges();
      debugPrint('[ManageInfoScreen/_handleLogout] Action: Logout requested HasPendingUnsaved=$hasPendingUnsaved');

      // Step A: If unsaved changes exist, resolve them first.
      // The unsaved-changes popup is ALWAYS shown before the logout dialog.
      // After any action (save, discard), the user returns here without
      // seeing the logout confirmation — per the agreed flowchart.
      if (hasPendingUnsaved) {
        await _resolveUnsavedChangesIfAny();
        return; // Always return — logout popup never follows unsaved dialog.
      }

      // Step B: No unsaved changes → show the logout confirmation dialog.
      debugPrint('[ManageInfoScreen/_handleLogout] Action: Show logout confirmation dialog');
      final confirmed = await _showLogoutConfirmationDialog();
      debugPrint('[ManageInfoScreen/_handleLogout] Action: Logout confirmation result=$confirmed');

      if (confirmed != true || !mounted) return;
      await _supabaseService.signOutCurrentUser();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } finally {
      _logoutFlowInProgress = false;
    }
  }

  Future<bool> _showLogoutConfirmationDialog() async {
    if (!mounted || _logoutDialogOpen) return false;

    _logoutDialogOpen = true;
    var didTapConfirm = false;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => LogoutConfirmationDialog(
          onCancel: () => Navigator.pop(ctx, false),
          onConfirm: () {
            didTapConfirm = true;
            Navigator.pop(ctx, true);
          },
        ),
      );
      return didTapConfirm && confirmed == true;
    } finally {
      _logoutDialogOpen = false;
    }
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────

  Future<void> _onNavTap(int index) async {
    // When leaving the form tab, check for unsaved changes first.
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
    final canProceed = await _resolveUnsavedChangesIfAny();
    if (!canProceed || !mounted) return;

    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const InfoScannerScreen()));
    if (mounted) {
      await _controller.loadAll(forceRefresh: true);
      _attachFormControllerListener();
      _savedFormFingerprint = _currentFormFingerprint();
      setState(() => _hasUnsavedChanges = false);
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

  // ── Template switching (both intro-card and in-form dropdowns) ────────────

  /// Shared handler for both template-selector dropdowns.
  /// Always checks for unsaved changes before switching.
  Future<void> _onTemplateSwitched(String? id) async {
    if (id == null) return;

    // If there are unsaved changes on the current form, resolve them first.
    if (_hasUnsavedChanges && !_showFormIntro) {
      final resolved = await _resolveUnsavedChangesIfAny();
      if (!resolved) return;
    }

    await _controller.switchTemplate(id);
    _attachFormControllerListener();
    _savedFormFingerprint = _currentFormFingerprint();
    if (mounted) {
      setState(() {
        _highlightedMissingFields = {};
        _hasUnsavedChanges = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleLogout();
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

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final displayName =
        _controller.username.isNotEmpty ? _controller.username : 'User';
 
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
          final canProceed = await _resolveUnsavedChangesIfAny();
          if (!canProceed || !mounted) return;
 
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: widget.userId)),
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
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Welcome back,',
                      style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w400)),
                  Text(
                    displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // ── NOTIFICATION BELL (replaces camera icon) ──────────────
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 24),
              onPressed: _openNotifications,
              tooltip: 'Notifications',
            ),
            if (_unreadNotifCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    // Use AppColors.highlight (gold/amber) to match your FAB style
                    color: AppColors.highlight,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primaryBlue, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      _unreadNotifCount > 99
                          ? '99+'
                          : '$_unreadNotifCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // ── SAVE BUTTON (unchanged) ───────────────────────────────
        if (!_showFormIntro && _currentNavIndex == 0)
          IconButton(
            icon: _controller.isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined,
                    color: Colors.white, size: 22),
            onPressed: _controller.isSaving ? null : _saveProfile,
            tooltip: 'Save Profile',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Form intro card ───────────────────────────────────────────────────────

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
              )
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
                child: Icon(Icons.edit_document,
                    size: 36, color: AppColors.primaryBlue),
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
                      letterSpacing: 0.4),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ready to manage your info?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select a form type below. Your saved information will be '
                'pre-filled and ready to transmit!',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── Template dropdown ──────────────────────────
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
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primaryBlue),
                    items: _controller.templates
                        .map((t) => DropdownMenuItem(
                              value: t.templateId,
                              child: Text(
                                t.formName,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A2E)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    // Uses the shared handler — shows unsaved dialog if needed.
                    onChanged: _onTemplateSwitched,
                  ),
                ),
              ),
              const SizedBox(height: 20),

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
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Continue',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
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

  // ── Empty state ───────────────────────────────────────────────────────────

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
          Text('No forms available.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Pull down to refresh',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form content ──────────────────────────────────────────────────────────

  Widget _buildFormContent() {
    return Column(
      children: [
        _buildFormSelector(),
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
          Icon(Icons.warning_amber_rounded,
              color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_highlightedMissingFields.length} required field'
              '${_highlightedMissingFields.length == 1 ? '' : 's'} still empty '
              '— highlighted below in red',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _highlightedMissingFields = {}),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 32)),
            child: Text('Dismiss',
                style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }

  /// In-form template selector strip (shown above the form fields).
  /// Also uses the shared _onTemplateSwitched handler.
  Widget _buildFormSelector() {
    return Container(
      color: AppColors.primaryBlue.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Form:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                      .map((t) => DropdownMenuItem(
                            value: t.templateId,
                            child: Text(
                              t.formName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  // Uses the shared handler — shows unsaved dialog if needed.
                  onChanged: _onTemplateSwitched,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────

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
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex == 1 ? 0 : _currentNavIndex,
      onTap: _onNavTap,
      backgroundColor: AppColors.primaryBlue,
      selectedItemColor: AppColors.highlight,
      unselectedItemColor: Colors.white60,
      selectedLabelStyle:
          const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
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