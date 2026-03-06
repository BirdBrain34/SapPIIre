// lib/web/screen/manage_forms_screen.dart
// REFACTORED: Uses DynamicFormRenderer — no more hardcoded GIS.dart imports.
// Staff selects template → starts session → QR autofills → finalize saves to client_submissions.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';

class ManageFormsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;

  const ManageFormsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
  });

  @override
  State<ManageFormsScreen> createState() => _ManageFormsScreenState();
}

class _ManageFormsScreenState extends State<ManageFormsScreen> {
  final _templateService = FormTemplateService();
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

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    debugPrint('🌐 Web: Loading templates...');
    final templates = await _templateService.fetchActiveTemplates(forceRefresh: true);
    debugPrint('📊 Web: Received ${templates.length} templates');
    setState(() {
      _templates = templates;
      _selectedTemplate = templates.isNotEmpty
          ? (templates.firstWhere(
              (t) => t.formName == 'General Intake Sheet',
              orElse: () => templates.first))
          : null;
      _isLoading = false;
    });
    if (_selectedTemplate != null) {
      debugPrint('✅ Web: Selected ${_selectedTemplate!.formName}');
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
      });

      _listenForMobileUpdates(_currentSessionId);
    } catch (e) {
      debugPrint('_createNewSession error: $e');
      setState(() => _isStartingSession = false);
    }
  }

  // ── Listen for mobile QR data via Realtime ────────────────
  void _listenForMobileUpdates(String sessionId) {
    _formSubscription?.cancel();
    _formSubscription = _supabase
        .from('form_submission')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isEmpty) return;
          final row = data.first;
          final incoming =
              row['form_data'] as Map<String, dynamic>? ?? {};
          if (incoming.isEmpty) return;
          if (!mounted) return;
          _formCtrl?.loadFromJson(incoming);
          setState(() {}); // refresh UI
        });
  }

  // ── Finalize: save to client_submissions ──────────────────
  Future<void> _finalizeEntry() async {
    if (_formCtrl == null || _selectedTemplate == null) return;
    setState(() => _isFinalizing = true);

    try {
      final formData = _formCtrl!.toJson();

      await _supabase.from('client_submissions').insert({
        'form_type': _selectedTemplate!.formName,
        'data': formData,
        'created_by': widget.cswd_id,
      });

      // Close the session
      await _supabase
          .from('form_submission')
          .update({'status': 'completed'})
          .eq('id', _currentSessionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entry saved to Applicants ✓'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }

      // Reset for next client
      setState(() {
        _sessionStarted = false;
        _currentSessionId = 'WAITING-FOR-SESSION';
        _isFinalizing = false;
      });
      _formSubscription?.cancel();
    } catch (e) {
      debugPrint('_finalizeEntry error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
      setState(() => _isFinalizing = false);
    }
  }

  Future<void> _handleLogout() async {
    _formSubscription?.cancel();
    if (_currentSessionId != 'WAITING-FOR-SESSION') {
      await _supabase
          .from('form_submission')
          .update({'status': 'closed'})
          .eq('id', _currentSessionId);
    }
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(page: const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget next;
    switch (screenPath) {
      case 'Dashboard':
        next = DashboardScreen(
            cswd_id: widget.cswd_id,
            role: widget.role,
            onLogout: _handleLogout);
        break;
      case 'Staff':
        next = ManageStaffScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      case 'CreateStaff':
        next = CreateStaffScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      case 'Applicants':
        next = ApplicantsScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      default:
        return;
    }
    Navigator.of(context)
        .pushReplacement(ContentFadeRoute(page: next));
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
      onLogout: _handleLogout,
      headerActions: [
        if (_sessionStarted) ...[
          _buildHeaderButton('New Session', Icons.refresh,
              onPressed: _createNewSession),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isFinalizing ? null : _finalizeEntry,
            icon: _isFinalizing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_alt, color: Colors.white, size: 18),
            label: const Text('Save to Applicants',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
      onNavigate: (path) => _navigateToScreen(context, path),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue))
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
                offset: const Offset(0, 8))
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
              child: const Icon(Icons.qr_code_2_rounded,
                  size: 44, color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 28),
            const Text('Ready to assist a client?',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 12),
            Text(
              'Select a form type and start a session. '
              'A QR code will be generated for the client to scan. '
              'Their data will autofill in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade600, height: 1.5),
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
                    color: AppColors.buttonOutlineBlue.withOpacity(0.4)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTemplate?.templateId,
                  items: _templates
                      .map((t) => DropdownMenuItem(
                          value: t.templateId,
                          child: Text(t.formName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))))
                      .toList(),
                  onChanged: (id) {
                    final tpl =
                        _templates.firstWhere((t) => t.templateId == id);
                    setState(() {
                      _selectedTemplate = tpl;
                      _formCtrl?.dispose();
                      _formCtrl =
                          FormStateController(template: tpl);
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
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded,
                        color: Colors.white),
                label: Text(
                  _isStartingSession ? 'Starting...' : 'Start Session',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
              const Text('Form:',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(width: 12),
              Container(
                width: 340,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.buttonOutlineBlue.withOpacity(0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTemplate!.templateId,
                    items: _templates
                        .map((t) => DropdownMenuItem(
                            value: t.templateId,
                            child: Text(t.formName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))))
                        .toList(),
                    onChanged: null, // locked once session started
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Session: ${_currentSessionId.split('-').first}...',
                style:
                    TextStyle(color: Colors.grey.shade500, fontSize: 12),
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
                      blurRadius: 20)
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
    return Container(
      width: 300,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Live Form QR',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Scan with SapPIIre Mobile',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20)),
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
                Text('How it works:',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                SizedBox(height: 6),
                Text('1. Client opens SapPIIre app',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 11)),
                Text('2. Selects fields to share',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 11)),
                Text('3. Scans this QR code',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 11)),
                Text('4. Form autofills instantly',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String label, IconData icon,
      {VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: AppColors.primaryBlue),
      label: Text(label,
          style: const TextStyle(
              color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.buttonOutlineBlue),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
