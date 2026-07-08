/// Web screen for browsing, resolving, and editing applicant submissions.
/// Uses DynamicFormRenderer so any saved form template can be displayed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/widgets/web_header_button.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/controllers/applicants_controller.dart';

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
  final _applicantsController = const ApplicantsController();

  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _selectedSubmission;
  FormTemplate? _activeTemplate;
  FormStateController? _viewCtrl;

  bool _isLoading = true;
  bool _isLoadingSubmission = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _intakeRefCtrl = TextEditingController();
  String? _selectedApplicantKey;
  RecordSortOrder _recordSortOrder = RecordSortOrder.latestFirst;
  _RightPanelView _rightPanelView = _RightPanelView.records;
  String _formTypeFilter = 'All';
  int _submissionLoadToken = 0;

  // Cache templates by form type.
  final Map<String, FormTemplate> _templateCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _isLoadingSubmission = false;
    });
    try {
      final templatesFuture = _templateService
          .fetchActiveTemplates()
          .catchError((Object e, StackTrace st) {
            debugPrint('[ApplicantsScreen/_loadData] Template load error: $e');
            return <FormTemplate>[];
          });
      final submissions = await _submissionService.fetchApplicantIndex(
        limit: 100,
      );

      final hydrateFuture = _hydrateApplicantMetadata(submissions);
      final templates = await templatesFuture;
      await hydrateFuture;

      // Decrypt encrypted submissions in batch
      final encryptedSubmissionIds = submissions
          .where((s) => (s['data_encryption_version'] ?? 0) == 1)
          .map((s) => s['id'] as int)
          .toList();

      if (encryptedSubmissionIds.isNotEmpty) {
        try {
          final decryptedData = await _submissionService.batchDecryptSubmissions(
            encryptedSubmissionIds,
            widget.cswd_id,
            logAccess: false,
          );

          // Merge decrypted data back into submissions
          for (final submission in submissions) {
            final id = submission['id'] as int;
            if (decryptedData.containsKey(id)) {
              submission['data'] = decryptedData[id];
            }
          }
        } catch (e) {
          debugPrint('[ApplicantsScreen/_loadData] Batch decrypt error: $e');
        }
      }

      if (!mounted) return;

      for (final t in templates) {
        _templateCache[t.formName] = t;
      }

      setState(() {
        _submissions = submissions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ApplicantsScreen/_loadData] Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openSubmission(Map<String, dynamic> submission) async {
    final loadToken = ++_submissionLoadToken;

    setState(() {
      _isLoadingSubmission = true;
      _rightPanelView = _RightPanelView.form;
    });

    try {
      await _loadSubmission(submission, loadToken: loadToken);
    } finally {
      if (!mounted || loadToken != _submissionLoadToken) return;
      setState(() => _isLoadingSubmission = false);
    }
  }

  void _cancelSubmissionLoad() {
    _submissionLoadToken++;
    _isLoadingSubmission = false;
  }

  void _handleSearchChanged(String v) {
    if (v == _searchQuery) return;

    // Prevent focus-stealing quirks on Flutter Web by letting the
    // TextField update happen before rebuilding the list.
    _searchQuery = v;
    Future.microtask(() {
      if (!mounted) return;
      setState(() {});
    });
  }


  Future<void> _hydrateApplicantMetadata(
    List<Map<String, dynamic>> submissions,
  ) async {
    final sessionIds = submissions
        .map(_resolveSubmissionSessionId)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (sessionIds.isEmpty) return;

    try {
      final sessionToUserId = await _submissionService.fetchSessionUserMap(
        sessionIds,
      );
      final userIds = sessionToUserId.values
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();

      if (userIds.isEmpty) return;

      final userIdToCanonicalName = await _submissionService
          .fetchCanonicalNamesByUserIds(userIds);

      if (!mounted) return;

      for (final sub in submissions) {
        final sessionId = _resolveSubmissionSessionId(sub);
        if (sessionId == null || sessionId.isEmpty) {
          continue;
        }

        final userId = sessionToUserId[sessionId];
        if (userId == null || userId.trim().isEmpty) {
          continue;
        }

        sub['user_id'] = userId;

        final canonicalName = userIdToCanonicalName[userId];
        final formattedName = canonicalName == null
            ? ''
            : _applicantsController.formatName(canonicalName) ?? '';

        final existingData = sub['data'];
        final dataMap = existingData is Map
            ? Map<String, dynamic>.from(existingData)
            : <String, dynamic>{};
        dataMap['__session_id'] = sessionId;
        dataMap['__user_id'] = userId;
        if (canonicalName != null && canonicalName.isNotEmpty) {
          dataMap['__applicant_name'] = canonicalName;
        }
        sub['data'] = dataMap;

        if (canonicalName != null && canonicalName.isNotEmpty) {
          sub['applicant_name'] = canonicalName;
        }
        if (formattedName.isNotEmpty) {
          sub['display_name'] = formattedName;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[ApplicantsScreen/_hydrateApplicantMetadata] Error: $e');
    }
  }

  String? _resolveSubmissionSessionId(Map<String, dynamic> submission) {
    final data = submission['data'] is Map
        ? Map<String, dynamic>.from(submission['data'] as Map)
        : <String, dynamic>{};

    final candidates = [
      submission['session_id'],
      submission['sessionId'],
      submission['form_submission_id'],
      submission['submission_id'],
      data['__session_id'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    return null;
  }

  // Load a submission into the detail panel.
  // [logAccess] records a deliberate PII-access audit entry; set false for
  // programmatic reloads (e.g. after saving an edit) to avoid double-logging.
  Future<void> _loadSubmission(
    Map<String, dynamic> submission, {
    bool logAccess = true,
    int? loadToken,
  }) async {
    var submissionToOpen = submission;
    final metadata = {
      if (submission['applicant_name'] != null)
        'applicant_name': submission['applicant_name'],
      if (submission['display_name'] != null)
        'display_name': submission['display_name'],
      if (submission['user_id'] != null) 'user_id': submission['user_id'],
      if (submission['session_id'] != null)
        'session_id': submission['session_id'],
    };

    if (loadToken != null && loadToken != _submissionLoadToken) {
      return;
    }

    if (submissionToOpen['data'] == null) {
      final fullSubmission = await _submissionService.fetchClientSubmissionById(
        submissionToOpen['id'],
      );

      if (fullSubmission == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load submission details.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      submissionToOpen = {...fullSubmission, ...metadata};
    }

    if (loadToken != null && loadToken != _submissionLoadToken) {
      return;
    }

    final formType = submissionToOpen['form_type'] as String? ?? '';
    var data = submissionToOpen['data'];
    final encryptionVersion = submissionToOpen['data_encryption_version'] ?? 0;

    // Always route encrypted submissions through the edge function on a
    // deliberate open so exactly one server-side access audit row is written,
    // even when the list's background pass already cached a decrypted Map.
    if (encryptionVersion == 1) {
      try {
        final decrypted = await _decryptSubmissionData(
          submissionToOpen['id'].toString(),
          logAccess: logAccess,
        );
        data = decrypted;
      } catch (e) {
        debugPrint('[ApplicantsScreen/_loadSubmission] Error: $e');
        // Fall back to the cached decrypted Map (from the list pass) so the
        // record still opens; only hard-fail when nothing usable is cached.
        if (data is! Map) {
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
    }

    if (loadToken != null && loadToken != _submissionLoadToken) {
      return;
    }

    final dataMap = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final template = _templateCache[formType];
    _intakeRefCtrl.text =
        (submissionToOpen['intake_reference'] as String?) ?? '';

    _viewCtrl?.dispose();

    if (template == null) {
      if (loadToken != null && loadToken != _submissionLoadToken) {
        return;
      }
      // Fall back to the raw JSON when the template no longer exists.
      setState(() {
        _selectedSubmission = submissionToOpen;
        _activeTemplate = null;
        _viewCtrl = null;
      });
      return;
    }

    final view = FormStateController(template: template)..loadFromJson(dataMap);

    if (loadToken != null && loadToken != _submissionLoadToken) {
      return;
    }

    setState(() {
      _selectedSubmission = submissionToOpen;
      _activeTemplate = template;
      _viewCtrl = view;
    });
  }

  Future<Map<String, dynamic>> _decryptSubmissionData(
    String submissionId, {
    bool logAccess = true,
  }) async {
    final supabase = Supabase.instance.client;

    final response = await supabase.functions.invoke(
      'decrypt-submission-data',
      body: {
        'submissionId': submissionId,
        'staffId': widget.cswd_id,
        'logAccess': logAccess,
      },
    );

    if (response.status != 200) {
      debugPrint(
        '[ApplicantsScreen/_decryptSubmissionData] Error response: ${response.data}',
      );
      throw Exception(response.data.toString());
    }

    final result = response.data as Map<String, dynamic>;
    return result['data'] as Map<String, dynamic>;
  }

  List<ApplicantGroup> get _groupedApplicants =>
      _applicantsController.groupedApplicants(
        submissions: _submissions,
        searchQuery: _searchQuery,
        templateCache: _templateCache,
      );

  ApplicantGroup? get _selectedApplicantGroup {
    final key = _selectedApplicantKey;
    if (key == null) return null;
    for (final group in _groupedApplicants) {
      if (group.key == key) return group;
    }
    return null;
  }

  List<Map<String, dynamic>> _sortedSubmissionsForGroup(ApplicantGroup group) =>
      _applicantsController.sortedSubmissionsForGroup(
        group: group,
        formTypeFilter: _formTypeFilter,
        sortOrder: _recordSortOrder,
      );

  List<String> _formTypeOptionsForGroup(ApplicantGroup group) =>
      _applicantsController.formTypeOptionsForGroup(group);

  String _getFormattedDate(String? iso) =>
      _applicantsController.getFormattedDate(iso);

  String _getIntakeRefLabel(Map<String, dynamic> submission) =>
      _applicantsController.getIntakeRefLabel(submission);

  String _formTypeBadgeText(String formType) =>
      _applicantsController.formTypeBadgeText(formType);

  Color _formTypeBadgeColor(String formType) =>
      _applicantsController.formTypeBadgeColor(formType);

  // Logout / navigation
  Future<void> _handleLogout() => WebSession.logout(context);

  // Build
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
        WebHeaderButton('Refresh', Icons.refresh, onPressed: _loadData),
      ],
      onNavigate: (p) => WebNavigator.go(
        context,
        p,
        cswdId: widget.cswd_id,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final fade = FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                  final scale = Tween<double>(
                    begin: 0.985,
                    end: 1.0,
                  ).animate(animation);
                  return ScaleTransition(scale: scale, child: fade);
                },
                child: _isLoading
                    ? Container(
                        key: const ValueKey('applicants-loading'),
                        color: Colors.transparent,
                        child: _buildApplicantsLoadingState(),
                      )
                    : Row(
                        key: const ValueKey('applicants-ready'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildListPanel(),
                          const SizedBox(width: 20),
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

  // Left panel: applicant list
  Widget _buildListPanel() {
    final groups = _groupedApplicants;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 18,
                      color: AppColors.textDark,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Applicants',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    if (!_isLoading)
                      Text(
                        '${groups.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _handleSearchChanged,
                  style: const TextStyle(color: AppColors.textDark, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search applicants...',
                    hintStyle: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.pageBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.highlight),
                  )
                : groups.isEmpty
                ? const Center(
                    child: Text(
                      'No applicants found.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: AppColors.cardBorder,
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
                            hoverColor: AppColors.pageBg,
                            splashColor: AppColors.highlight.withValues(alpha:  0.08),
                            onTap: () {
                              setState(() {
                                _cancelSubmissionLoad();
                                _selectedApplicantKey = group.key;
                                _rightPanelView = _RightPanelView.records;
                                _formTypeFilter = 'All';
                                _recordSortOrder = RecordSortOrder.latestFirst;
                                _selectedSubmission = null;
                                _activeTemplate = null;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.highlight.withValues(alpha:  0.10)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? AppColors.highlight
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
                                          ? AppColors.highlight.withValues(
                                              alpha: 0.15,
                                            )
                                          : AppColors.pageBg,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.highlight
                                            : AppColors.cardBorder,
                                      ),
                                    ),
                                    child: Text(
                                      initials.isEmpty ? '?' : initials,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.highlight
                                            : AppColors.textMuted,
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
                                        color: AppColors.textDark,
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
                                        ? AppColors.highlight
                                        : AppColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // Right panel: empty
  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 64,
              color: AppColors.textMuted.withValues(alpha:  0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select an applicant to view records',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmissionLoadingState() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: AppColors.highlight,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading form...',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicantsLoadingState() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: AppColors.highlight,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Grouping applicants...',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _cancelSubmissionLoad();
                        _rightPanelView = _RightPanelView.records;
                      });
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: AppColors.textDark,
                    ),
                    label: const Text(
                      'Back',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.pageBg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.displayName,
                      style: const TextStyle(
                        color: AppColors.textDark,
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final fade = FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                    final slide = Tween<Offset>(
                      begin: const Offset(0.02, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(position: slide, child: fade);
                  },
                  child: _isLoadingSubmission
                      ? Container(
                          key: const ValueKey('submission-loading'),
                          child: _buildSubmissionLoadingState(),
                        )
                      : _selectedSubmission == null
                          ? const Center(
                              key: ValueKey('submission-empty'),
                              child: Text(
                                'Select a record to view full form data.',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            )
                          : Container(
                              key: ValueKey(
                                'submission-${_selectedSubmission!['id']}',
                              ),
                              child: _buildDetailPanel(),
                            ),
                ),
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
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.displayName,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.swap_vert,
                                    color: AppColors.textMuted,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Date',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButtonFormField<RecordSortOrder>(
                              isExpanded: true,
                              initialValue: _recordSortOrder,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _recordSortOrder = value;
                                });
                              },
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.pageBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.highlight,
                                  ),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: RecordSortOrder.latestFirst,
                                  child: Text('Latest First'),
                                ),
                                DropdownMenuItem(
                                  value: RecordSortOrder.oldestFirst,
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.category,
                                    color: AppColors.textMuted,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Type',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _formTypeFilter,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _formTypeFilter = value;
                                });
                              },
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.pageBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.highlight,
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
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.cardBorder),
            if (records.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No records available for this applicant.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: records.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: AppColors.cardBorder,
                        indent: 12,
                        endIndent: 12,
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
                            hoverColor: AppColors.pageBg,
                            splashColor: AppColors.highlight.withValues(alpha:  0.08),
                            onTap: () => _openSubmission(record),
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
                                        color: badgeColor.withValues(alpha:  0.12),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: badgeColor.withValues(alpha:  0.3),
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
                                              color: AppColors.textDark,
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
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            'Ref: ${_getIntakeRefLabel(record)}',
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.textMuted,
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
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
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
                    style: const TextStyle(color: AppColors.textDark, fontSize: 12),
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    final ctrl = _viewCtrl!;

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
                    readOnly: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'No reference assigned',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
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
                isReadOnly: true,
                showCheckboxes: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _intakeRefCtrl.dispose();
    _viewCtrl?.dispose();
    super.dispose();
  }
}
