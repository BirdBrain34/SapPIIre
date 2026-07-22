import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/widgets/filter_controls.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/utils/debouncer.dart';
import 'package:sappiire/web/utils/web_navigator.dart';

class AuditLogsScreen extends StatefulWidget {
  final String cswdId;
  final String role;
  final String displayName;

  const AuditLogsScreen({
    super.key,
    required this.cswdId,
    required this.role,
    required this.displayName,
  });

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final _service = AuditLogService();
  final _searchController = TextEditingController();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 400));

  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _displayLogs = [];
  int _totalCount = 0;
  bool _isLoading = true;

  String _categoryFilter = '';
  String _actionFilter = '';
  String _severityFilter = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Number of *display rows* (after grouping) we aim to show per page.
  static const _pageSize = 50;
  // How many raw logs we pull per fetch while accumulating a page.
  static const _rawBatchSize = 100;
  int _currentPage = 0;
  // Raw-row offset where each visited page begins. _pageRawOffsets[p] is the
  // raw offset to start fetching page p from. Grows as the user pages forward.
  final List<int> _pageRawOffsets = [0];
  bool _hasMorePages = false;

  final _categories = [
    '',
    'auth',
    'session',
    'submission',
    'staff',
    'template',
  ];
  final _severities = ['', 'info', 'warning', 'critical'];
  final _actions = [
    '',
    kAuditLogin, kAuditLoginFailed, kAuditLogout, kAuditPasswordChanged,
    kAuditSubmissionCreated, kAuditSubmissionEdited, kAuditSubmissionDeleted, kAuditSubmissionDecrypted,
    kAuditSubmissionPreviewDecrypted, kAuditApplicantNamesResolved,
    kAuditApplicantSearch,
    kAuditStaffCreated, kAuditStaffApproved, kAuditStaffRejected, kAuditRoleChanged,
    kAuditTemplateCreated, kAuditTemplatePublished, kAuditTemplatePushed, kAuditTemplateArchived, kAuditTemplateDeleted,
    kAuditTemplateSubmittedForApproval, kAuditTemplateApproved, kAuditTemplateRejected,
    kAuditSessionStarted, kAuditSessionCompleted, kAuditSessionClosed,
    kAuditCanonicalKeyCreated, kAuditCanonicalKeyDeactivated,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.role != 'superadmin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    _loadLogs();
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    // Accumulate raw logs starting at this page's raw offset, grouping as we go,
    // until we have more than a full page of display rows (or run out of data).
    // This keeps the screen filled even when a large group (e.g. dozens of
    // "Submission Decrypted" events) collapses into a single row.
    final startRaw = _pageRawOffsets[_currentPage];
    final accumulated = <Map<String, dynamic>>[];
    var rawCursor = startRaw;
    var grouped = <Map<String, dynamic>>[];

    while (true) {
      final batch = await _service.fetchLogs(
        limit: _rawBatchSize,
        offset: rawCursor,
        categoryFilter: _categoryFilter.isEmpty ? null : _categoryFilter,
        actionFilter: _actionFilter.isEmpty ? null : _actionFilter,
        severityFilter: _severityFilter.isEmpty ? null : _severityFilter,
        actorFilter: _searchController.text.isEmpty
            ? null
            : _searchController.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (batch.isEmpty) break;
      accumulated.addAll(batch);
      rawCursor += batch.length;
      grouped = _groupDecryptionLogs(accumulated);
      // Reached the end of the dataset.
      if (batch.length < _rawBatchSize) break;
      // One extra display row past the page tells us there's more to show and
      // guarantees the rows we keep are fully-formed (not an open group).
      if (grouped.length > _pageSize) break;
    }

    final totalCount = await _service.fetchCount(
      categoryFilter: _categoryFilter.isEmpty ? null : _categoryFilter,
      actionFilter: _actionFilter.isEmpty ? null : _actionFilter,
      severityFilter: _severityFilter.isEmpty ? null : _severityFilter,
      actorFilter: _searchController.text.isEmpty
          ? null
          : _searchController.text,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    );

    if (!mounted) return;

    final hasMore = grouped.length > _pageSize;
    final pageRows = hasMore ? grouped.sublist(0, _pageSize) : grouped;
    // The raw logs that actually back the displayed rows (a grouped row expands
    // to its members). Drives both the next-page offset and the summary strip,
    // so counts reflect exactly what's on screen.
    final pageRawLogs = <Map<String, dynamic>>[];
    for (final row in pageRows) {
      final members = row['_groupedLogs'] as List?;
      if (members != null) {
        pageRawLogs.addAll(
          members.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } else {
        pageRawLogs.add(row);
      }
    }
    final nextOffset = startRaw + pageRawLogs.length;
    if (_pageRawOffsets.length <= _currentPage + 1) {
      _pageRawOffsets.add(nextOffset);
    } else {
      _pageRawOffsets[_currentPage + 1] = nextOffset;
    }

    setState(() {
      _logs = pageRawLogs;
      _displayLogs = pageRows;
      _hasMorePages = hasMore;
      _totalCount = totalCount;
      _isLoading = false;
    });
  }

  // Filters change the underlying dataset, so the cached per-page raw offsets
  // are no longer valid -> rewind to the first page.
  void _resetPaging() {
    _currentPage = 0;
    _pageRawOffsets
      ..clear()
      ..add(0);
  }

  void _resetFilters() {
    setState(() {
      _categoryFilter = '';
      _actionFilter = '';
      _severityFilter = '';
      _dateFrom = null;
      _dateTo = null;
      _resetPaging();
      _searchController.clear();
    });
    _loadLogs();
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateFrom ?? DateTime.now().subtract(const Duration(days: 7)),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked;
        _resetPaging();
      });
      _loadLogs();
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateTo = picked;
        _resetPaging();
      });
      _loadLogs();
    }
  }

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFE63946);
      case 'warning':
        return const Color(0xFFF4A261);
      default:
        return const Color(0xFF2EC4B6);
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'auth':
        return Icons.lock_outline;
      case 'session':
        return Icons.qr_code_scanner;
      case 'submission':
        return Icons.description_outlined;
      case 'staff':
        return Icons.people_outline;
      case 'template':
        return Icons.dashboard_customize_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _categoryColor(String? category) {
    switch (category) {
      case 'auth':
        return AppColors.highlight;
      case 'session':
        return const Color(0xFF4ECDC4);
      case 'submission':
        return const Color(0xFF95E1D3);
      case 'staff':
        return const Color(0xFFAA96DA);
      case 'template':
        return const Color(0xFFFFA500);
      default:
        return AppColors.textMuted;
    }
  }

  // ==========================================================================
  // Plain-language wording
  //
  // This screen is read by caseworkers and senior officials, not engineers.
  // Everything shown here is written in everyday office language: "form"
  // rather than "template", "opened" rather than "decrypted", and no database
  // or cryptography terms anywhere on screen.
  // ==========================================================================

  String _actionLabel(String? action) {
    switch (action) {
      case kAuditLogin:
        return 'Signed in';
      case kAuditLoginFailed:
        return 'Failed sign-in attempt';
      case kAuditLogout:
        return 'Signed out';
      case kAuditPasswordChanged:
        return 'Password changed';
      case kAuditSessionStarted:
        return 'Intake session started';
      case kAuditSessionCompleted:
        return 'Intake session completed';
      case kAuditSessionClosed:
        return 'Intake session closed';
      case kAuditSubmissionCreated:
        return 'Applicant record saved';
      case kAuditSubmissionEdited:
        return 'Applicant record edited';
      case kAuditSubmissionDeleted:
        return 'Applicant record deleted';
      case kAuditSubmissionDecrypted:
        return 'Applicant record opened';
      case kAuditSubmissionPreviewDecrypted:
        return 'Submitted form reviewed';
      case kAuditApplicantNamesResolved:
        return 'Applicant names displayed';
      case kAuditApplicantSearch:
        return 'Applicant search';
      case kAuditStaffCreated:
        return 'Staff account created';
      case kAuditStaffApproved:
        return 'Staff account approved';
      case kAuditStaffRejected:
        return 'Staff account rejected';
      case kAuditRoleChanged:
        return 'Staff role changed';
      case kAuditTemplateCreated:
        return 'Form created';
      case kAuditTemplatePublished:
        return 'Form published';
      case kAuditTemplatePushed:
        return 'Form sent to mobile app';
      case kAuditTemplateArchived:
        return 'Form archived';
      case kAuditTemplateDeleted:
        return 'Form deleted';
      case kAuditTemplateSubmittedForApproval:
        return 'Form sent for approval';
      case kAuditTemplateApproved:
        return 'Form approved';
      case kAuditTemplateRejected:
        return 'Form rejected';
      case kAuditCanonicalKeyCreated:
        return 'Shared field added';
      case kAuditCanonicalKeyDeactivated:
        return 'Shared field removed';
      default:
        return action ?? 'Unknown activity';
    }
  }

  /// One sentence saying what actually happened, shown when a staff member
  /// opens an entry. The label alone cannot carry why an entry matters.
  String _actionDescription(String? action) {
    switch (action) {
      case kAuditLogin:
        return 'A staff member signed in to the system.';
      case kAuditLoginFailed:
        return 'Someone tried to sign in but the details were incorrect. '
            'Repeated attempts in a short time may mean someone is trying to '
            'guess a password.';
      case kAuditLogout:
        return 'A staff member signed out.';
      case kAuditPasswordChanged:
        return 'A staff member changed their password.';
      case kAuditSessionStarted:
        return 'A staff member started an intake session for a client.';
      case kAuditSessionCompleted:
        return 'An intake session was finished and the record was saved.';
      case kAuditSessionClosed:
        return 'An intake session was closed without being completed.';
      case kAuditSubmissionCreated:
        return 'A new applicant record was saved.';
      case kAuditSubmissionEdited:
        return 'An existing applicant record was changed.';
      case kAuditSubmissionDeleted:
        return 'An applicant record was deleted.';
      case kAuditSubmissionDecrypted:
        return 'An applicant\'s protected personal information was opened and '
            'viewed. Personal details are kept locked in storage, so every '
            'time someone views them it is recorded here.';
      case kAuditSubmissionPreviewDecrypted:
        return 'A form sent in from the mobile app was opened for checking '
            'before it was saved.';
      case kAuditApplicantNamesResolved:
        return 'Applicant names were unlocked so they could be shown in a list '
            'on screen. Only the names were shown, not the full records.';
      case kAuditApplicantSearch:
        return 'A staff member searched the applicant records. The search '
            'wording itself is never stored here, only that a search happened.';
      case kAuditStaffCreated:
        return 'A new staff account was created.';
      case kAuditStaffApproved:
        return 'A staff account was approved and can now be used.';
      case kAuditStaffRejected:
        return 'A staff account request was refused.';
      case kAuditRoleChanged:
        return 'A staff member\'s level of access was changed.';
      case kAuditTemplateCreated:
        return 'A new form was created.';
      case kAuditTemplatePublished:
        return 'A form was published and is now available to staff.';
      case kAuditTemplatePushed:
        return 'A form was sent to the mobile app for clients to fill in.';
      case kAuditTemplateArchived:
        return 'A form was archived and is no longer offered for new intakes.';
      case kAuditTemplateDeleted:
        return 'A form was deleted.';
      case kAuditTemplateSubmittedForApproval:
        return 'A form was sent to a Super Administrator for approval. It is '
            'not available to staff until it is approved.';
      case kAuditTemplateApproved:
        return 'A form was approved and published.';
      case kAuditTemplateRejected:
        return 'A form was refused during approval and sent back as a draft. '
            'The reason given is shown below.';
      case kAuditCanonicalKeyCreated:
        return 'A shared field was added, so the same question can be matched '
            'across different forms.';
      case kAuditCanonicalKeyDeactivated:
        return 'A shared field was removed from matching.';
      default:
        return 'Activity recorded by the system.';
    }
  }

  String _categoryLabel(String? category) {
    switch (category) {
      case kCategoryAuth:
        return 'Sign-in';
      case kCategorySession:
        return 'Intake sessions';
      case kCategorySubmission:
        return 'Applicant records';
      case kCategoryStaff:
        return 'Staff accounts';
      case kCategoryTemplate:
        return 'Forms';
      default:
        return category == null || category.isEmpty ? 'Other' : category;
    }
  }

  /// Severity in words a caseworker can act on. "Sensitive" is the level used
  /// whenever protected personal information was opened.
  String _severityLabel(String? severity) {
    switch (severity) {
      case kSeverityCritical:
        return 'Sensitive';
      case kSeverityWarning:
        return 'Notice';
      default:
        return 'Routine';
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'superadmin':
        return 'Super Administrator';
      case 'admin':
        return 'Administrator';
      default:
        return role == null || role.isEmpty ? '-' : role;
    }
  }

  String _targetTypeLabel(String? type) {
    switch (type) {
      case 'client_submission':
      case 'client_submissions':
        return 'Applicant record';
      case 'form_template':
        return 'Form';
      case 'form_submission':
        return 'Intake session';
      case 'staff_account':
        return 'Staff account';
      case 'user_field_values':
        return 'Applicant details';
      default:
        return type == null || type.isEmpty ? '-' : type;
    }
  }

  /// Technical bookkeeping that means nothing to a caseworker. Kept out of the
  /// detail panel rather than shown as unexplained numbers.
  static const _hiddenDetailKeys = {
    'ids',
    'query_hash',
    'query_length',
    'token_count',
    'filters',
    'intended_action',
    'transmission_version',
    'account_link',
    'scope',
  };

  String _detailKeyLabel(String key) {
    switch (key) {
      case 'purpose':
        return 'Reason';
      case 'reason':
        return 'Reason given';
      case 'count':
        return 'Records opened';
      case 'resolved':
        return 'Names shown';
      case 'requested':
        return 'Names requested';
      case 'candidate_rows':
        return 'Records searched';
      case 'decrypted_blobs':
        return 'Records opened';
      case 'users_resolved':
        return 'Names shown';
      case 'applicants_returned':
        return 'Applicants found';
      case 'truncated':
        return 'Results incomplete';
      case 'elapsed_ms':
        return 'Time taken';
      default:
        // last_edited_by -> "Last edited by"
        final spaced = key.replaceAll('_', ' ').trim();
        if (spaced.isEmpty) return key;
        return spaced[0].toUpperCase() + spaced.substring(1);
    }
  }

  String _detailValueLabel(String key, Object? value) {
    if (value == null) return '-';
    if (key == 'purpose') {
      switch (value.toString()) {
        case 'applicant_record_view':
          return 'Opening a single applicant record';
        case 'list_view':
          return 'Showing the applicant list';
        case 'search':
          return 'Searching for an applicant';
      }
    }
    if (key == 'elapsed_ms') {
      final ms = int.tryParse(value.toString());
      if (ms != null) {
        return ms < 1000 ? '$ms milliseconds' : '${(ms / 1000).toStringAsFixed(1)} seconds';
      }
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (value.toString() == 'true') return 'Yes';
    if (value.toString() == 'false') return 'No';
    return value.toString();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m:$s';
    } catch (_) {
      return iso;
    }
  }

  /// Action types emitted in bursts, which are collapsed into a single display
  /// row per actor per 5-minute window.
  ///
  /// Applicant search is here because a debounced search box still emits one
  /// event per settled query — ten minutes of an admin looking someone up
  /// would otherwise bury every other event on the page. The names-resolved
  /// action is included because it is what `search-applicants` falls back to
  /// when the live table rejects `applicant_search`.
  static const _collapsibleActions = {
    kAuditSubmissionDecrypted,
    kAuditApplicantSearch,
    kAuditApplicantNamesResolved,
  };

  List<Map<String, dynamic>> _groupDecryptionLogs(List<Map<String, dynamic>> logs) {
    final result = <Map<String, dynamic>>[];
    for (final log in logs) {
      final actionType = log['action_type'];
      if (!_collapsibleActions.contains(actionType)) {
        result.add(log);
        continue;
      }
      if (result.isNotEmpty) {
        final last = result.last;
        if (last['action_type'] == actionType &&
            last['actor_id'] == log['actor_id']) {
          final groupStart = DateTime.tryParse(last['created_at'] as String? ?? '');
          final thisTime = DateTime.tryParse(log['created_at'] as String? ?? '');
          if (groupStart != null && thisTime != null &&
              groupStart.difference(thisTime).abs().inMinutes < 5) {
            final grouped = List<Map<String, dynamic>>.from(
              last['_groupedLogs'] as List? ?? [last],
            )..add(log);
            result[result.length - 1] = {
              ...last,
              '_groupCount': grouped.length,
              '_groupedLogs': grouped,
            };
            continue;
          }
        }
      }
      result.add({...log, '_groupCount': 1, '_groupedLogs': <Map<String, dynamic>>[log]});
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'AuditLogs',
      pageTitle: 'Audit Logs',
      pageSubtitle: 'System-wide activity trail - superadmin view',
      role: widget.role,
      cswdId: widget.cswdId,
      displayName: widget.displayName,
      onLogout: _handleLogout,
      onNavigate: (path) => WebNavigator.go(
        context,
        path,
        cswdId: widget.cswdId,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryStrip(),
            const SizedBox(height: 20),
            _buildFilterBar(),
            const SizedBox(height: 20),
            Expanded(child: _buildLogsTable()),
            if (_currentPage > 0 || _hasMorePages) ...[
              const SizedBox(height: 16),
              _buildPagination(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStrip() {
    final categories = ['auth', 'submission', 'staff', 'template', 'session'];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 90),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _summaryCard(
                label: 'Total activity',
                value: _totalCount.toString(),
                color: AppColors.primaryBlue,
                icon: Icons.history,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                label: 'Sensitive',
                value: _logs
                    .where((l) => l['severity'] == kSeverityCritical)
                    .length
                    .toString(),
                color: const Color(0xFFE63946),
                icon: Icons.warning_amber_rounded,
              ),
              const SizedBox(width: 12),
              ...categories.map(
                (cat) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _summaryCard(
                    label: _categoryLabel(cat),
                    value: _logs
                        .where((l) => l['category'] == cat)
                        .length
                        .toString(),
                    color: _categoryColor(cat),
                    icon: _categoryIcon(cat),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 140,
      constraints: const BoxConstraints(minHeight: 90),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha:  0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha:  0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
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
              hintText: 'Search by actor name...',
              // Search on typing rather than only on Enter, but debounced so a
              // burst of keystrokes is one query.
              onChanged: (_) => _searchDebouncer.run(() {
                if (!mounted) return;
                _resetPaging();
                _loadLogs();
              }),
              onSubmitted: (_) => _searchDebouncer.flush(() {
                if (!mounted) return;
                _resetPaging();
                _loadLogs();
              }),
            ),
          ),
          const SizedBox(width: 12),
          _buildDropdownFilter(
            value: _categoryFilter,
            hint: 'All activity',
            items: _categories,
            labels: {
              for (final c in _categories)
                c: c.isEmpty ? 'All activity' : _categoryLabel(c),
            },
            onChanged: (v) {
              setState(() {
                _categoryFilter = v ?? '';
                _resetPaging();
              });
              _loadLogs();
            },
          ),
          const SizedBox(width: 12),
          _buildDropdownFilter(
            value: _actionFilter,
            hint: 'All Actions',
            items: _actions,
            labels: {
              for (final a in _actions) a: a.isEmpty ? 'All Actions' : _actionLabel(a),
            },
            onChanged: (v) {
              setState(() {
                _actionFilter = v ?? '';
                _resetPaging();
              });
              _loadLogs();
            },
          ),
          const SizedBox(width: 12),
          _buildDropdownFilter(
            value: _severityFilter,
            hint: 'All Severities',
            items: _severities,
            labels: {
              for (final s in _severities)
                s: s.isEmpty ? 'All importance levels' : _severityLabel(s),
            },
            onChanged: (v) {
              setState(() {
                _severityFilter = v ?? '';
                _resetPaging();
              });
              _loadLogs();
            },
          ),
          const SizedBox(width: 12),
          _buildDateButton(
            label: _dateFrom == null
                ? 'From date'
                : '${_dateFrom!.month}/${_dateFrom!.day}/${_dateFrom!.year}',
            onTap: _pickDateFrom,
            isSet: _dateFrom != null,
          ),
          const SizedBox(width: 8),
          _buildDateButton(
            label: _dateTo == null
                ? 'To date'
                : '${_dateTo!.month}/${_dateTo!.day}/${_dateTo!.year}',
            onTap: _pickDateTo,
            isSet: _dateTo != null,
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

  // Chrome now lives in web/widgets/filter_controls.dart so the applicants
  // filter bar renders identically. These thin wrappers keep the call sites
  // in _buildFilterBar unchanged.
  Widget _buildDropdownFilter({
    required String value,
    required String hint,
    required List<String> items,
    required Map<String, String> labels,
    required ValueChanged<String?> onChanged,
  }) {
    return WebDropdownFilter(
      value: value,
      hint: hint,
      items: items,
      labels: labels,
      onChanged: onChanged,
    );
  }

  Widget _buildDateButton({
    required String label,
    required VoidCallback onTap,
    required bool isSet,
  }) {
    return WebDateFilterButton(label: label, onTap: onTap, isSet: isSet);
  }

  Widget _buildLogsTable() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.highlight),
      );
    }

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_outlined,
              size: 64,
              color: AppColors.textMuted.withValues(alpha:  0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No audit logs found',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting the filters',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.pageBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 12),
                SizedBox(width: 8),
                Expanded(flex: 2, child: _TableHeader('Timestamp')),
                Expanded(flex: 1, child: _TableHeader('Category')),
                Expanded(flex: 2, child: _TableHeader('Action')),
                Expanded(flex: 2, child: _TableHeader('Actor')),
                Expanded(flex: 3, child: _TableHeader('Target')),
                Expanded(flex: 1, child: _TableHeader('Severity')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Expanded(
            child: ListView.separated(
              itemCount: _displayLogs.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.cardBorder),
              itemBuilder: (_, i) => _buildLogRow(_displayLogs[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(Map<String, dynamic> log) {
    final severity = log['severity'] as String? ?? 'info';
    final category = log['category'] as String? ?? '';
    final action = log['action_type'] as String? ?? '';
    final actorName = log['actor_name'] as String? ?? '-';
    final actorRole = log['actor_role'] as String? ?? '';
    final target = log['target_label'] as String? ?? '-';
    final targetType = log['target_type'] as String? ?? '';
    final timestamp = log['created_at'] as String?;
    final groupCount = log['_groupCount'] as int? ?? 1;

    final severityColor = _severityColor(severity);
    final catColor = _categoryColor(category);

    return InkWell(
      onTap: () => _showLogDetail(log),
      hoverColor: AppColors.pageBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: severityColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text(
                _formatDate(timestamp),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha:  0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_categoryIcon(category), size: 12, color: catColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _categoryLabel(category),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: catColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _actionLabel(action),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (groupCount > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.highlight.withValues(alpha:  0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '×$groupCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.highlight,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actorName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (actorRole.isNotEmpty)
                    Text(
                      actorRole,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    target,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (targetType.isNotEmpty)
                    Text(
                      targetType.replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha:  0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _severityLabel(severity).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: severityColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogDetail(Map<String, dynamic> log) {
    final groupCount = log['_groupCount'] as int? ?? 1;
    if (groupCount > 1) {
      _showGroupedLogDetail(log);
      return;
    }
    final rawDetails = log['details'];
    final details = rawDetails is Map<String, dynamic>
        ? rawDetails
        : rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : <String, dynamic>{};

    final visibleDetails = <String, dynamic>{
      for (final e in details.entries)
        if (!_hiddenDetailKeys.contains(e.key)) e.key: e.value,
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _categoryColor(log['category']).withValues(alpha:  0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _categoryIcon(log['category']),
                color: _categoryColor(log['category']),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _actionLabel(log['action_type']),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionDescription(log['action_type']?.toString()),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                _detailRow(
                  'When',
                  _formatDate(log['created_at']?.toString()),
                ),
                _detailRow('Performed by', log['actor_name']?.toString() ?? '-'),
                _detailRow('Role', _roleLabel(log['actor_role']?.toString())),
                _detailRow('Activity', _categoryLabel(log['category']?.toString())),
                _detailRow(
                  'Importance',
                  _severityLabel(log['severity']?.toString()),
                ),
                _detailRow(
                  'Item type',
                  _targetTypeLabel(log['target_type']?.toString()),
                ),
                _detailRow('Item', log['target_label']?.toString() ?? '-'),
                if (visibleDetails.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'More information',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...visibleDetails.entries.map(
                    (e) => _detailRow(
                      _detailKeyLabel(e.key),
                      _detailValueLabel(e.key, e.value),
                    ),
                  ),
                ],
                const Divider(),
                // Kept for investigations, but out of the way and clearly
                // marked as reference numbers rather than anything meaningful.
                _detailRow(
                  'Reference (staff)',
                  log['actor_id']?.toString() ?? '-',
                ),
                _detailRow(
                  'Reference (item)',
                  log['target_id']?.toString() ?? '-',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGroupedLogDetail(Map<String, dynamic> log) {
    final groupedRaw = log['_groupedLogs'] as List? ?? [log];
    final grouped = groupedRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final count = grouped.length;
    // Rows are newest-first within the group.
    final latest = grouped.first['created_at']?.toString();
    final earliest = grouped.last['created_at']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _categoryColor(log['category']).withValues(alpha:  0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _categoryIcon(log['category']),
                color: _categoryColor(log['category']),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_actionLabel(log['action_type'])} (×$count)',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _actionDescription(log['action_type']?.toString()),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              _detailRow('Performed by', log['actor_name']?.toString() ?? '-'),
              _detailRow('Role', _roleLabel(log['actor_role']?.toString())),
              _detailRow('Activity', _categoryLabel(log['category']?.toString())),
              _detailRow(
                'Importance',
                _severityLabel(log['severity']?.toString()),
              ),
              _detailRow(
                'Between',
                '${_formatDate(earliest)}  and  ${_formatDate(latest)}',
              ),
              const Divider(),
              Text(
                '$count times in this period',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: grouped.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.cardBorder),
                  itemBuilder: (_, i) {
                    final g = grouped[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            g['target_label']?.toString() ?? '-',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${g['target_id'] ?? '-'}  •  ${_formatDate(g['created_at']?.toString())}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontFamily: 'monospace',
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _currentPage > 0
              ? () {
                  setState(() => _currentPage--);
                  _loadLogs();
                }
              : null,
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          'Page ${_currentPage + 1}  ($_totalCount total events)',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _hasMorePages
              ? () {
                  setState(() => _currentPage++);
                  _loadLogs();
                }
              : null,
          icon: const Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ],
    );
  }

  Future<void> _handleLogout() => WebSession.logout(context);

}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}
