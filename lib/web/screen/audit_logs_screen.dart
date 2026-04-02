import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';

class AuditLogsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;

  const AuditLogsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.displayName,
  });

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final _service = AuditLogService();
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _logs = [];
  int _totalCount = 0;
  bool _isLoading = true;

  String _categoryFilter = '';
  String _severityFilter = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const _pageSize = 50;
  int _currentPage = 0;

  final _categories = [
    '',
    'auth',
    'session',
    'submission',
    'staff',
    'template',
  ];
  final _severities = ['', 'info', 'warning', 'critical'];

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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _service.fetchLogs(
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        categoryFilter: _categoryFilter.isEmpty ? null : _categoryFilter,
        severityFilter: _severityFilter.isEmpty ? null : _severityFilter,
        actorFilter: _searchController.text.isEmpty
            ? null
            : _searchController.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      ),
      _service.fetchCount(
        categoryFilter: _categoryFilter.isEmpty ? null : _categoryFilter,
        severityFilter: _severityFilter.isEmpty ? null : _severityFilter,
        actorFilter: _searchController.text.isEmpty
            ? null
            : _searchController.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _logs = results[0] as List<Map<String, dynamic>>;
      _totalCount = results[1] as int;
      _isLoading = false;
    });
  }

  void _resetFilters() {
    setState(() {
      _categoryFilter = '';
      _severityFilter = '';
      _dateFrom = null;
      _dateTo = null;
      _currentPage = 0;
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
        _currentPage = 0;
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
        _currentPage = 0;
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

  String _actionLabel(String? action) {
    switch (action) {
      case kAuditLogin:
        return 'Login';
      case kAuditLoginFailed:
        return 'Login Failed';
      case kAuditLogout:
        return 'Logout';
      case kAuditPasswordChanged:
        return 'Password Changed';
      case kAuditSessionStarted:
        return 'Session Started';
      case kAuditSessionCompleted:
        return 'Session Completed';
      case kAuditSessionClosed:
        return 'Session Closed';
      case kAuditSubmissionCreated:
        return 'Submission Created';
      case kAuditSubmissionEdited:
        return 'Submission Edited';
      case kAuditSubmissionDeleted:
        return 'Submission Deleted';
      case kAuditStaffCreated:
        return 'Staff Created';
      case kAuditStaffApproved:
        return 'Staff Approved';
      case kAuditStaffRejected:
        return 'Staff Rejected';
      case kAuditRoleChanged:
        return 'Role Changed';
      case kAuditTemplateCreated:
        return 'Template Created';
      case kAuditTemplatePublished:
        return 'Template Published';
      case kAuditTemplatePushed:
        return 'Pushed to Mobile';
      case kAuditTemplateArchived:
        return 'Template Archived';
      case kAuditTemplateDeleted:
        return 'Template Deleted';
      default:
        return action ?? 'Unknown';
    }
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

  int get _totalPages => (_totalCount / _pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'AuditLogs',
      pageTitle: 'Audit Logs',
      pageSubtitle: 'System-wide activity trail - superadmin view',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: _handleLogout,
      onNavigate: (path) => _navigateToScreen(context, path),
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
            if (_totalPages > 1) ...[
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
                label: 'Total Events',
                value: _totalCount.toString(),
                color: AppColors.primaryBlue,
                icon: Icons.history,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                label: 'Critical',
                value: _logs
                    .where((l) => l['severity'] == 'critical')
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
                    label: cat[0].toUpperCase() + cat.substring(1),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
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
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) {
                _currentPage = 0;
                _loadLogs();
              },
              decoration: InputDecoration(
                hintText: 'Search by actor name...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
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
          ),
          const SizedBox(width: 12),
          _buildDropdownFilter(
            value: _categoryFilter,
            hint: 'All Categories',
            items: _categories,
            labels: {
              '': 'All Categories',
              'auth': 'Auth',
              'session': 'Sessions',
              'submission': 'Submissions',
              'staff': 'Staff',
              'template': 'Templates',
            },
            onChanged: (v) {
              setState(() {
                _categoryFilter = v ?? '';
                _currentPage = 0;
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
              '': 'All Severities',
              'info': 'Info',
              'warning': 'Warning',
              'critical': 'Critical',
            },
            onChanged: (v) {
              setState(() {
                _severityFilter = v ?? '';
                _currentPage = 0;
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

  Widget _buildDropdownFilter({
    required String value,
    required String hint,
    required List<String> items,
    required Map<String, String> labels,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          isDense: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labels[item] ?? item,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required VoidCallback onTap,
    required bool isSet,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        Icons.calendar_today,
        size: 14,
        color: isSet ? AppColors.highlight : AppColors.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSet ? AppColors.highlight : AppColors.textMuted,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isSet ? AppColors.highlight : AppColors.cardBorder,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
              color: AppColors.textMuted.withValues(alpha: 0.4),
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
              itemCount: _logs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.cardBorder),
              itemBuilder: (_, i) => _buildLogRow(_logs[i]),
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
                  color: catColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_categoryIcon(category), size: 12, color: catColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        category,
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
                  color: severityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  severity.toUpperCase(),
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
    final rawDetails = log['details'];
    final details = rawDetails is Map<String, dynamic>
        ? rawDetails
        : rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : <String, dynamic>{};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _categoryColor(log['category']).withValues(alpha: 0.1),
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
                _detailRow(
                  'Timestamp',
                  _formatDate(log['created_at']?.toString()),
                ),
                _detailRow('Category', log['category']?.toString() ?? '-'),
                _detailRow('Severity', log['severity']?.toString() ?? '-'),
                _detailRow('Actor', log['actor_name']?.toString() ?? '-'),
                _detailRow('Actor Role', log['actor_role']?.toString() ?? '-'),
                _detailRow('Actor ID', log['actor_id']?.toString() ?? '-'),
                _detailRow(
                  'Target Type',
                  log['target_type']?.toString() ?? '-',
                ),
                _detailRow('Target', log['target_label']?.toString() ?? '-'),
                _detailRow('Target ID', log['target_id']?.toString() ?? '-'),
                if (details.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...details.entries.map(
                    (e) => _detailRow(e.key, e.value?.toString() ?? '-'),
                  ),
                ],
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
          'Page ${_currentPage + 1} of $_totalPages  ($_totalCount total events)',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _currentPage < _totalPages - 1
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

  Future<void> _handleLogout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ContentFadeRoute(page: const WorkerLoginScreen()),
      (route) => false,
    );
  }

  void _navigateToScreen(BuildContext context, String path) {
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
      case 'Forms':
        next = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
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
        next = FormBuilderScreen(
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
