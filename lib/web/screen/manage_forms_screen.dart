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
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';

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
  final ScrollController _formScrollController = ScrollController();
  final ScrollController _qrSidebarScrollController = ScrollController();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();

  List<FormTemplate> _templates = [];
  FormTemplate? _selectedTemplate;
  FormStateController? _formCtrl;

  String _currentSessionId = 'WAITING-FOR-SESSION';
  StreamSubscription? _formSubscription;

  bool _sessionStarted = false;
  bool _isStartingSession = false;
  bool _isLoading = true;
  bool _isFinalizing = false;
  bool _isSubmitting = false;
  String _lastSavedReference = '';
  String? _lastAppliedPayloadFingerprint;

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
    debugPrint('Web: Loading templates...');
    final templates = await _templateService.fetchActiveTemplates(
      forceRefresh: true,
    );
    debugPrint('Web: Received ${templates.length} templates');
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
      debugPrint('Web: Selected ${_selectedTemplate!.formName}');
      _formCtrl = FormStateController(template: _selectedTemplate!);
    }
  }

  // ── Start a new QR session ────────────────────────────────
  Future<void> _createNewSession() async {
    if (_selectedTemplate == null) return;
    _setStatePreserveScroll(() => _isStartingSession = true);

    try {
      // Close previous session if open
      if (_currentSessionId != 'WAITING-FOR-SESSION') {
        await _submissionService.updateSessionStatus(_currentSessionId, 'closed');
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
        _lastAppliedPayloadFingerprint = null;
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
      debugPrint('_createNewSession error: $e');
      _setStatePreserveScroll(() => _isStartingSession = false);
    }
  }

  // Listen for mobile QR data via Supabase Realtime
  void _listenForMobileUpdates(String sessionId) {
    debugPrint('Web: Starting realtime listener for session $sessionId');
    _formSubscription?.cancel();
    _formSubscription = _submissionService
        .streamSession(sessionId)
        .listen(
          (List<Map<String, dynamic>> data) {
            debugPrint('Web: Realtime update received');
            if (data.isEmpty) {
              debugPrint('Web: Data is empty');
              return;
            }
            _applySessionRow(data.first);
          },
          onError: (e) {
            debugPrint('Session stream error: $e');
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
    Timer.periodic(const Duration(seconds: 2), (timer) {
      pollCount++;
      if (pollCount > 15 || !mounted || _currentSessionId != sessionId) {
        timer.cancel();
        return;
      }
      _hydrateFromSessionSnapshot(sessionId);
    });
  }

  void _applySessionRow(Map<String, dynamic> row) {
    debugPrint('\n=== WEB WORKER SCREEN: Received Realtime Update ===');
    debugPrint('Web: Row status: ${row['status']}');
    final incoming = row['form_data'] as Map<String, dynamic>? ?? {};
    debugPrint('Web: Incoming data keys: ${incoming.keys.toList()}');
    debugPrint('Web: Incoming data size: ${incoming.length} fields');
    if (incoming.isEmpty) {
      debugPrint(
        'Web: ⚠️ Incoming data is EMPTY - mobile may not have transmitted yet',
      );
      debugPrint('===================================================\n');
      return;
    }

    final fingerprint = _fingerprintPayload(incoming);
    if (fingerprint != null && fingerprint == _lastAppliedPayloadFingerprint) {
      debugPrint('Web: ♻️ Duplicate payload detected, skipping re-apply');
      debugPrint('===================================================\n');
      return;
    }
    _lastAppliedPayloadFingerprint = fingerprint;

    if (!mounted) return;
    final currentFormOffset = _formScrollController.hasClients
        ? _formScrollController.offset
        : 0.0;
    debugPrint('Web: ✅ Loading data into form controller...');
    _formCtrl?.loadFromJson(incoming);
    _setStatePreserveScroll(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_formScrollController.hasClients) return;
      final max = _formScrollController.position.maxScrollExtent;
      final target = currentFormOffset.clamp(0.0, max);
      _formScrollController.jumpTo(target);
    });
    debugPrint(
      'Web: ✅ Form updated successfully with ${incoming.length} fields',
    );
    debugPrint('===================================================\n');
  }

  String? _fingerprintPayload(Map<String, dynamic> payload) {
    try {
      final normalized = _normalizeForFingerprint(payload);
      return jsonEncode(normalized);
    } catch (_) {
      return payload.toString();
    }
  }

  dynamic _normalizeForFingerprint(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final normalized = <String, dynamic>{};
      for (final key in keys) {
        normalized[key] = _normalizeForFingerprint(value[key]);
      }
      return normalized;
    }
    if (value is List) {
      return value.map(_normalizeForFingerprint).toList();
    }
    return value;
  }

  Future<void> _hydrateFromSessionSnapshot(String sessionId) async {
    try {
      debugPrint('Web: Polling session $sessionId for data...');
      final row = await _submissionService.fetchSessionSnapshot(sessionId);

      if (row == null) {
        debugPrint('Web: Session not found in database');
        return;
      }

      final formData = row['form_data'] as Map<String, dynamic>? ?? {};
      if (formData.isNotEmpty) {
        debugPrint(
          'Web: ✅ Found data via polling! Keys: ${formData.keys.toList()}',
        );
      }

      _applySessionRow(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('Session snapshot hydrate error: $e');
    }
  }

  // ── Finalize: save form data to client_submissions ───────
  Future<void> _finalizeEntry() async {
    if (_formCtrl == null || _selectedTemplate == null) return;
    // Guard: prevent double finalize taps from creating duplicate submissions.
    if (_isSubmitting) return;
    _setStatePreserveScroll(() {
      _isSubmitting = true;
      _isFinalizing = true;
    });

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

      for (final field in _selectedTemplate!.allFields) {
        if (field.fieldType != FormFieldType.computed) continue;
        if (formData.containsKey(field.fieldName)) continue;

        final scannedValue = scannedData[field.fieldName];
        if (scannedValue == null) continue;
        if (scannedValue.toString().trim().isEmpty) continue;

        formData[field.fieldName] = scannedValue;
      }

      // Embed applicant name + session ID for traceability
      await _embedApplicantName(formData);
      formData['__session_id'] = _currentSessionId;

      // Save field values to submission_field_values
      await _fieldValueService.pushToSubmission(
        sessionId: _currentSessionId,
        template: _selectedTemplate!,
        formData: formData,
      );

      // ── Audit copy (JSONB keeps __family_composition for record) ──
      // Idempotent save keyed by session_id so repeated submits update one row.
      final created = await _submissionService.upsertClientSubmission(
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
                  ? 'Entry saved ✓ Reference: $intakeReference'
                  : 'Entry saved to Applicants ✓',
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

      // Revert customer display to standby
      await _displayService.resetStation(_stationId);
    } catch (e) {
      debugPrint('_finalizeEntry error: $e');
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
    final template = _selectedTemplate;
    if (template == null) return 'N/A';
    if (!template.requiresReference) return 'Reference disabled for this form';

    final now = DateTime.now();
    var preview = template.referenceFormat;
    final prefix =
        (template.referencePrefix?.trim().isNotEmpty == true
                ? template.referencePrefix!
                : (template.formCode?.trim().isNotEmpty == true
                      ? template.formCode!
                      : 'FORM'))
            .toUpperCase();

    String pad(int v, int len) => v.toString().padLeft(len, '0');
    final yearStart = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(yearStart).inDays + 1;
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final weekOfYear = ((dayOfYear - 1) ~/ 7) + 1;

    preview = preview.replaceAll('{FORMCODE}', prefix);
    preview = preview.replaceAll('{YYYY}', now.year.toString());
    preview = preview.replaceAll('{YY}', now.year.toString().substring(2));
    preview = preview.replaceAll('{MM}', pad(now.month, 2));
    preview = preview.replaceAll(
      '{MON}',
      const [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ][now.month - 1],
    );
    preview = preview.replaceAll(
      '{MONTH}',
      const [
        'JANUARY',
        'FEBRUARY',
        'MARCH',
        'APRIL',
        'MAY',
        'JUNE',
        'JULY',
        'AUGUST',
        'SEPTEMBER',
        'OCTOBER',
        'NOVEMBER',
        'DECEMBER',
      ][now.month - 1],
    );
    preview = preview.replaceAll('{DD}', pad(now.day, 2));
    preview = preview.replaceAll('{DDD}', pad(dayOfYear, 3));
    preview = preview.replaceAll('{Q}', '$quarter');
    preview = preview.replaceAll('{WW}', pad(weekOfYear, 2));
    preview = preview.replaceAll('{IW}', pad(weekOfYear, 2));
    preview = preview.replaceAll('{HH24}', pad(now.hour, 2));
    preview = preview.replaceAll('{MI}', pad(now.minute, 2));
    preview = preview.replaceAll('{SS}', pad(now.second, 2));

    preview = preview.replaceAll('{########}', '????????');
    preview = preview.replaceAll('{######}', '??????');
    preview = preview.replaceAll('{####}', '????');
    preview = preview.replaceAll('{###}', '???');
    preview = preview.replaceAll('{##}', '??');
    preview = preview.replaceAll('{#}', '?');
    return preview;
  }

  /// Resolves a user's name via canonical_field_key values in form_fields.
  /// Works even when template autofill_source is not configured.
  Future<Map<String, String>?> _resolveNameViaCanonicalRpc(
    String userId,
  ) async {
    try {
      final row = await _submissionService.fetchCanonicalNameByUserId(userId);
      if (row == null) return null;

      final last = (row['last'] ?? '').trim();
      final first = (row['first'] ?? '').trim();
      final mid = (row['middle'] ?? '').trim();

      if (last.isEmpty && first.isEmpty) return null;
      return {'last': last, 'first': first, 'middle': mid};
    } catch (e) {
      debugPrint('_resolveNameViaCanonicalRpc error: $e');
      return null;
    }
  }

  /// Embeds __applicant_name into the JSONB data.
  /// Tries: 1) session user_id → canonical key RPC, 2) autofill_source fields,
  /// 3) brute-force key name matching.
  Future<void> _embedApplicantName(Map<String, dynamic> formData) async {
    // Strategy 1: session → user_id → canonical key lookup.
    if (_currentSessionId != 'WAITING-FOR-SESSION') {
      try {
        final userId = await _submissionService.fetchSessionUserId(
          _currentSessionId,
        );

        if (userId != null && userId.isNotEmpty) {
          final name = await _resolveNameViaCanonicalRpc(userId);
          if (name != null) {
            formData['__applicant_name'] = name;
            return;
          }
        }
      } catch (e) {
        debugPrint('_embedApplicantName error: $e');
      }
    }

    // Strategy 2: template fields with autofill_source
    if (_selectedTemplate != null) {
      String last = '', first = '', mid = '';
      for (final field in _selectedTemplate!.allFields) {
        final src = field.autofillSource;
        if (src == 'lastname')
          last = formData[field.fieldName]?.toString() ?? '';
        if (src == 'firstname')
          first = formData[field.fieldName]?.toString() ?? '';
        if (src == 'middle_name')
          mid = formData[field.fieldName]?.toString() ?? '';
      }
      if (last.isNotEmpty || first.isNotEmpty) {
        formData['__applicant_name'] = {
          'last': last,
          'first': first,
          'middle': mid,
        };
        return;
      }
    }

    // Strategy 3: match common name patterns in JSONB keys
    String last = '', first = '', mid = '';
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      final val = formData[key]?.toString() ?? '';
      if (val.isEmpty) continue;
      if (lk.contains('last') && lk.contains('name') && last.isEmpty)
        last = val;
      if (lk.contains('first') && lk.contains('name') && first.isEmpty)
        first = val;
      if (lk.contains('middle') && lk.contains('name') && mid.isEmpty)
        mid = val;
    }
    if (last.isNotEmpty || first.isNotEmpty) {
      formData['__applicant_name'] = {
        'last': last,
        'first': first,
        'middle': mid,
      };
    }
  }

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

  void _navigateToScreen(BuildContext context, String screenPath) {
    if ((screenPath == 'Staff' || screenPath == 'CreateStaff') &&
        widget.role != 'superadmin') {
      return;
    }
    Widget next;
    switch (screenPath) {
      case 'Dashboard':
        next = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
          onLogout: _handleLogout,
        );
        break;
      case 'Staff':
        next = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'CreateStaff':
        next = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'Applicants':
        next = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'FormBuilder':
        if (widget.role != 'superadmin') return;
        next = FormBuilderScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'AuditLogs':
        if (widget.role != 'superadmin') return;
        next = AuditLogsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      default:
        return;
    }
    _confirmLeave().then((ok) {
      if (!ok || !mounted) return;
      Navigator.of(context).pushReplacement(ContentFadeRoute(page: next));
    });
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PageStorage(
      bucket: _pageStorageBucket,
      child: WebShell(
        activePath: 'Forms',
        pageTitle: 'Forms Management',
        pageSubtitle: _sessionStarted
            ? 'Session active — client can scan the QR code'
            : 'Start a session to generate a QR code',
        role: widget.role,
        cswd_id: widget.cswd_id,
        displayName: widget.displayName,
        onLogout: _handleLogout,
        headerActions: [
          // "Open Customer Display" button — always visible
          _buildHeaderButton(
            'Open Customer Display',
            Icons.desktop_windows,
            onPressed: _openCustomerDisplay,
          ),
          if (_sessionStarted) ...[
            const SizedBox(width: 8),
            _buildHeaderButton(
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
        onNavigate: (path) => _navigateToScreen(context, path),
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

  // ── Gate: before session starts ───────────────────────────
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
              color: Colors.black.withOpacity(0.07),
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
                  color: AppColors.buttonOutlineBlue.withOpacity(0.35),
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
                    final tpl = _templates.firstWhere(
                      (t) => t.templateId == id,
                    );
                    _setStatePreserveScroll(() {
                      _selectedTemplate = tpl;
                      _formCtrl?.dispose();
                      _formCtrl = FormStateController(template: tpl);
                    });
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

  // ── Active session: QR sidebar + dynamic form ─────────────
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
                        color: AppColors.buttonOutlineBlue.withOpacity(0.38),
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
                        onChanged: null,
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
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // ── QR sidebar ──────────────────────────────
                  _buildQrSidebar(),

                  // ── Dynamic form (scrollable) ───────────────
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
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
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
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                      data: _currentSessionId,
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
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
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
                        color: Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.45),
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
                      color: Colors.white.withOpacity(0.1),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderButton(
    String label,
    IconData icon, {
    VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: AppColors.primaryBlue),
      label: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.buttonOutlineBlue),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _formSubscription?.cancel();
    _formCtrl?.dispose();
    _formScrollController.dispose();
    _qrSidebarScrollController.dispose();
    super.dispose();
  }
}
