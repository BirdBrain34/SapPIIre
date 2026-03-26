// lib/web/screen/applicants_screen.dart
// REFACTORED: Uses DynamicFormRenderer to display any saved form template.
// No more hardcoded GIS section imports.

import 'package:flutter/material.dart';
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
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/web/services/audit_log_service.dart';

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

enum _SubmissionSortOption { date, formType }

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
  final _supabase = Supabase.instance.client;
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
  final Set<String> _expandedApplicantKeys = <String>{};
  final Map<String, String> _submissionSearchByGroup = {};
  final Map<String, _SubmissionSortOption> _submissionSortByGroup = {};

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

      final response = await _supabase
          .from('client_submissions')
          .select('*')
          .order('created_at', ascending: false)
          .range(0, 99); // paginate: first 100

      final submissions = List<Map<String, dynamic>>.from(response);

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
  /// Traces __session_id → form_submission.user_id → user_profiles in batch.
  Future<void> _resolveUnknownNames(
    List<Map<String, dynamic>> submissions,
  ) async {
    final needsResolution = <Map<String, dynamic>>[];
    for (final sub in submissions) {
      final data = sub['data'] as Map<String, dynamic>? ?? {};
      if (data['__applicant_name'] is Map) continue;
      final sid = data['__session_id']?.toString();
      if (sid != null && sid.isNotEmpty) needsResolution.add(sub);
    }

    if (needsResolution.isEmpty) return;

    final sessionIds = needsResolution
        .map(
          (s) =>
              (s['data'] as Map<String, dynamic>)['__session_id']?.toString(),
        )
        .whereType<String>()
        .toSet()
        .toList();
    if (sessionIds.isEmpty) return;

    try {
      // session IDs → user_ids
      final sessions = await _supabase
          .from('form_submission')
          .select('id, user_id')
          .inFilter('id', sessionIds);

      final sessionToUserId = <String, String>{};
      final userIds = <String>{};
      for (final row in sessions) {
        final uid = row['user_id']?.toString();
        if (uid != null && uid.isNotEmpty) {
          sessionToUserId[row['id'].toString()] = uid;
          userIds.add(uid);
        }
      }

      if (userIds.isEmpty) return;

      // user_ids → profile names
      final profiles = await _supabase
          .from('user_profiles')
          .select('user_id, lastname, firstname, middle_name')
          .inFilter('user_id', userIds.toList());

      final userIdToName = <String, Map<String, String>>{};
      for (final p in profiles) {
        userIdToName[p['user_id'].toString()] = {
          'last': (p['lastname'] ?? '').toString().trim(),
          'first': (p['firstname'] ?? '').toString().trim(),
          'middle': (p['middle_name'] ?? '').toString().trim(),
        };
      }

      // Embed resolved names into submissions
      for (final sub in needsResolution) {
        final data = sub['data'] as Map<String, dynamic>? ?? {};
        final sessionId = data['__session_id']?.toString();
        if (sessionId == null) continue;
        final userId = sessionToUserId[sessionId];
        if (userId == null) continue;
        final name = userIdToName[userId];
        if (name != null &&
            (name['last']!.isNotEmpty || name['first']!.isNotEmpty)) {
          data['__applicant_name'] = name;
        }
      }
    } catch (e) {
      debugPrint('_resolveUnknownNames error: $e');
    }
  }

  // ── Load a submission into the detail panel ───────────────
  void _loadSubmission(Map<String, dynamic> submission) {
    final formType = submission['form_type'] as String? ?? '';
    final data = submission['data'] as Map<String, dynamic>? ?? {};
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

    final view = FormStateController(template: template)..loadFromJson(data);
    final edit = FormStateController(template: template)..loadFromJson(data);

    setState(() {
      _selectedSubmission = submission;
      _activeTemplate = template;
      _viewCtrl = view;
      _editCtrl = edit;
      _isEditMode = false;
    });
  }

  // ── Save edited submission ────────────────────────────────
  Future<void> _saveEdit() async {
    if (_editCtrl == null || _selectedSubmission == null) return;
    setState(() => _isSaving = true);
    try {
      final updatedData = _editCtrl!.toJson();
      await _supabase
          .from('client_submissions')
          .update({
            'data': updatedData,
            'intake_reference': _intakeRefCtrl.text.trim().isEmpty
                ? null
                : _intakeRefCtrl.text.trim(),
            'last_edited_by': widget.cswd_id,
            'last_edited_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _selectedSubmission!['id']);

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

    await _supabase
        .from('client_submissions')
        .delete()
        .eq('id', _selectedSubmission!['id']);

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

  // ── Applicant name resolution (3-tier fallback) ──────────
  String _getApplicantName(Map<String, dynamic> submission) {
    final data = submission['data'] as Map<String, dynamic>? ?? {};

    // 1) Embedded name from _embedApplicantName / _resolveUnknownNames
    if (data['__applicant_name'] is Map) {
      final n = data['__applicant_name'] as Map<String, dynamic>;
      final name = _formatName(n);
      if (name != null) return name;
    }

    // 2) Common key names in JSONB (GIS and custom templates)
    final last = _findNameValue(data, [
      'last_name',
      'Last Name',
      'lastname',
      'Apelyido',
    ]);
    final first = _findNameValue(data, [
      'first_name',
      'First Name',
      'firstname',
      'Pangalan',
    ]);
    final middle = _findNameValue(data, [
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
          final val = data[field.fieldName]?.toString() ?? '';
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

  String? _findApplicantId(Map<String, dynamic> submission) {
    final data = submission['data'] as Map<String, dynamic>? ?? {};
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

  List<Map<String, dynamic>> _visibleSubmissionsForGroup(
    _ApplicantGroup group,
  ) {
    final query = (_submissionSearchByGroup[group.key] ?? '')
        .trim()
        .toLowerCase();
    final sortOption =
        _submissionSortByGroup[group.key] ?? _SubmissionSortOption.date;

    final visible = group.submissions.where((s) {
      if (query.isEmpty) return true;
      final intakeRef = (s['intake_reference'] ?? '').toString().toLowerCase();
      final formType = (s['form_type'] ?? '').toString().toLowerCase();
      final dateRaw = (s['created_at'] ?? '').toString().toLowerCase();
      final dateDisplay = _getFormattedDate(
        s['created_at']?.toString(),
      ).toLowerCase();
      return intakeRef.contains(query) ||
          formType.contains(query) ||
          dateRaw.contains(query) ||
          dateDisplay.contains(query);
    }).toList();

    visible.sort((a, b) {
      if (sortOption == _SubmissionSortOption.formType) {
        final at = (a['form_type'] ?? '').toString().toLowerCase();
        final bt = (b['form_type'] ?? '').toString().toLowerCase();
        final typeCompare = at.compareTo(bt);
        if (typeCompare != 0) return typeCompare;
      }
      return _parseCreatedAt(b).compareTo(_parseCreatedAt(a));
    });

    return visible;
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
        final matchesSubmission = submissions.any((s) {
          final ref = (s['intake_reference'] ?? '').toString().toLowerCase();
          final type = (s['form_type'] ?? '').toString().toLowerCase();
          final date = _getFormattedDate(
            s['created_at']?.toString(),
          ).toLowerCase();
          return ref.contains(q) || type.contains(q) || date.contains(q);
        });
        if (!matchesGroup && !matchesSubmission) continue;
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

  String _getFormattedDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ── Logout / navigation ───────────────────────────────────
  Future<void> _handleLogout() async {
    await _supabase.auth.signOut();
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
        if (_selectedSubmission != null) ...[
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
                      child: _selectedSubmission == null
                          ? _buildEmptyState()
                          : _buildDetailPanel(),
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
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (ctx, i) {
                      final group = groups[i];
                      final isExpanded = _expandedApplicantKeys.contains(
                        group.key,
                      );
                      final visibleSubmissions = _visibleSubmissionsForGroup(
                        group,
                      );
                      final selectedId = _selectedSubmission?['id'];
                      final groupHasSelected = group.submissions.any(
                        (s) => s['id'] == selectedId,
                      );

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              selected: groupHasSelected,
                              selectedTileColor: Colors.white.withOpacity(0.15),
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedApplicantKeys.remove(group.key);
                                  } else {
                                    _expandedApplicantKeys.add(group.key);
                                  }
                                });
                              },
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.displayName,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: groupHasSelected
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${group.submissions.length} forms',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: group.submissions.isEmpty
                                  ? null
                                  : Text(
                                      'Latest: ${group.submissions.first['form_type'] ?? ''}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: Icon(
                                isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                            if (isExpanded)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 12,
                                  bottom: 8,
                                ),
                                child: Column(
                                  children: [
                                    TextField(
                                      key: ValueKey(
                                        'submission-search-${group.key}',
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _submissionSearchByGroup[group.key] =
                                              value;
                                        });
                                      },
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search intake ref, form type, or date',
                                        hintStyle: const TextStyle(
                                          color: Colors.white54,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                          0.08,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<
                                      _SubmissionSortOption
                                    >(
                                      value:
                                          _submissionSortByGroup[group.key] ??
                                          _SubmissionSortOption.date,
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() {
                                          _submissionSortByGroup[group.key] =
                                              value;
                                        });
                                      },
                                      dropdownColor: const Color(0xFF1F2B40),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                          0.08,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: _SubmissionSortOption.date,
                                          child: Text('Sort by Date'),
                                        ),
                                        DropdownMenuItem(
                                          value: _SubmissionSortOption.formType,
                                          child: Text('Sort by Form Type'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    ...visibleSubmissions.map((s) {
                                      final isSelected =
                                          _selectedSubmission?['id'] == s['id'];
                                      final ref =
                                          (s['intake_reference'] as String?)
                                              ?.trim();
                                      final refLabel =
                                          (ref != null && ref.isNotEmpty)
                                          ? ref
                                          : 'NO-REFERENCE';
                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 6),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white.withOpacity(0.2)
                                              : Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.white54
                                                : Colors.white24,
                                          ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          onTap: () => _loadSubmission(s),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  refLabel,
                                                  style: const TextStyle(
                                                    color: Colors.amber,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${s['form_type'] ?? ''} • ${_getFormattedDate(s['created_at']?.toString())}',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    if (visibleSubmissions.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                          'No submissions match your search.',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.7,
                                            ),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
            'Select an applicant to view their form',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
        ],
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
