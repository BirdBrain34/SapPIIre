import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';

/// ============================================================================
/// Staff Submission Activity — 3-Level Drill-Down Widget
///
/// Level 1: Staff overview with total submission counts
/// Level 2: Form type breakdown for a selected staff member
/// Level 3: Individual submission records for a selected form type
///
/// Navigation is via breadcrumbs at the top of the widget.
/// ============================================================================
class StaffSubmissionActivity extends StatefulWidget {
  final DashboardAnalyticsService analyticsService;
  final DateTimeRange? timeRange;

  const StaffSubmissionActivity({
    super.key,
    required this.analyticsService,
    this.timeRange,
  });

  @override
  State<StaffSubmissionActivity> createState() =>
      _StaffSubmissionActivityState();
}

class _StaffSubmissionActivityState extends State<StaffSubmissionActivity> {
  final _analytics = DashboardAnalyticsService();

  // Level state
  int _currentLevel = 1; // 1, 2, or 3
  StaffSummary? _selectedStaff;
  String _selectedFormType = '';

  // Level 1 data
  List<StaffSummary> _staffSummaries = [];

  // Level 2 data
  Map<String, int> _formTypeBreakdown = {};

  // Level 3 data
  List<Map<String, dynamic>> _submissionRecords = [];

  // Loading states
  bool _isLoadingLevel1 = true;
  bool _isLoadingLevel2 = false;
  bool _isLoadingLevel3 = false;

  @override
  void initState() {
    super.initState();
    _loadLevel1();
  }

  @override
  void didUpdateWidget(StaffSubmissionActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeRange != widget.timeRange) {
      _resetToLevel1();
    }
  }

  void _resetToLevel1() {
    setState(() {
      _currentLevel = 1;
      _selectedStaff = null;
      _selectedFormType = '';
      _formTypeBreakdown = {};
      _submissionRecords = [];
      _isLoadingLevel1 = true;
    });
    _loadLevel1();
  }

  Future<void> _loadLevel1() async {
    setState(() => _isLoadingLevel1 = true);
    try {
      final data = await _analytics.fetchStaffSubmissionCounts(
        timeRange: widget.timeRange,
      );
      if (mounted) {
        setState(() {
          _staffSummaries = data;
          _isLoadingLevel1 = false;
        });
      }
    } catch (e) {
      debugPrint('[StaffSubmissionActivity/_loadLevel1] Error: $e');
      if (mounted) setState(() => _isLoadingLevel1 = false);
    }
  }

  Future<void> _navigateToLevel2(StaffSummary staff) async {
    setState(() {
      _currentLevel = 2;
      _selectedStaff = staff;
      _selectedFormType = '';
      _isLoadingLevel2 = true;
      _formTypeBreakdown = {};
      _submissionRecords = [];
    });

    try {
      final data = await _analytics.fetchStaffFormTypeBreakdown(
        staff.staffId,
        timeRange: widget.timeRange,
      );
      if (mounted) {
        setState(() {
          _formTypeBreakdown = data;
          _isLoadingLevel2 = false;
        });
      }
    } catch (e) {
      debugPrint('[StaffSubmissionActivity/_navigateToLevel2] Error: $e');
      if (mounted) setState(() => _isLoadingLevel2 = false);
    }
  }

  Future<void> _navigateToLevel3(String formType) async {
    if (_selectedStaff == null) return;

    setState(() {
      _currentLevel = 3;
      _selectedFormType = formType;
      _isLoadingLevel3 = true;
      _submissionRecords = [];
    });

    try {
      final data = await _analytics.fetchStaffFormSubmissions(
        _selectedStaff!.staffId,
        formType,
        timeRange: widget.timeRange,
      );
      if (mounted) {
        setState(() {
          _submissionRecords = data;
          _isLoadingLevel3 = false;
        });
      }
    } catch (e) {
      debugPrint('[StaffSubmissionActivity/_navigateToLevel3] Error: $e');
      if (mounted) setState(() => _isLoadingLevel3 = false);
    }
  }

  void _navigateToBreadcrumb(int level) {
    if (level == 1) {
      setState(() {
        _currentLevel = 1;
        _selectedStaff = null;
        _selectedFormType = '';
        _formTypeBreakdown = {};
        _submissionRecords = [];
      });
    } else if (level == 2) {
      setState(() {
        _currentLevel = 2;
        _selectedFormType = '';
        _submissionRecords = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppColors.cardDecoration(elevation: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with title
          _buildHeader(),
          // Breadcrumb navigation
          _buildBreadcrumbs(),
          // Content area
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Staff Submission Activity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          if (_currentLevel == 1 && _staffSummaries.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.highlight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_staffSummaries.length} staff',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.highlight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final staffName = _selectedStaff?.displayName ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _breadcrumbItem(
            'Staff Submission Activity',
            _currentLevel > 1,
            () => _navigateToBreadcrumb(1),
          ),
          if (_currentLevel >= 2) ...[
            _breadcrumbSeparator(),
            _breadcrumbItem(
              staffName,
              _currentLevel > 2,
              () => _navigateToBreadcrumb(2),
            ),
          ],
          if (_currentLevel >= 3) ...[
            _breadcrumbSeparator(),
            _breadcrumbItem(
              _selectedFormType,
              false,
              null,
              isActive: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _breadcrumbItem(
    String label,
    bool isClickable,
    VoidCallback? onTap, {
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: isClickable ? onTap : null,
      child: MouseRegion(
        cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.highlight.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? AppColors.highlight
                  : isClickable
                      ? AppColors.highlight.withValues(alpha: 0.8)
                      : AppColors.textMuted,
              decoration:
                  isClickable ? TextDecoration.underline : TextDecoration.none,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _breadcrumbSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.chevron_right,
        size: 14,
        color: AppColors.textMuted.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentLevel) {
      case 1:
        return _buildLevel1();
      case 2:
        return _buildLevel2();
      case 3:
        return _buildLevel3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ============================================================================
  // Level 1: Staff Overview
  // ============================================================================
  Widget _buildLevel1() {
    if (_isLoadingLevel1) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_staffSummaries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 36, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text(
                'No staff submission data available',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxVal = _staffSummaries
        .map((s) => s.submissionCount)
        .reduce((a, b) => a > b ? a : b);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (_staffSummaries.length * 52.0 + 16).clamp(100.0, 600.0),
        minHeight: 100,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: _staffSummaries.length,
        itemBuilder: (context, index) {
          final summary = _staffSummaries[index];
          final pct = maxVal > 0 ? summary.submissionCount / maxVal : 0.0;
          final isTop3 = index < 3;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => _navigateToLevel2(summary),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0, end: pct),
                  builder: (context, animatedPct, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                children: [
                                  // Rank badge for top 3
                                  if (isTop3)
                                    Container(
                                      width: 20,
                                      height: 20,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: _rankColor(index)
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _rankColor(index),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 28),
                                  Flexible(
                                    child: Text(
                                      summary.displayName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textDark,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.highlight.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${summary.submissionCount}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.highlight,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: animatedPct,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.highlight.withValues(alpha: 0.7),
                                        AppColors.highlight,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _rankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFA500); // Gold
      case 1:
        return const Color(0xFF9E9E9E); // Silver
      case 2:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return AppColors.highlight;
    }
  }

  // ============================================================================
  // Level 2: Staff Detail — Form Type Breakdown
  // ============================================================================
  Widget _buildLevel2() {
    if (_isLoadingLevel2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_formTypeBreakdown.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.description_outlined,
                  size: 36, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text(
                'No submissions found for this staff member',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxVal = _formTypeBreakdown.values
        .reduce((a, b) => a > b ? a : b);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (_formTypeBreakdown.length * 52.0 + 16).clamp(100.0, 500.0),
        minHeight: 100,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: _formTypeBreakdown.length,
        itemBuilder: (context, index) {
          final entry = _formTypeBreakdown.entries.elementAt(index);
          final pct = maxVal > 0 ? entry.value / maxVal : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => _navigateToLevel3(entry.key),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.successGreen,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${entry.value}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: AppColors.textMuted.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: pct,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.successGreen.withValues(alpha: 0.7),
                                    AppColors.successGreen,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // Level 3: Form Detail — Individual Submission Records
  // ============================================================================
  Widget _buildLevel3() {
    if (_isLoadingLevel3) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_submissionRecords.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.list_alt, size: 36, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text(
                'No submission records found',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.highlight.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.highlight),
              const SizedBox(width: 8),
              Text(
                '${_submissionRecords.length} submission(s) found for $_selectedFormType',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.highlight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.textDark.withValues(alpha: 0.04),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Submitter',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Date & Time Submitted',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Reference Number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table rows
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (_submissionRecords.length * 44.0 + 16).clamp(100.0, 500.0),
            minHeight: 44,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: _submissionRecords.length,
            itemBuilder: (context, index) {
              final record = _submissionRecords[index];
              final isEven = index.isEven;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isEven ? Colors.white : Colors.grey.shade50,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.cardBorder.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        record['submitter']?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatDateTime(record['submitted_at']?.toString() ?? ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        record['reference_number']?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.highlight,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final date =
          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (e) {
      return isoString;
    }
  }
}