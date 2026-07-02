// Web Forms Management Screen
// Staff interface for managing client form submissions via QR code.
//
// Flow:
// 1. Staff selects a form template
// 2. Starts a session and generates QR code
// 3. Client scans QR code with mobile app
// 4. Client's data is transmitted and autofills the form in real-time
// 5. Staff reviews and saves the submission to client_submissions table
//
// Uses Supabase Realtime to listen for incoming data from mobile.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/display_session_service.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/widgets/web_header_button.dart';
import 'package:sappiire/web/widgets/confirm_dialog.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/web/controllers/manage_forms_controller.dart';

class ManageFormsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;

  const ManageFormsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
  });

  @override
  State<ManageFormsScreen> createState() => _ManageFormsScreenState();
}

class _ManageFormsScreenState extends State<ManageFormsScreen> {
  final _templateService = FormTemplateService();
  final _displayService = DisplaySessionService();
  final _fieldValueService = FieldValueService();
  final _submissionService = SubmissionService();
  final _manageFormsController = ManageFormsController();
  final ScrollController _formScrollController = ScrollController();
  final ScrollController _qrSidebarScrollController = ScrollController();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();

  List<FormTemplate> _templates = [];
  FormTemplate? _selectedTemplate;
  FormStateController? _formCtrl;

  String _currentSessionId = 'WAITING-FOR-SESSION';
  StreamSubscription? _formSubscription;
  Timer? _pollTimer;

  bool _sessionStarted = false;
  bool _isStartingSession = false;
  bool _isLoading = true;
  bool _isFinalizing = false;
  bool _isSubmitting = false;
  String _lastSavedReference = '';
  
  /// Derive a stable station ID from the worker's cswd_id.
  String get _stationId => 'desk_${widget.cswd_id}';

  void _setStatePreserveScroll(VoidCallback fn) {
    final formOffset = _formScrollController.hasClients
        ? _formScrollController.offset
        : null;
    final qrOffset = _qrSidebarScrollController.hasClients
        ? _qrSidebarScrollController.offset
        : null;

    if (!mounted) return;
    setState(fn);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (formOffset != null && _formScrollController.hasClients) {
        final max = _formScrollController.position.maxScrollExtent;
        _formScrollController.jumpTo(formOffset.clamp(0.0, max));
      }

      if (qrOffset != null && _qrSidebarScrollController.hasClients) {
        final max = _qrSidebarScrollController.position.maxScrollExtent;
        _qrSidebarScrollController.jumpTo(qrOffset.clamp(0.0, max));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    debugPrint('[ManageFormsScreen/_loadTemplates] Action: Loading templates');
    final templates = await _templateService.fetchActiveTemplates(
      forceRefresh: true,
    );
    debugPrint(
      '[ManageFormsScreen/_loadTemplates] Action: Received templates Count: ${templates.length}',
    );
    _setStatePreserveScroll(() {
      _templates = templates;
      _selectedTemplate = templates.isNotEmpty
          ? (templates.firstWhere(
              (t) => t.formName == 'General Intake Sheet',
              orElse: () => templates.first,
            ))
          : null;
      _isLoading = false;
    });
    if (_selectedTemplate != null) {
      debugPrint(
        '[ManageFormsScreen/_loadTemplates] Action: Selected template ${_selectedTemplate!.formName}',
      );
      _formCtrl = FormStateController(template: _selectedTemplate!);
    }
  }

  Future<void> _selectTemplate(FormTemplate template) async {
    if (_selectedTemplate?.templateId == template.templateId) {
      return;
    }

    if (_sessionStarted && !await _confirmTemplateSwitch(template)) {
      return;
    }

    _setStatePreserveScroll(() {
      _selectedTemplate = template;
      _formCtrl?.dispose();
      _formCtrl = FormStateController(template: template);
    });

    if (_sessionStarted && _currentSessionId != 'WAITING-FOR-SESSION') {
      await _displayService.pushSession(
        stationId: _stationId,
        sessionId: _currentSessionId,
        templateId: template.templateId,
        formName: template.formName,
      );
    }
  }

  Future<bool> _confirmTemplateSwitch(FormTemplate template) {
    return showConfirmDialog(
      context,
      title: 'Switch forms?',
      message:
          'Changing the selected form while a session is active will update the live view to "${template.formName}". Continue?',
      confirmLabel: 'Switch',
    );
  }

  // Start a new QR session
  Future<void> _createNewSession() async {
    if (_selectedTemplate == null) return;
    _setStatePreserveScroll(() => _isStartingSession = true);

    try {
      // Close previous session if open
      if (_currentSessionId != 'WAITING-FOR-SESSION') {
        await _submissionService.updateSessionStatus(
          _currentSessionId,
          'closed',
        );
      }

      // Reset form state
      _formCtrl?.clearAll();
      _formSubscription?.cancel();

      final response = await _submissionService.createSession(
        _selectedTemplate!.formName,
      );

      _setStatePreserveScroll(() {
        _currentSessionId = response['id'].toString();
        _sessionStarted = true;
        _isStartingSession = false;
        _lastSavedReference = '';
      });

      await AuditLogService().log(
        actionType: kAuditSessionStarted,
        category: kCategorySession,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'form_session',
        targetId: _currentSessionId,
        targetLabel: _selectedTemplate?.formName,
        details: {
          'template_id': _selectedTemplate?.templateId,
          'form_name': _selectedTemplate?.formName,
        },
      );

      _listenForMobileUpdates(_currentSessionId);

      // Push to display_sessions so the customer monitor updates
      await _displayService.pushSession(
        stationId: _stationId,
        sessionId: _currentSessionId,
        templateId: _selectedTemplate!.templateId,
        formName: _selectedTemplate!.formName,
      );
    } catch (e) {
      debugPrint('[ManageFormsScreen/_createNewSession] Error: $e');
      _setStatePreserveScroll(() => _isStartingSession = false);
    }
  }

  // Listen for mobile QR data via Supabase Realtime
  void _listenForMobileUpdates(String sessionId) {
    debugPrint(
      '[ManageFormsScreen/_listenForMobileUpdates] Action: Starting realtime listener SessionId=$sessionId',
    );
    _pollTimer?.cancel();
    _formSubscription?.cancel();
    _formSubscription = _submissionService
        .streamSession(sessionId)
        .listen(
          (List<Map<String, dynamic>> data) {
            debugPrint(
              '[ManageFormsScreen/_listenForMobileUpdates] Action: Realtime update received',
            );
            if (data.isEmpty) {
              debugPrint(
                '[ManageFormsScreen/_listenForMobileUpdates] Action: Data is empty',
              );
              return;
            }
            _applySessionRow(data.first);
          },
          onError: (e) {
            debugPrint('[ManageFormsScreen/_listenForMobileUpdates] Error: $e');
            // On error, try to fetch data directly
            _hydrateFromSessionSnapshot(sessionId);
          },
          cancelOnError: false,
        );

    // Cold-start race guard: if mobile updates before the stream fully attaches,
    // fetch current session state directly and hydrate multiple times.
    _hydrateFromSessionSnapshot(sessionId);
    Future.delayed(const Duration(milliseconds: 500), () {
      _hydrateFromSessionSnapshot(sessionId);
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      _hydrateFromSessionSnapshot(sessionId);
    });
    Future.delayed(const Duration(milliseconds: 3000), () {
      _hydrateFromSessionSnapshot(sessionId);
    });

    // Set up periodic polling as backup (every 2 seconds for first 30 seconds)
    int pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      pollCount++;
      if (pollCount > 15 || !mounted || _currentSessionId != sessionId) {
        timer.cancel();
        return;
      }
      _hydrateFromSessionSnapshot(sessionId);
    });
  }

  void _applySessionRow(Map<String, dynamic> row) {
    debugPrint(
      '[ManageFormsScreen/_applySessionRow] Action: Realtime update received',
    );
    final status = row['status'] as String? ?? '';
    debugPrint(
      '[ManageFormsScreen/_applySessionRow] Action: Row status $status',
    );

    // Delegate encryption detection to controller (form_data column was removed)
    if (_manageFormsController.shouldDecrypt(row)) {
      debugPrint(
        '[ManageFormsScreen/_applySessionRow] Action: Scanned session detected, decrypting via controller',
      );
      _hydrateDecrypted();
      return;
    }

    // Active session with no data yet — wait for mobile to scan
    debugPrint(
      '[ManageFormsScreen/_applySessionRow] Action: No payload available yet',
    );
  }

  /// Fetches decrypted data from the controller and loads it into the form.
  /// Delegates all crypto/Supabase logic to ManageFormsController.
  Future<void> _hydrateDecrypted() async {
    if (_manageFormsController.isDecrypting) return;

    final decrypted = await _manageFormsController.decryptStagingSubmission(
      sessionId: _currentSessionId,
      staffId: widget.cswd_id,
    );

    if (decrypted == null || decrypted.isEmpty) {
      debugPrint('[ManageFormsScreen/_hydrateDecrypted] Decryption returned null or empty');
      return;
    }

    debugPrint(
      '[ManageFormsScreen/_hydrateDecrypted] Decrypted keys: ${decrypted.keys.toList()}',
    );

    if (!mounted) return;
    final currentFormOffset = _formScrollController.hasClients
        ? _formScrollController.offset
        : 0.0;

    _formCtrl?.loadFromJson(decrypted);
    _setStatePreserveScroll(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_formScrollController.hasClients) return;
      final max = _formScrollController.position.maxScrollExtent;
      final target = currentFormOffset.clamp(0.0, max);
      _formScrollController.jumpTo(target);
    });
    debugPrint(
      '[ManageFormsScreen/_hydrateDecrypted] Form updated successfully Count: ${decrypted.length}',
    );
  }

  Future<void> _hydrateFromSessionSnapshot(String sessionId) async {
    try {
      debugPrint(
        '[ManageFormsScreen/_hydrateFromSessionSnapshot] Action: Polling session $sessionId for data',
      );
      final row = await _submissionService.fetchSessionSnapshot(sessionId);

      if (row == null) {
        debugPrint(
          '[ManageFormsScreen/_hydrateFromSessionSnapshot] Action: Session not found in database',
        );
        return;
      }

      final status = row['status'] as String? ?? '';

      if (status == 'scanned') {
        // Polling detected a scanned session with empty form_data.
        // Try on-demand decryption directly here as a backup.
        debugPrint(
          '[ManageFormsScreen/_hydrateFromSessionSnapshot] Action: Polling found scanned session with empty form_data, trying decrypt via controller',
        );
        _hydrateDecrypted();
        return;
      }

      _applySessionRow(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('[ManageFormsScreen/_hydrateFromSessionSnapshot] Error: $e');
    }
  }

  bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is Iterable) return value.any(_hasMeaningfulValue);
    if (value is Map) return value.values.any(_hasMeaningfulValue);
    return value.toString().trim().isNotEmpty;
  }

  bool _hasMeaningfulFormData(
    FormTemplate template,
    Map<String, dynamic> data, {
    bool includeComputed = false,
  }) {
    for (final field in template.allFields) {
      if (!includeComputed && field.fieldType == FormFieldType.computed) {
        continue;
      }
      if (!data.containsKey(field.fieldName)) continue;
      if (_hasMeaningfulValue(data[field.fieldName])) return true;
    }
    return false;
  }

  Future<void> _showEmptyFormSaveBlockedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot save form'),
        content: const Text(
          'Cannot save form. The form is empty and has not been scanned by the mobile app. Please scan the form before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Finalize the active session by saving form data to client_submissions.
  Future<void> _finalizeEntry() async {
    if (_formCtrl == null || _selectedTemplate == null) return;
    // Prevent duplicate finalize taps from creating duplicate submissions.
    if (_isSubmitting) return;

    try {
      final formData = _formCtrl!.toJson();

      // Preserve scanned computed values if controller serialization omitted them.
      final snapshot = await _submissionService.fetchSessionSnapshot(
        _currentSessionId,
      );
      final snapshotRaw = snapshot?['form_data'];
      final scannedData = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};

      final hasUserEnteredData = _hasMeaningfulFormData(
        _selectedTemplate!,
        formData,
      );
      final hasScannedData = _hasMeaningfulFormData(
        _selectedTemplate!,
        scannedData,
        includeComputed: true,
      );

      if (!hasUserEnteredData && !hasScannedData) {
        await _showEmptyFormSaveBlockedDialog();
        return;
      }

      _setStatePreserveScroll(() {
        _isSubmitting = true;
        _isFinalizing = true;
      });

      await _manageFormsController.preserveComputedValues(
        template: _selectedTemplate!,
        targetData: formData,
        sourceData: scannedData,
      );

      // Embed applicant name + session ID for traceability
      await _embedApplicantName(formData);
      formData['__session_id'] = _currentSessionId;

      // pushToSubmission is removed — plaintext is no longer written to
      // submission_field_values. The encrypted path via
      // upsertClientSubmissionSecure is used instead (below).

      // Audit copy (JSONB keeps full submitted data for record)
      // Idempotent save keyed by session_id so repeated submits update one row.
      final created = await _submissionService.upsertClientSubmissionSecure(
        sessionId: _currentSessionId,
        templateId: _selectedTemplate!.templateId,
        formCode: _selectedTemplate!.formCode,
        formType: _selectedTemplate!.formName,
        data: formData,
        createdBy: widget.cswd_id,
      );

      final intakeReference = (created['intake_reference'] as String?) ?? '';

      await AuditLogService().log(
        actionType: kAuditSubmissionCreated,
        category: kCategorySubmission,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'client_submission',
        targetId: created['id']?.toString() ?? _currentSessionId,
        targetLabel: _selectedTemplate?.formName,
        details: {
          'form_type': _selectedTemplate?.formName,
          'session_id': _currentSessionId,
          'intake_reference': intakeReference,
          'encryption': 'server_aes_256_gcm',
        },
      );

      // Close the session
      await _submissionService.updateSessionStatus(
        _currentSessionId,
        'completed',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              intakeReference.isNotEmpty
                  ? 'Entry saved Reference: $intakeReference'
                  : 'Entry saved to Applicants',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Reset for next client
      _setStatePreserveScroll(() {
        _sessionStarted = false;
        _currentSessionId = 'WAITING-FOR-SESSION';
        _isFinalizing = false;
        _isSubmitting = false;
        _lastSavedReference = intakeReference;
      });
      _formSubscription?.cancel();

      // Return the customer display to standby after finalizing.
      await _displayService.resetStation(_stationId);
    } catch (e) {
      debugPrint('[ManageFormsScreen/_finalizeEntry] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _setStatePreserveScroll(() {
        _isFinalizing = false;
        _isSubmitting = false;
      });
    }
  }

  String _buildTempReferencePreview() {
    return _manageFormsController.buildTempReferencePreview(_selectedTemplate);
  }

  /// Embeds __applicant_name into the JSONB data.
  /// Tries: 1) session user_id via Edge Function B, 2) autofill_source fields,
  /// 3) brute-force key name matching.
  Future<void> _embedApplicantName(Map<String, dynamic> formData) =>
      _manageFormsController.embedApplicantName(
        currentSessionId: _currentSessionId,
        selectedTemplate: _selectedTemplate,
        formData: formData,
        staffId: widget.cswd_id,
      );

  /// Open the customer-facing display in a new browser window.
  void _openCustomerDisplay() {
    if (kIsWeb) {
      final url = '/#/display?station=${Uri.encodeComponent(_stationId)}';
      launchUrl(Uri.parse(url));
    }
  }

  /// Returns true if navigation should proceed (no active session, or user confirmed).
  Future<bool> _confirmLeave() async {
    if (!_sessionStarted) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Session'),
        content: const Text(
          'You have an active session with unsaved data. Leave anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleLogout() async {
    if (!await _confirmLeave()) return;
    _formSubscription?.cancel();
    if (_currentSessionId != 'WAITING-FOR-SESSION') {
      await _submissionService.updateSessionStatus(_currentSessionId, 'closed');
    }
    // Reset display monitor on logout
    await _displayService.resetStation(_stationId);
    await _submissionService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(page: const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return PageStorage(
      bucket: _pageStorageBucket,
      child: WebShell(
        activePath: 'Forms',
        pageTitle: 'Forms Management',
        pageSubtitle: _sessionStarted
            ? 'Session active client can scan the QR code'
            : 'Start a session to generate a QR code',
        role: widget.role,
        cswd_id: widget.cswd_id,
        displayName: widget.displayName,
        onLogout: _handleLogout,
        headerActions: [
          // "Open Customer Display" button always visible
          WebHeaderButton(
            'Open Customer Display',
            Icons.desktop_windows,
            onPressed: _openCustomerDisplay,
          ),
          if (_sessionStarted) ...[
            const SizedBox(width: 8),
            WebHeaderButton(
              'New Session',
              Icons.refresh,
              onPressed: _createNewSession,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isFinalizing ? null : _finalizeEntry,
              icon: _isFinalizing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_alt, color: Colors.white, size: 18),
              label: const Text(
                'Save to Applicants',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
        onNavigate: (path) => WebNavigator.go(
          context,
          path,
          cswdId: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
          onLogout: _handleLogout,
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue),
              )
            : _sessionStarted
            ? _buildActiveFormView()
            : _buildStartSessionGate(),
      ),
    );
  }

  // Gate: before session starts
  Widget _buildStartSessionGate() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE6EBF8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 34,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE9F0FF), Color(0xFFDDE8FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 44,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Session Setup',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Ready to assist a client?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Select a form type and start a session. '
              'A QR code will be generated for the client to scan and '
              'the form will autofill in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.buttonOutlineBlue.withValues(alpha: 0.35),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTemplate?.templateId,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more_rounded),
                  items: _templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.templateId,
                          child: Text(
                            t.formName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final tpl = _templates.firstWhere(
                      (t) => t.templateId == id,
                    );
                    unawaited(_selectTemplate(tpl));
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isStartingSession ? null : _createNewSession,
                icon: _isStartingSession
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                label: Text(
                  _isStartingSession ? 'Starting...' : 'Start Session',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Active session: QR sidebar + dynamic form
  Widget _buildActiveFormView() {
    if (_formCtrl == null || _selectedTemplate == null) {
      return const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6EBF8)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F9F1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fiber_manual_record,
                        size: 10,
                        color: Color(0xFF1B9E63),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Session Live',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF156D45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Form:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.buttonOutlineBlue.withValues(
                          alpha: 0.38,
                        ),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTemplate!.templateId,
                        isExpanded: true,
                        items: _templates
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.templateId,
                                child: Text(
                                  t.formName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final tpl = _templates.firstWhere(
                            (t) => t.templateId == id,
                          );
                          unawaited(_selectTemplate(tpl));
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Session: ${_currentSessionId.split('-').first}...',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryBlue, AppColors.midBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // QR sidebar
                  _buildQrSidebar(),

                  // Dynamic form (scrollable)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SingleChildScrollView(
                        key: const PageStorageKey<String>(
                          'manage_forms_form_scroll',
                        ),
                        controller: _formScrollController,
                        padding: const EdgeInsets.all(16),
                        child: DynamicFormRenderer(
                          template: _selectedTemplate!,
                          controller: _formCtrl!,
                          mode: 'web',
                          isReadOnly: kIsWeb,
                          showCheckboxes: false,
                        ),
                      ),
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
    final tempReference = _buildTempReferencePreview();
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _qrSidebarScrollController,
            padding: const EdgeInsets.only(right: 6),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Live Form QR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan with SapPIIre Mobile',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: QrImageView(
                      data: jsonEncode({
                        'sessionId': _currentSessionId,
                        'templateId': _selectedTemplate!.templateId,
                      }),
                      version: QrVersions.auto,
                      size: 184.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Session: ${_currentSessionId.split('-').first}...',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Temporary Reference',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tempReference,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Final value is generated when saved',
                          style: TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  if (_lastSavedReference.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Last Saved Reference',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _lastSavedReference,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Instructions
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How it works:',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '1. Client opens SapPIIre app',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          '2. Selects fields to share',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          '3. Scans this QR code',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          '4. Form autofills instantly',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        },
      ),
    );
  }

  @override
  void dispose() {
    _formSubscription?.cancel();
    _pollTimer?.cancel();
    _formCtrl?.dispose();
    _formScrollController.dispose();
    _qrSidebarScrollController.dispose();
    super.dispose();
  }
}
