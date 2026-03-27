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
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/form_builder_service.dart';
import 'package:sappiire/services/display_session_service.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/services/field_value_service.dart';
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
import 'package:sappiire/web/services/audit_log_service.dart';

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
  final _supabase = Supabase.instance.client;

  List<FormTemplate> _templates = [];
  FormTemplate? _selectedTemplate;
  FormStateController? _formCtrl;

  String _currentSessionId = 'WAITING-FOR-SESSION';
  StreamSubscription? _formSubscription;

  bool _sessionStarted = false;
  bool _isStartingSession = false;
  bool _isLoading = true;
  bool _isFinalizing = false;
  String _lastSavedReference = '';

  /// Derive a stable station ID from the worker's cswd_id.
  String get _stationId => 'desk_${widget.cswd_id}';

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
    setState(() {
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
    setState(() => _isStartingSession = true);

    try {
      // Close previous session if open
      if (_currentSessionId != 'WAITING-FOR-SESSION') {
        await _supabase
            .from('form_submission')
            .update({'status': 'closed'})
            .eq('id', _currentSessionId);
      }

      // Reset form state
      _formCtrl?.clearAll();
      _formSubscription?.cancel();

      final response = await _supabase
          .from('form_submission')
          .insert({
            'status': 'active',
            'form_type': _selectedTemplate!.formName,
            'form_data': {},
          })
          .select()
          .single();

      setState(() {
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
      debugPrint('_createNewSession error: $e');
      setState(() => _isStartingSession = false);
    }
  }

  // Listen for mobile QR data via Supabase Realtime
  void _listenForMobileUpdates(String sessionId) {
    debugPrint('Web: Starting realtime listener for session $sessionId');
    _formSubscription?.cancel();
    _formSubscription = _supabase
        .from('form_submission')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .timeout(const Duration(minutes: 30), onTimeout: (sink) => sink.close())
        .listen(
          (List<Map<String, dynamic>> data) {
            debugPrint('Web: Realtime update received');
            if (data.isEmpty) {
              debugPrint('Web: Data is empty');
              return;
            }
            _applySessionRow(data.first);
          },
          onError: (e) => debugPrint('Session stream error: $e'),
          cancelOnError: false,
        );

    // Cold-start race guard: if mobile updates before the stream fully attaches,
    // fetch current session state directly and hydrate once.
    _hydrateFromSessionSnapshot(sessionId);
    Future.delayed(const Duration(milliseconds: 800), () {
      _hydrateFromSessionSnapshot(sessionId);
    });
  }

  void _applySessionRow(Map<String, dynamic> row) {
    debugPrint('Web: Row status: ${row['status']}');
    final incoming = row['form_data'] as Map<String, dynamic>? ?? {};
    debugPrint('Web: Incoming data keys: ${incoming.keys.toList()}');
    debugPrint('Web: Incoming data size: ${incoming.length} fields');
    if (incoming.isEmpty) {
      debugPrint('Web: Incoming data is empty, skipping');
      return;
    }
    if (!mounted) return;
    debugPrint('Web: Loading data into form controller');
    _formCtrl?.loadFromJson(incoming);
    setState(() {});
    debugPrint('Web: Form updated successfully');
  }

  Future<void> _hydrateFromSessionSnapshot(String sessionId) async {
    try {
      final row = await _supabase
          .from('form_submission')
          .select('id, status, form_data')
          .eq('id', sessionId)
          .maybeSingle();

      if (row == null) return;
      _applySessionRow(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('Session snapshot hydrate error: $e');
    }
  }

  // ── Finalize: save form data to client_submissions ───────
  Future<void> _finalizeEntry() async {
    if (_formCtrl == null || _selectedTemplate == null) return;
    setState(() => _isFinalizing = true);

    try {
      final formData = _formCtrl!.toJson();

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
      final created = await _supabase
          .from('client_submissions')
          .insert({
            'template_id': _selectedTemplate!.templateId,
            'form_code': _selectedTemplate!.formCode,
            'form_type': _selectedTemplate!.formName,
            'data': formData,
            'created_by': widget.cswd_id,
          })
          .select('id, intake_reference')
          .single();

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
      await _supabase
          .from('form_submission')
          .update({'status': 'completed'})
          .eq('id', _currentSessionId);

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
      setState(() {
        _sessionStarted = false;
        _currentSessionId = 'WAITING-FOR-SESSION';
        _isFinalizing = false;
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
      setState(() => _isFinalizing = false);
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

  /// Embeds __applicant_name into the JSONB data.
  /// Tries: 1) session user_id → user_profiles, 2) autofill_source fields,
  /// 3) brute-force key name matching.
  Future<void> _embedApplicantName(Map<String, dynamic> formData) async {
    // Strategy 1: session → user_profiles (most reliable)
    if (_currentSessionId != 'WAITING-FOR-SESSION') {
      try {
        final session = await _supabase
            .from('form_submission')
            .select('user_id')
            .eq('id', _currentSessionId)
            .maybeSingle();
        final userId = session?['user_id'] as String?;
        if (userId != null) {
          final profile = await _supabase
              .from('user_profiles')
              .select('lastname, firstname, middle_name')
              .eq('user_id', userId)
              .maybeSingle();
          if (profile != null) {
            final last = (profile['lastname'] ?? '').toString().trim();
            final first = (profile['firstname'] ?? '').toString().trim();
            final mid = (profile['middle_name'] ?? '').toString().trim();
            if (last.isNotEmpty || first.isNotEmpty) {
              formData['__applicant_name'] = {
                'last': last,
                'first': first,
                'middle': mid,
              };
              return;
            }
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
      await _supabase
          .from('form_submission')
          .update({'status': 'closed'})
          .eq('id', _currentSessionId);
    }
    // Reset display monitor on logout
    await _displayService.resetStation(_stationId);
    await _supabase.auth.signOut();
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
    return WebShell(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    );
  }

  // ── Gate: before session starts ───────────────────────────
  Widget _buildStartSessionGate() {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 8),
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
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 44,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Ready to assist a client?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a form type and start a session. '
              'A QR code will be generated for the client to scan. '
              'Their data will autofill in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Template selector
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.buttonOutlineBlue.withOpacity(0.4),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTemplate?.templateId,
                  isExpanded: true,
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
                    setState(() {
                      _selectedTemplate = tpl;
                      _formCtrl?.dispose();
                      _formCtrl = FormStateController(template: tpl);
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),

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
          // Template dropdown (read-only while session is active)
          Row(
            children: [
              const Text(
                'Form:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.buttonOutlineBlue.withOpacity(0.5),
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
                      onChanged: null, // locked once session started
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Session: ${_currentSessionId.split('-').first}...',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accentBlue,
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
                        padding: const EdgeInsets.all(16),
                        child: AnimatedBuilder(
                          animation: _formCtrl!,
                          builder: (context, _) => DynamicFormRenderer(
                            template: _selectedTemplate!,
                            controller: _formCtrl!,
                            mode: 'web',
                            showCheckboxes: false,
                          ),
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
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Live Form QR',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan with SapPIIre Mobile',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: _currentSessionId,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Session: ${_currentSessionId.split('-').first}...',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 14),
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
                border: Border.all(color: Colors.green.withOpacity(0.45)),
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
          const SizedBox(height: 24),

          // Instructions
          Container(
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
    super.dispose();
  }
}
