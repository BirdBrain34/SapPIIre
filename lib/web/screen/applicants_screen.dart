/// Web screen for browsing, resolving, and editing applicant submissions.
///
/// Applicant PII is AES-GCM ciphertext, so searching and grouping happen
/// server-side in the `search-applicants` Edge Function — the browser cannot
/// filter on names, and it never holds more than the page it is showing.
/// Uses DynamicFormRenderer so any saved form template can be displayed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/forms/applicant_search_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/widgets/filter_controls.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/utils/debouncer.dart';
import 'package:sappiire/web/widgets/web_header_button.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/controllers/applicants_controller.dart';

enum _RightPanelView { records, form }

class ApplicantsScreen extends StatefulWidget {
  final String cswdId;
  final String role;
  final String displayName;

  const ApplicantsScreen({
    super.key,
    required this.cswdId,
    required this.role,
    this.displayName = '',
  });

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final _submissionService = SubmissionService();
  final _searchService = ApplicantSearchService();
  final _templateService = FormTemplateService();
  final _applicantsController = const ApplicantsController();

  static const int _pageSize = 25;

  // Applicant list state — one entry per distinct person, as resolved server
  // side. Never the raw submission rows.
  List<ApplicantSummary> _applicants = [];
  ApplicantSummary? _selected;

  Map<String, dynamic>? _selectedSubmission;
  FormTemplate? _activeTemplate;
  FormStateController? _viewCtrl;

  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _isLoadingSubmission = false;
  bool _hasMore = false;
  bool _degraded = false;
  String? _searchError;
  int _offset = 0;

  String _searchQuery = '';
  ApplicantSearchFilters _filters = const ApplicantSearchFilters();
  ApplicantSortOrder _sortOrder = ApplicantSortOrder.recent;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _intakeRefCtrl = TextEditingController();
  final ScrollController _listScroll = ScrollController();
  final Debouncer _searchDebouncer = Debouncer.search();

  RecordSortOrder _recordSortOrder = RecordSortOrder.latestFirst;
  _RightPanelView _rightPanelView = _RightPanelView.records;
  String _formTypeFilter = 'All';
  int _submissionLoadToken = 0;

  // Cache templates by form type.
  final Map<String, FormTemplate> _templateCache = {};

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onListScroll);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _isLoadingSubmission = false;
    });

    try {
      final templates = await _templateService.fetchActiveTemplates().catchError(
        (Object e, StackTrace st) {
          debugPrint('[ApplicantsScreen/_loadData] Template load error: $e');
          return <FormTemplate>[];
        },
      );

      if (!mounted) return;

      for (final t in templates) {
        _templateCache[t.formName] = t;
      }
    } catch (e) {
      debugPrint('[ApplicantsScreen/_loadData] Error: $e');
    }

    // The list itself is populated by the search call — there is no separate
    // "fetch everything then filter in the browser" pass any more, and no
    // eager bulk decrypt of records nobody has opened.
    await _runSearch(reset: true);

    if (mounted) setState(() => _isLoading = false);
  }

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  void _onListScroll() {
    if (!_listScroll.hasClients || !_hasMore || _isLoadingMore || _isSearching) {
      return;
    }
    final position = _listScroll.position;
    if (position.pixels >= position.maxScrollExtent * 0.85) {
      _runSearch(reset: false);
    }
  }

  /// Keystrokes must not call setState — the TextField owns its own text via
  /// the controller. Rebuilding the screen on every character is what forced
  /// the old Future.microtask focus workaround on Flutter Web.
  void _handleSearchChanged(String value) {
    _searchQuery = value;
    _searchDebouncer.run(() {
      if (!mounted) return;
      _runSearch(reset: true);
    });
  }

  void _handleSearchSubmitted(String value) {
    _searchQuery = value;
    _searchDebouncer.flush(() {
      if (!mounted) return;
      _runSearch(reset: true);
    });
  }

  bool get _queryTooShort {
    final q = _searchQuery.trim();
    return q.isNotEmpty && q.length < ApplicantSearchService.minQueryLength;
  }

  Future<void> _runSearch({required bool reset}) async {
    // A 1-2 character query would scan nearly everything for nothing useful.
    if (_queryTooShort) {
      setState(() {
        _applicants = [];
        _selected = null;
        _hasMore = false;
        _degraded = false;
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    if (reset) {
      setState(() {
        _isSearching = true;
        _searchError = null;
        _offset = 0;
      });
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    final result = await _searchService.search(
      staffId: widget.cswdId,
      query: _searchQuery,
      filters: _filters,
      sort: _sortOrder,
      limit: _pageSize,
      offset: reset ? 0 : _offset,
    );

    if (!mounted) return;

    // A null result means a newer search superseded this one. Leave the list
    // alone rather than clobbering fresher data with a stale response.
    if (result == null) {
      if (!reset) setState(() => _isLoadingMore = false);
      return;
    }

    setState(() {
      _isSearching = false;
      _isLoadingMore = false;

      if (result.isError) {
        _searchError = result.error;
        if (reset) {
          _applicants = [];
          _selected = null;
          _hasMore = false;
        }
        return;
      }

      _searchError = null;
      _degraded = result.degraded;
      _hasMore = result.hasMore;

      if (reset) {
        _applicants = result.applicants;
        _offset = result.applicants.length;
        // Keep the selection only if that person is still in the results.
        // identityKey is ephemeral, so this is in-session state only — never
        // persist it or put it in a URL.
        final previousKey = _selected?.identityKey;
        ApplicantSummary? stillPresent;
        if (previousKey != null) {
          for (final applicant in _applicants) {
            if (applicant.identityKey == previousKey) {
              stillPresent = applicant;
              break;
            }
          }
        }
        _selected = stillPresent;
        if (_selected == null) {
          _selectedSubmission = null;
          _activeTemplate = null;
          _rightPanelView = _RightPanelView.records;
        }
      } else {
        // Guard the page seam: the same person must never appear twice.
        final seen = _applicants.map((a) => a.identityKey).toSet();
        final added = result.applicants
            .where((a) => !seen.contains(a.identityKey))
            .toList();
        _applicants = [..._applicants, ...added];
        _offset += result.applicants.length;
      }
    });
  }

  void _updateFilters(ApplicantSearchFilters next) {
    setState(() => _filters = next);
    _runSearch(reset: true);
  }

  void _resetFilters() {
    _searchController.clear();
    _searchQuery = '';
    setState(() {
      _filters = const ApplicantSearchFilters();
      _sortOrder = ApplicantSortOrder.recent;
    });
    _runSearch(reset: true);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial =
        (isFrom ? _filters.dateFrom : _filters.dateTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    _updateFilters(
      isFrom
          ? _filters.copyWith(dateFrom: picked)
          : _filters.copyWith(dateTo: picked),
    );
  }

  // ---------------------------------------------------------------------
  // Record opening
  // ---------------------------------------------------------------------

  Future<void> _openSubmission(Map<String, dynamic> submission) async {
    final loadToken = ++_submissionLoadToken;

    setState(() {
      _isLoadingSubmission = true;
      _rightPanelView = _RightPanelView.form;
    });

    try {
      await _loadSubmission(submission, loadToken: loadToken);
    } finally {
      if (mounted && loadToken == _submissionLoadToken) {
        setState(() => _isLoadingSubmission = false);
      }
    }
  }

  void _cancelSubmissionLoad() {
    _submissionLoadToken++;
    _isLoadingSubmission = false;
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
      if (_selected != null) 'display_name': _selected!.displayName,
      if (_selected?.userId != null) 'user_id': _selected!.userId,
      if (submission['session_id'] != null)
        'session_id': submission['session_id'],
    };

    if (loadToken != null && loadToken != _submissionLoadToken) {
      return;
    }

    // The list only carries metadata, so the body is always fetched here —
    // exactly one record, on a deliberate open.
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

    // Encrypted submissions always route through the edge function on a
    // deliberate open, so exactly one server-side access audit row is written.
    if (encryptionVersion == 1) {
      try {
        final decrypted = await _decryptSubmissionData(
          submissionToOpen['id'].toString(),
          logAccess: logAccess,
        );
        data = decrypted;
      } catch (e) {
        debugPrint('[ApplicantsScreen/_loadSubmission] Error: $e');
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
        'staffId': widget.cswdId,
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

  // ---------------------------------------------------------------------
  // Selected applicant's records
  // ---------------------------------------------------------------------

  List<String> get _formTypeOptions {
    final applicant = _selected;
    if (applicant == null) return const ['All'];
    return ['All', ...applicant.formTypes];
  }

  List<ApplicantSubmissionRef> get _visibleRecords {
    final applicant = _selected;
    if (applicant == null) return const [];

    final records = applicant.submissions
        .where(
          (r) => _formTypeFilter == 'All' || r.formType == _formTypeFilter,
        )
        .toList();

    records.sort((a, b) {
      final compare = a.createdAt.compareTo(b.createdAt);
      return _recordSortOrder == RecordSortOrder.latestFirst
          ? -compare
          : compare;
    });
    return records;
  }

  String _getFormattedDate(String? iso) =>
      _applicantsController.getFormattedDate(iso);

  String _formTypeBadgeText(String formType) =>
      _applicantsController.formTypeBadgeText(formType);

  Color _formTypeBadgeColor(String formType) =>
      _applicantsController.formTypeBadgeColor(formType);

  // Logout / navigation
  Future<void> _handleLogout() => WebSession.logout(context);

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'Applicants',
      pageSubtitle: 'Review submitted client intake forms',
      role: widget.role,
      cswdId: widget.cswdId,
      displayName: widget.displayName,
      onLogout: _handleLogout,
      headerActions: [
        WebHeaderButton('Refresh', Icons.refresh, onPressed: _loadData),
      ],
      onNavigate: (p) => WebNavigator.go(
        context,
        p,
        cswdId: widget.cswdId,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(),
            if (_degraded) ...[
              const SizedBox(height: 12),
              const WebDegradedResultsBanner(),
            ],
            const SizedBox(height: 16),
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
                            child: _selected == null
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

  Widget _buildFilterBar() {
    final formTypes = ['All', ..._templateCache.keys.toList()..sort()];
    final currentFormType = _filters.formType ?? 'All';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: WebSearchField(
              controller: _searchController,
              hintText: 'Search name, reference, phone, or email...',
              onChanged: _handleSearchChanged,
              onSubmitted: _handleSearchSubmitted,
            ),
          ),
          const SizedBox(width: 12),
          WebDropdownFilter(
            value: formTypes.contains(currentFormType) ? currentFormType : 'All',
            hint: 'All Forms',
            items: formTypes,
            labels: {for (final f in formTypes) f: f},
            onChanged: (v) => _updateFilters(
              _filters.copyWith(formType: v == 'All' ? null : v),
            ),
          ),
          const SizedBox(width: 12),
          WebDropdownFilter(
            value: _filters.accountLink.wireValue,
            hint: 'All applicants',
            items: AccountLinkFilter.values.map((v) => v.wireValue).toList(),
            labels: {
              for (final v in AccountLinkFilter.values) v.wireValue: v.label,
            },
            onChanged: (v) => _updateFilters(
              _filters.copyWith(
                accountLink: AccountLinkFilter.values.firstWhere(
                  (e) => e.wireValue == v,
                  orElse: () => AccountLinkFilter.all,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          WebDropdownFilter(
            value: _sortOrder.wireValue,
            hint: 'Sort',
            items: ApplicantSortOrder.values.map((v) => v.wireValue).toList(),
            labels: {
              for (final v in ApplicantSortOrder.values) v.wireValue: v.label,
            },
            onChanged: (v) {
              setState(
                () => _sortOrder = ApplicantSortOrder.values.firstWhere(
                  (e) => e.wireValue == v,
                  orElse: () => ApplicantSortOrder.recent,
                ),
              );
              _runSearch(reset: true);
            },
          ),
          const SizedBox(width: 12),
          WebDateFilterButton(
            label: _filters.dateFrom == null
                ? 'From date'
                : _getFormattedDate(_filters.dateFrom!.toIso8601String()),
            onTap: () => _pickDate(isFrom: true),
            isSet: _filters.dateFrom != null,
          ),
          const SizedBox(width: 8),
          WebDateFilterButton(
            label: _filters.dateTo == null
                ? 'To date'
                : _getFormattedDate(_filters.dateTo!.toIso8601String()),
            onTap: () => _pickDate(isFrom: false),
            isSet: _filters.dateTo != null,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _resetFilters,
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            tooltip: 'Reset filters',
          ),
        ],
      ),
    );
  }

  // Left panel: applicant list
  Widget _buildListPanel() {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
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
                if (_isSearching)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.highlight,
                    ),
                  )
                else
                  Text(
                    _hasMore
                        ? '${_applicants.length}+'
                        : '${_applicants.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.cardBorder),
          Expanded(child: _buildApplicantList()),
        ],
      ),
    );
  }

  Widget _buildApplicantList() {
    if (_queryTooShort) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Type at least '
            '${ApplicantSearchService.minQueryLength} characters to search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.textMuted,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                _searchError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _runSearch(reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching && _applicants.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.highlight),
      );
    }

    if (_applicants.isEmpty) {
      return const Center(
        child: Text(
          'No applicants found.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      controller: _listScroll,
      itemCount: _applicants.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: AppColors.cardBorder,
        indent: 14,
        endIndent: 14,
      ),
      itemBuilder: (ctx, i) {
        if (i >= _applicants.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.highlight,
                ),
              ),
            ),
          );
        }
        return _buildApplicantRow(_applicants[i]);
      },
    );
  }

  /// One row per distinct person. Carries a record count, dates, reference and
  /// origin badge — with automatic merging unavailable for weak matches, this
  /// detail is what lets an admin tell two same-name applicants apart.
  Widget _buildApplicantRow(ApplicantSummary applicant) {
    final isSelected = _selected?.identityKey == applicant.identityKey;
    final initials = applicant.displayName
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.trim().isNotEmpty)
        .take(2)
        .map((p) => p.trim()[0].toUpperCase())
        .join();

    final recordLabel = applicant.submissionCount == 1
        ? '1 record'
        : '${applicant.submissionCount} records';
    final latest = _getFormattedDate(applicant.latestSubmissionAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: AppColors.pageBg,
        splashColor: AppColors.highlight.withValues(alpha: 0.08),
        onTap: () {
          setState(() {
            _cancelSubmissionLoad();
            _selected = applicant;
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
                ? AppColors.highlight.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.highlight : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.highlight.withValues(alpha: 0.15)
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            applicant.displayName,
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
                        const SizedBox(width: 6),
                        _buildOriginBadge(applicant),
                      ],
                    ),
                    // Account username, when there is one. Walk-ins have no
                    // account, so the line is omitted rather than shown empty.
                    if (applicant.username != null &&
                        applicant.username!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${applicant.username}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      latest == '-'
                          ? recordLabel
                          : '$recordLabel · latest $latest',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (applicant.latestIntakeReference != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ref: ${applicant.latestIntakeReference}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (applicant.formTypes.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: applicant.formTypes
                            .map(_buildFormTypeChip)
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isSelected
                      ? AppColors.highlight
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOriginBadge(ApplicantSummary applicant) {
    final isMobile = applicant.isLinkedAccount;
    final color = isMobile ? const Color(0xFF2B74E4) : const Color(0xFF8A6BDB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        applicant.originLabel,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFormTypeChip(String formType) {
    final color = _formTypeBadgeColor(formType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _formTypeBadgeText(formType),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
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
              color: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select an applicant to view records',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15),
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
              'Loading applicants...',
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
    final applicant = _selected;
    if (applicant == null) return _buildEmptyState();

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
                      applicant.displayName,
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

    final options = _formTypeOptions;
    if (!options.contains(_formTypeFilter)) {
      _formTypeFilter = 'All';
    }
    final records = _visibleRecords;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          applicant.displayName,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _applicantSubtitle(applicant),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
                  itemBuilder: (_, idx) =>
                      _buildRecordRow(records[idx]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _applicantSubtitle(ApplicantSummary applicant) {
    final parts = <String>[
      applicant.submissionCount == 1
          ? '1 record'
          : '${applicant.submissionCount} records',
      applicant.originLabel,
    ];
    final first = _getFormattedDate(applicant.firstSubmissionAt);
    final last = _getFormattedDate(applicant.latestSubmissionAt);
    if (first != '-' && last != '-') {
      parts.add(first == last ? first : '$first – $last');
    }
    return parts.join(' · ');
  }

  Widget _buildRecordRow(ApplicantSubmissionRef record) {
    final formType = record.formType.isEmpty ? 'Unknown Form' : record.formType;
    final badgeText = _formTypeBadgeText(formType);
    final badgeColor = _formTypeBadgeColor(formType);
    final reference = record.intakeReference?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: AppColors.pageBg,
        splashColor: AppColors.highlight.withValues(alpha: 0.08),
        onTap: () => _openSubmission(record.toSubmissionMap()),
        child: SizedBox(
          height: 78,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                        _getFormattedDate(record.createdAt),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Ref: ${reference == null || reference.isEmpty ? 'No reference' : reference}',
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
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 12,
                    ),
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
    _searchDebouncer.dispose();
    _listScroll.dispose();
    _searchService.dispose();
    _searchController.dispose();
    _intakeRefCtrl.dispose();
    _viewCtrl?.dispose();
    super.dispose();
  }
}
