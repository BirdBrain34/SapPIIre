// lib/web/screen/applicants_screen.dart
// REFACTORED: Uses DynamicFormRenderer to display any saved form template.
// No more hardcoded GIS section imports.

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';

class _ApplicantGroup {
  final String key;
  final String displayName;
  final List<Map<String, dynamic>> submissions;

  const _ApplicantGroup({
    required this.key,
    required this.displayName,
    required this.submissions,
  });
}

enum _RecordSortOrder { latestFirst, oldestFirst }

enum _RightPanelView { records, form }

class ApplicantsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;

  const ApplicantsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
  });

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final _submissionService = SubmissionService();
  final _templateService = FormTemplateService();

  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _selectedSubmission;
  FormTemplate? _activeTemplate;
  FormStateController? _viewCtrl;
  FormStateController? _editCtrl;

  bool _isLoading = true;
  bool _isEditMode = false;
  bool _isSaving = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _intakeRefCtrl = TextEditingController();
  String? _selectedApplicantKey;
  _RecordSortOrder _recordSortOrder = _RecordSortOrder.latestFirst;
  _RightPanelView _rightPanelView = _RightPanelView.records;
  String _formTypeFilter = 'All';

  // Template cache by form_type name
  final Map<String, FormTemplate> _templateCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final templates = await _templateService.fetchActiveTemplates();
      for (final t in templates) {
        _templateCache[t.formName] = t;
      }

      final submissions = await _submissionService.fetchRecentClientSubmissions(
        limit: 100,
      );

      // Resolve names for older submissions that lack __applicant_name
      await _resolveUnknownNames(submissions);

      setState(() {
        _submissions = submissions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('_loadData error: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Resolves names for legacy submissions missing __applicant_name.
  /// Traces __session_id → form_submission.user_id → canonical key RPC in batch.
  Future<void> _resolveUnknownNames(
    List<Map<String, dynamic>> submissions,
  ) async {
    final needsResolution = <Map<String, dynamic>>[];
    
    // First, decrypt any encrypted submissions so we can read their data
    for (final sub in submissions) {
      final encryptionVersion = sub['data_encryption_version'] ?? 0;
      if (encryptionVersion == 1 && sub['data'] is String) {
        try {
          final decrypted = await _decryptSubmissionData(
            sub['id'].toString(),
          );
          // Replace encrypted string with decrypted Map in memory
          sub['data'] = decrypted;
        } catch (e) {
          debugPrint('Failed to decrypt submission for name resolution: $e');
          // Keep encrypted data, will show as "Unknown Applicant"
        }
      }
    }
    
    // Now check which submissions need name resolution
    for (final sub in submissions) {
      final data = sub['data'] is Map 
          ? Map<String, dynamic>.from(sub['data'] as Map)
          : <String, dynamic>{};
      if (_hasUsableEmbeddedApplicantName(data)) continue;
      final sid = data['__session_id']?.toString();
      if (sid != null && sid.isNotEmpty) needsResolution.add(sub);
    }

    if (needsResolution.isEmpty) return;

    final sessionIds = needsResolution
        .map(
          (s) {
            final data = s['data'] is Map
                ? Map<String, dynamic>.from(s['data'] as Map)
                : <String, dynamic>{};
            return data['__session_id']?.toString();
          },
        )
        .whereType<String>()
        .toSet()
        .toList();
    if (sessionIds.isEmpty) return;

    try {
      // session IDs → user_ids
      final sessionToUserId = await _submissionService.fetchSessionUserMap(
        sessionIds,
      );
      final userIds = sessionToUserId.values.toSet();

      if (userIds.isEmpty) return;

      // user_ids → names via canonical_field_key
      final userIdToName = await _submissionService
          .fetchCanonicalNamesByUserIds(userIds.toList());

      // Embed resolved names into submissions (mutates in place)
      for (final sub in needsResolution) {
        final data = sub['data'] is Map
            ? Map<String, dynamic>.from(sub['data'] as Map)
            : <String, dynamic>{};
        final sessionId = data['__session_id']?.toString();
        if (sessionId == null) continue;
        final userId = sessionToUserId[sessionId];
        if (userId == null) continue;
        final name = userIdToName[userId];
        if (name != null &&
            ((name['last'] ?? '').isNotEmpty ||
                (name['first'] ?? '').isNotEmpty)) {
          data['__applicant_name'] = name;
          sub['data'] = data; // Update the submission with the name
        }
      }
    } catch (e) {
      debugPrint('_resolveUnknownNames error: $e');
    }
  }

  // ── Load a submission into the detail panel ───────────────
  Future<void> _loadSubmission(Map<String, dynamic> submission) async {
    final formType = submission['form_type'] as String? ?? '';
    var data = submission['data'];
    final encryptionVersion = submission['data_encryption_version'] ?? 0;

    // Decrypt if server-encrypted
    if (encryptionVersion == 1 && data is String) {
      try {
        final decrypted = await _decryptSubmissionData(
          submission['id'].toString(),
        );
        data = decrypted;
      } catch (e) {
        debugPrint('Decryption failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to decrypt submission: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    final dataMap = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final template = _templateCache[formType];
    _intakeRefCtrl.text = (submission['intake_reference'] as String?) ?? '';

    _viewCtrl?.dispose();
    _editCtrl?.dispose();

    if (template == null) {
      // Unknown/deleted template — raw JSON fallback
      setState(() {
        _selectedSubmission = submission;
        _activeTemplate = null;
        _viewCtrl = null;
        _editCtrl = null;
        _isEditMode = false;
      });
      return;
    }

    final view = FormStateController(template: template)..loadFromJson(dataMap);
    final edit = FormStateController(template: template)..loadFromJson(dataMap);

    setState(() {
      _selectedSubmission = submission;
      _activeTemplate = template;
      _viewCtrl = view;
      _editCtrl = edit;
      _isEditMode = false;
    });
  }

  Future<Map<String, dynamic>> _decryptSubmissionData(
    String submissionId,
  ) async {
    final supabase = Supabase.instance.client;
    
    final response = await supabase.functions.invoke(
      'decrypt-submission-data',
      body: {
        'submissionId': submissionId,
        'staffId': widget.cswd_id,
      },
    );

    if (response.status != 200) {
      debugPrint('Decrypt error response: ${response.data}');
      throw Exception(response.data.toString());
    }

    final result = response.data as Map<String, dynamic>;
    return result['data'] as Map<String, dynamic>;
  }

  // ── Save edited submission ────────────────────────────────
  Future<void> _saveEdit() async {
    if (_editCtrl == null || _selectedSubmission == null) return;
    setState(() => _isSaving = true);
    try {
      final updatedData = _editCtrl!.toJson();
      final existingRaw = _selectedSubmission!['data'];
      final existingData = existingRaw is Map
          ? Map<String, dynamic>.from(existingRaw)
          : <String, dynamic>{};

      // Keep metadata keys (like __applicant_name / __session_id) if present.
      for (final entry in existingData.entries) {
        if (!entry.key.startsWith('__')) continue;
        updatedData.putIfAbsent(entry.key, () => entry.value);
      }

      // Preserve computed values if they were in storage and serializer omitted them.
      final template = _activeTemplate;
      if (template != null) {
        for (final field in template.allFields) {
          if (field.fieldType != FormFieldType.computed) continue;
          if (updatedData.containsKey(field.fieldName)) continue;

          final existingValue = existingData[field.fieldName];
          if (existingValue == null) continue;
          if (existingValue.toString().trim().isEmpty) continue;

          updatedData[field.fieldName] = existingValue;
        }
      }

      await _submissionService.updateClientSubmission(
        submissionId: _selectedSubmission!['id'],
        data: updatedData,
        intakeReference: _intakeRefCtrl.text.trim().isEmpty
            ? null
            : _intakeRefCtrl.text.trim(),
        editorId: widget.cswd_id,
      );

      await AuditLogService().log(
        actionType: kAuditSubmissionEdited,
        category: kCategorySubmission,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'client_submission',
        targetId: _selectedSubmission!['id'].toString(),
        targetLabel: _getApplicantName(_selectedSubmission!),
        details: {'form_type': _selectedSubmission!['form_type']},
      );

      await _loadData();
      setState(() {
        _isEditMode = false;
        _isSaving = false;
      });
      // Reload the same submission with fresh data
      final updated = _submissions.firstWhere(
        (s) => s['id'] == _selectedSubmission!['id'],
        orElse: () => {},
      );
      if (updated.isNotEmpty) _loadSubmission(updated);
    } catch (e) {
      debugPrint('_saveEdit error: $e');
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteSubmission() async {
    if (_selectedSubmission == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete applicant record?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AuditLogService().log(
      actionType: kAuditSubmissionDeleted,
      category: kCategorySubmission,
      severity: kSeverityCritical,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
      targetType: 'client_submission',
      targetId: _selectedSubmission!['id'].toString(),
      targetLabel: _getApplicantName(_selectedSubmission!),
      details: {'form_type': _selectedSubmission!['form_type']},
    );

    await _submissionService.deleteClientSubmission(_selectedSubmission!['id']);

    setState(() {
      _selectedSubmission = null;
      _activeTemplate = null;
      _viewCtrl?.dispose();
      _viewCtrl = null;
      _editCtrl?.dispose();
      _editCtrl = null;
      _isEditMode = false;
    });
    await _loadData();
  }

  Future<void> _deleteApplicant() async {
    final group = _selectedApplicantGroup;
    if (group == null) return;

    final count = group.submissions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entire applicant?'),
        content: Text(
          'This will permanently delete all $count form(s) for ${group.displayName}. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Delete all submissions for this applicant
    final idsToDelete = <dynamic>[];
    for (final submission in group.submissions) {
      await AuditLogService().log(
        actionType: kAuditSubmissionDeleted,
        category: kCategorySubmission,
        severity: kSeverityCritical,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'client_submission',
        targetId: submission['id'].toString(),
        targetLabel: _getApplicantName(submission),
        details: {'form_type': submission['form_type'], 'bulk_delete': true},
      );
      idsToDelete.add(submission['id']);
    }

    await _submissionService.deleteClientSubmissions(idsToDelete);

    setState(() {
      _selectedApplicantKey = null;
      _selectedSubmission = null;
      _activeTemplate = null;
      _viewCtrl?.dispose();
      _viewCtrl = null;
      _editCtrl?.dispose();
      _editCtrl = null;
      _isEditMode = false;
    });
    await _loadData();
  }

  // ── Applicant name resolution (3-tier fallback) ──────────
  String _getApplicantName(Map<String, dynamic> submission) {
    var data = submission['data'];
    
    // If data is still encrypted (shouldn't happen after _resolveUnknownNames, but safety check)
    if (data is! Map) {
      return 'Unknown Applicant (Encrypted)';
    }
    
    final dataMap = Map<String, dynamic>.from(data as Map);

    // 1) Embedded name from _embedApplicantName / _resolveUnknownNames
    if (dataMap['__applicant_name'] is Map) {
      final n = dataMap['__applicant_name'] as Map<String, dynamic>;
      final embeddedNameLooksValid = _hasUsableEmbeddedApplicantName(dataMap);
      if (embeddedNameLooksValid) {
        final name = _formatName(n);
        if (name != null) return name;
      }
    }

    // 2) Common key names in JSONB (GIS and custom templates)
    final last = _findNameValue(dataMap, [
      'last_name',
      'Last Name',
      'lastname',
      'Apelyido',
    ]);
    final first = _findNameValue(dataMap, [
      'first_name',
      'First Name',
      'firstname',
      'Pangalan',
    ]);
    final middle = _findNameValue(dataMap, [
      'middle_name',
      'Middle Name',
      'middle_name',
      'Gitnang Pangalan',
    ]);

    // 3) Template-aware: match by autofill_source or field label
    if (last.isEmpty && first.isEmpty) {
      final formType = submission['form_type'] as String? ?? '';
      final template = _templateCache[formType];
      if (template != null) {
        String tLast = '', tFirst = '', tMid = '';
        for (final field in template.allFields) {
          final src = field.autofillSource;
          final lbl = field.fieldLabel.toLowerCase();
          final val = dataMap[field.fieldName]?.toString() ?? '';
          if (val.isEmpty) continue;
          if (src == 'lastname' || lbl.contains('last') && lbl.contains('name'))
            tLast = val;
          if (src == 'firstname' ||
              lbl.contains('first') && lbl.contains('name'))
            tFirst = val;
          if (src == 'middle_name' ||
              lbl.contains('middle') && lbl.contains('name'))
            tMid = val;
        }
        final tName = _formatName({
          'last': tLast,
          'first': tFirst,
          'middle': tMid,
        });
        if (tName != null) return tName;
      }
    }

    if (first.isEmpty && last.isEmpty) return 'Unknown Applicant';
    return _formatName({'last': last, 'first': first, 'middle': middle}) ??
        'Unknown Applicant';
  }

  /// Formats {last, first, middle} into "Last, First M." or null if empty.
  String? _formatName(Map<dynamic, dynamic> n) {
    final last = (n['last'] ?? '').toString().trim();
    final first = (n['first'] ?? '').toString().trim();
    final mid = (n['middle'] ?? '').toString().trim();
    if (last.isEmpty && first.isEmpty) return null;
    return '$last, $first${mid.isNotEmpty ? ' ${mid[0]}.' : ''}'.trim();
  }

  String _findNameValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final val = data[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  bool _hasUsableEmbeddedApplicantName(Map<String, dynamic> data) {
    final raw = data['__applicant_name'];
    if (raw is! Map) return false;

    final last = (raw['last'] ?? '').toString().trim();
    final first = (raw['first'] ?? '').toString().trim();

    if (last.isEmpty && first.isEmpty) return false;
    if (_looksEncryptedToken(last) || _looksEncryptedToken(first)) {
      return false;
    }
    return true;
  }

  bool _looksEncryptedToken(String value) {
    final v = value.trim();
    if (v.length < 24) return false;
    if (v.contains(' ') || v.contains(',')) return false;
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(v)) return false;
    return RegExp(r'[0-9+/=]').hasMatch(v);
  }

  String? _findApplicantId(Map<String, dynamic> submission) {
    final data = submission['data'] is Map
        ? Map<String, dynamic>.from(submission['data'] as Map)
        : <String, dynamic>{};
    final candidates = [
      submission['applicant_id'],
      submission['user_id'],
      data['__applicant_id'],
      data['applicant_id'],
      data['client_id'],
      data['user_id'],
      data['__user_id'],
    ];
    for (final c in candidates) {
      final v = (c ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  DateTime _parseCreatedAt(Map<String, dynamic> submission) {
    final created = submission['created_at']?.toString();
    if (created == null || created.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(created) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_ApplicantGroup> get _groupedApplicants {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final groupName = <String, String>{};

    for (final s in _submissions) {
      final applicantId = _findApplicantId(s);
      final displayName = _getApplicantName(s);
      final key = applicantId != null && applicantId.isNotEmpty
          ? 'id:$applicantId'
          : 'name:${displayName.toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(s);
      groupName[key] = displayName;
    }

    final q = _searchQuery.trim().toLowerCase();
    final groups = <_ApplicantGroup>[];

    for (final entry in grouped.entries) {
      final submissions = List<Map<String, dynamic>>.from(entry.value)
        ..sort((a, b) => _parseCreatedAt(b).compareTo(_parseCreatedAt(a)));

      final name = groupName[entry.key] ?? 'Unknown Applicant';
      if (q.isNotEmpty) {
        final matchesGroup =
            name.toLowerCase().contains(q) ||
            entry.key.toLowerCase().contains(q);
        if (!matchesGroup) continue;
      }

      groups.add(
        _ApplicantGroup(
          key: entry.key,
          displayName: name,
          submissions: submissions,
        ),
      );
    }

    groups.sort((a, b) {
      final ad = a.submissions.isNotEmpty
          ? _parseCreatedAt(a.submissions.first)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.submissions.isNotEmpty
          ? _parseCreatedAt(b.submissions.first)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return groups;
  }

  _ApplicantGroup? get _selectedApplicantGroup {
    final key = _selectedApplicantKey;
    if (key == null) return null;
    for (final group in _groupedApplicants) {
      if (group.key == key) return group;
    }
    return null;
  }

  List<Map<String, dynamic>> _sortedSubmissionsForGroup(_ApplicantGroup group) {
    final sorted = List<Map<String, dynamic>>.from(group.submissions);

    if (_formTypeFilter != 'All') {
      sorted.removeWhere(
        (s) => (s['form_type']?.toString() ?? '') != _formTypeFilter,
      );
    }

    sorted.sort((a, b) {
      final compare = _parseCreatedAt(a).compareTo(_parseCreatedAt(b));
      return _recordSortOrder == _RecordSortOrder.latestFirst
          ? -compare
          : compare;
    });
    return sorted;
  }

  List<String> _formTypeOptionsForGroup(_ApplicantGroup group) {
    final options = <String>{'All'};
    for (final submission in group.submissions) {
      final formType = submission['form_type']?.toString().trim() ?? '';
      if (formType.isNotEmpty) options.add(formType);
    }
    final types = options.where((o) => o != 'All').toList()..sort();
    return ['All', ...types];
  }

  String _getFormattedDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _getIntakeRefLabel(Map<String, dynamic> submission) {
    final ref = (submission['intake_reference'] as String?)?.trim();
    if (ref == null || ref.isEmpty) return 'No reference';
    return ref;
  }

  String _formTypeBadgeText(String formType) {
    final trimmed = formType.trim();
    if (trimmed.isEmpty) return 'FORM';
    if (!trimmed.contains(' ') && trimmed.length <= 8) {
      return trimmed.toUpperCase();
    }
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.map((p) => p[0].toUpperCase()).join();
    return initials.isEmpty ? 'FORM' : initials;
  }

  Color _formTypeBadgeColor(String formType) {
    final key = formType.toLowerCase();
    if (key.contains('gis') || key.contains('general intake')) {
      return const Color(0xFF1FA663);
    }
    if (key.contains('eafic')) {
      return const Color(0xFF2B74E4);
    }
    if (key.contains('case')) {
      return const Color(0xFF8A6BDB);
    }
    return const Color(0xFF4F8A8B);
  }

  // ── Logout / navigation ───────────────────────────────────
  Future<void> _handleLogout() async {
    await _submissionService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(page: const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateToScreen(BuildContext context, String path) {
    if ((path == 'Staff' || path == 'CreateStaff') &&
        widget.role != 'superadmin') {
      return;
    }
    Widget next;
    switch (path) {
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
      case 'Forms':
        next = ManageFormsScreen(
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
    Navigator.of(context).pushReplacement(ContentFadeRoute(page: next));
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'Applicants',
      pageSubtitle: 'Review submitted client intake forms',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: _handleLogout,
      headerActions: [
        _buildHeaderButton('Refresh', Icons.refresh, onPressed: _loadData),
        if (_selectedSubmission != null &&
            _rightPanelView == _RightPanelView.form) ...[
          if (!_isEditMode)
            _buildHeaderButton(
              'Edit',
              Icons.edit,
              onPressed: () => setState(() => _isEditMode = true),
            ),
          if (_isEditMode) ...[
            _buildHeaderButton(
              'Delete',
              Icons.delete,
              onPressed: _deleteSubmission,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveEdit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white, size: 18),
              label: const Text(
                'Save',
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
            const SizedBox(width: 8),
            _buildHeaderButton(
              'Discard',
              Icons.close,
              onPressed: () {
                _editCtrl?.loadFromJson(
                  _selectedSubmission!['data'] as Map<String, dynamic>? ?? {},
                );
                _intakeRefCtrl.text =
                    (_selectedSubmission!['intake_reference'] as String?) ?? '';
                setState(() => _isEditMode = false);
              },
            ),
          ],
        ],
      ],
      onNavigate: (p) => _navigateToScreen(context, p),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
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
                    _buildListPanel(),
                    Expanded(
                      child: _selectedApplicantGroup == null
                          ? _buildEmptyState()
                          : _buildApplicantRecordsPanel(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Left panel: applicant list ────────────────────────────
  Widget _buildListPanel() {
    final groups = _groupedApplicants;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search applicants...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : groups.isEmpty
                ? const Center(
                    child: Text(
                      'No applicants found.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.10),
                        indent: 14,
                        endIndent: 14,
                      ),
                      itemBuilder: (ctx, i) {
                        final group = groups[i];
                        final isSelected = _selectedApplicantKey == group.key;
                        final initials = group.displayName
                            .split(' ')
                            .where((p) => p.trim().isNotEmpty)
                            .take(2)
                            .map((p) => p.trim()[0].toUpperCase())
                            .join();

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            hoverColor: Colors.white.withOpacity(0.05),
                            splashColor: Colors.white.withOpacity(0.08),
                            onTap: () {
                              setState(() {
                                _selectedApplicantKey = group.key;
                                _rightPanelView = _RightPanelView.records;
                                _formTypeFilter = 'All';
                                _recordSortOrder = _RecordSortOrder.latestFirst;
                                _selectedSubmission = null;
                                _activeTemplate = null;
                                _isEditMode = false;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.16)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF7CC3FF)
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(
                                              0xFF7CC3FF,
                                            ).withOpacity(0.25)
                                          : Colors.white.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF7CC3FF)
                                            : Colors.white24,
                                      ),
                                    ),
                                    child: Text(
                                      initials.isEmpty ? '?' : initials,
                                      style: TextStyle(
                                        color: isSelected
                                            ? const Color(0xFFBFE3FF)
                                            : Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      group.displayName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: isSelected
                                        ? const Color(0xFFBFE3FF)
                                        : Colors.white54,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Right panel: empty ────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Select an applicant to view records',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicantRecordsPanel() {
    final group = _selectedApplicantGroup;
    if (group == null) return _buildEmptyState();

    if (_rightPanelView == _RightPanelView.form) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: Container(
          key: const ValueKey('right-form-view'),
          margin: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _rightPanelView = _RightPanelView.records;
                        _isEditMode = false;
                      });
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _selectedSubmission == null
                    ? const Center(
                        child: Text(
                          'Select a record to view full form data.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : _buildDetailPanel(),
              ),
            ],
          ),
        ),
      );
    }

    final options = _formTypeOptionsForGroup(group);
    if (!options.contains(_formTypeFilter)) {
      _formTypeFilter = 'All';
    }
    final records = _sortedSubmissionsForGroup(group);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(-0.03, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: Container(
        key: const ValueKey('right-records-view'),
        margin: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      SizedBox(
                        width: 158,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 6, bottom: 4),
                              child: Text(
                                '↕ Date',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DropdownButtonFormField<_RecordSortOrder>(
                              isExpanded: true,
                              value: _recordSortOrder,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _recordSortOrder = value;
                                });
                              },
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF243047),
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.22),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: const BorderSide(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: _RecordSortOrder.latestFirst,
                                  child: Text('Latest First'),
                                ),
                                DropdownMenuItem(
                                  value: _RecordSortOrder.oldestFirst,
                                  child: Text('Oldest First'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 148,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 6, bottom: 4),
                              child: Text(
                                '⊞ Type',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _formTypeFilter,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _formTypeFilter = value;
                                });
                              },
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF243047),
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.22),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: const BorderSide(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              items: options
                                  .map(
                                    (type) => DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(
                                        type,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _deleteApplicant,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      side: BorderSide(
                        color: Colors.red.withOpacity(0.5),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (records.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No records available for this applicant.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.10),
                      ),
                      itemBuilder: (_, idx) {
                        final record = records[idx];
                        final formType =
                            record['form_type']?.toString() ?? 'Unknown Form';
                        final badgeText = _formTypeBadgeText(formType);
                        final badgeColor = _formTypeBadgeColor(formType);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            hoverColor: Colors.white.withOpacity(0.06),
                            splashColor: Colors.white.withOpacity(0.08),
                            onTap: () {
                              _loadSubmission(record);
                              setState(() {
                                _rightPanelView = _RightPanelView.form;
                              });
                            },
                            child: SizedBox(
                              height: 78,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: badgeColor.withOpacity(0.6),
                                        ),
                                      ),
                                      child: Text(
                                        badgeText,
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            formType,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _getFormattedDate(
                                              record['created_at']?.toString(),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            'Ref: ${_getIntakeRefLabel(record)}',
                                            style: const TextStyle(
                                              color: Colors.white60,
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Right panel: dynamic form detail ─────────────────────
  Widget _buildDetailPanel() {
    // Fallback: no template found for this form_type
    if (_activeTemplate == null) {
      final data = _selectedSubmission!['data'] as Map<String, dynamic>? ?? {};
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries
              .where((e) => !e.key.startsWith('__'))
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    final ctrl = _isEditMode ? _editCtrl! : _viewCtrl!;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Intake Reference',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _intakeRefCtrl,
                    readOnly: !_isEditMode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'No reference assigned',
                      isDense: true,
                      filled: true,
                      fillColor: _isEditMode
                          ? AppColors.pageBg
                          : const Color(0xFFF7F7F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: ctrl,
              builder: (context, _) => DynamicFormRenderer(
                template: _activeTemplate!,
                controller: ctrl,
                mode: 'web',
                isReadOnly: !_isEditMode,
                showCheckboxes: false,
              ),
            ),
          ],
        ),
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
    _searchController.dispose();
    _intakeRefCtrl.dispose();
    _viewCtrl?.dispose();
    _editCtrl?.dispose();
    super.dispose();
  }
}
