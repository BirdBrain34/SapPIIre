import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/dashboard_config_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/components/intake_chart_widgets.dart';
import 'package:sappiire/web/components/enhanced_chart_widgets.dart';
import 'package:sappiire/web/components/staff_submission_activity.dart';
import 'package:sappiire/web/controllers/dashboard_controller.dart';
import 'package:sappiire/web/utils/debouncer.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/widgets/dashboard_config_dialog.dart';
import 'package:sappiire/web/widgets/dashboard_form_card.dart';
import 'package:sappiire/web/widgets/dashboard_retention_summary.dart';
import 'package:sappiire/web/widgets/web_header_button.dart';
import 'package:sappiire/web/widgets/web_shell.dart';

class DashboardScreen extends StatefulWidget {
  final String cswdId;
  final String role;
  final String displayName;

  const DashboardScreen({
    super.key,
    required this.cswdId,
    required this.role,
    this.displayName = '',
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final _controller = DashboardController();
  final _analyticsService = DashboardAnalyticsService();
  final _templateService = FormTemplateService();
  final _configService = DashboardConfigService();

  // Form and template data
  List<FormTemplate> _templates = [];
  Map<String, int> _submissionCounts = {};
  Map<String, String> _cardColors = {};

  // Selected form and date range
  String _selectedFormId = 'all';
  String _selectedFormName = 'All Forms';
  DateTimeRange? _selectedDateRange;
  String _selectedTimeRange = 'all';

  // Widget configuration state
  List<DashboardWidgetConfig> _widgetConfigs = [];
  bool _isLoadingConfigs = false;
  final Map<String, Future<Map<String, int>>> _distributionFutures = {};
  int _refreshToken = 0;

  // All Forms view state (existing analytics)
  int _activeFormCount = 0;
  int _staffAccountCount = 0;
  Map<String, int> _monthlyTrend = {};

  Map<String, int> get _countsByFormType => _controller.countsByFormType;
  int get _totalCount => _controller.totalCount;
  // ignore: unused_element
  Map<String, int> get _staffWorkload => _controller.staffWorkload;
  Map<String, int> get _genderRatio => _controller.genderRatio;
  Map<String, int> get _ageBrackets => _controller.ageBrackets;
  Map<String, int> get _barangayVolume => _controller.barangayVolume;
  TextEditingController get _clientSearchController =>
      _controller.clientSearchController;
  final Debouncer _clientSearchDebouncer = Debouncer.search();
  bool get _isSearchingClients => _controller.isSearchingClients;
  bool get _isLoadingClientHistory => _controller.isLoadingClientHistory;
  List<Map<String, String>> get _clientSearchResults =>
      _controller.clientSearchResults;
  String? get _selectedClientId => _controller.selectedClientId;
  String get _selectedClientName => _controller.selectedClientName;
  List<Map<String, dynamic>> get _selectedClientHistory =>
      _controller.selectedClientHistory;
  Map<String, String> get _selectedClientFlags =>
      _controller.selectedClientFlags;

  @override
  void initState() {
    super.initState();
    _controller.setStaffId(widget.cswdId);
    _analyticsService.setStaffId(widget.cswdId);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _clientSearchDebouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    await _loadTemplates();
    await _refreshFormCards();
    if (mounted && _selectedFormId != 'all') {
      await _loadWidgetConfigs();
    } else if (mounted) {
      await _refreshAllFormsData();
    }
  }

  Future<void> _loadTemplates() async {
    final templates = await _templateService.fetchActiveTemplates(
      forceRefresh: true,
    );

    if (!mounted) return;

    setState(() {
      _templates = templates;
      _activeFormCount = templates.length;
    });
  }

  Future<void> _refreshFormCards() async {
    if (_templates.isEmpty) return;

    try {
      final counts = <String, int>{};
      final colors = <String, String>{};

      for (final template in _templates) {
        final count = await _analyticsService.fetchSubmissionCount(
          formType: template.formName,
          timeRange: _selectedDateRange,
        );
        counts[template.templateId] = count;

        final color = await _analyticsService.fetchCardSettings(
          template.templateId,
        );
        colors[template.templateId] = color;
      }

      if (mounted) {
        setState(() {
          _submissionCounts = counts;
          _cardColors = colors;
        });
      }
    } catch (e) {
      debugPrint('[DashboardScreen/_refreshFormCards] Error: $e');
    }
  }

  Future<void> _loadWidgetConfigs() async {
    setState(() => _isLoadingConfigs = true);

    _distributionFutures.clear();

    try {
      final configs = await _configService.fetchConfig(
        _selectedFormId,
      );

      if (!mounted) return;

      setState(() {
        _widgetConfigs = configs;
        _distributionFutures.clear();
        _isLoadingConfigs = false;
      });

      // Trigger data fetch for each widget
      if (configs.isNotEmpty) {
        _fetchAllChartData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingConfigs = false);
      }
      debugPrint('[DashboardScreen/_loadWidgetConfigs] Error: $e');
    }
  }

  void _fetchAllChartData() {
    for (final config in _widgetConfigs) {
      _fetchChartData(config);
    }
  }

  void _fetchChartData(DashboardWidgetConfig config) {
    final cacheKey = _getCacheKey(config);
    if (_distributionFutures.containsKey(cacheKey)) {
      return; // Already loading or loaded
    }
    
    final future = _analyticsService.fetchFieldDistribution(
      formType: _selectedFormName,
      fieldName: config.fieldName,
      topN: 15,
      timeRange: _selectedDateRange,
    );

    _distributionFutures[cacheKey] = future;
  }

  String _getCacheKey(DashboardWidgetConfig config) {
    return '$_selectedFormId:${config.fieldName}:${_selectedDateRange?.start.toIso8601String() ?? 'null'}:${_selectedDateRange?.end.toIso8601String() ?? 'null'}';
  }


  DateTimeRange? _getSelectedDateRange() {
    final now = DateTime.now();
    switch (_selectedTimeRange) {
      case 'today':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case 'week':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
      case 'year':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: now,
        );
      default:
        return null;
    }
  }

  Future<void> _onTimeRangeChanged(String timeRange) async {
    setState(() => _selectedTimeRange = timeRange);
    _selectedDateRange = _getSelectedDateRange();

    await _refreshFormCards();
    _distributionFutures.clear();
    if (_selectedFormId != 'all') {
      await _loadWidgetConfigs();
    } else {
      await _refreshAllFormsData();
    }
  }

  Future<void> _refreshAllFormsData() async {
    final token = ++_refreshToken;
    _analyticsService.clearDecryptedCache();

    if (mounted) {
      setState(() {});
    }

    final timeRange = _selectedDateRange;

    await Future.wait([
      _controller.loadSummary(timeRange: timeRange),
      _controller.loadOperationalInsights(timeRange: timeRange),
      _controller.loadPlanningInsights('All', timeRange: timeRange),
    ]);

    if (!mounted || token != _refreshToken) return;

    final results = await Future.wait([
      _analyticsService.fetchStaffAccountCount(),
      _analyticsService.fetchMonthlyTrend('All', timeRange: timeRange),
    ]);
    await _analyticsService.fetchUniqueClientCount(
      timeRange: timeRange,
    );

    if (!mounted || token != _refreshToken) return;

    setState(() {
      _staffAccountCount = results[0] as int;
      _monthlyTrend = results[1] as Map<String, int>;
    });
  }

  Future<void> _selectForm(String templateId, String formName) async {
    setState(() {
      _selectedFormId = templateId;
      _selectedFormName = formName;
      _widgetConfigs = [];
      _distributionFutures.clear();
    });

    await _loadWidgetConfigs();
  }

  Future<void> _selectAllForms() async {
    setState(() {
      _selectedFormId = 'all';
      _selectedFormName = 'All Forms';
      _widgetConfigs = [];
    });

    await _refreshAllFormsData();
  }

  Future<void> _openConfigDialog() async {
    if (_templates.isEmpty) return;

    try {
      final selectedTemplate = _templates
          .firstWhere((t) => t.templateId == _selectedFormId);

      await showDialog(
        context: context,
        builder: (context) => DashboardConfigDialog(
          templateId: _selectedFormId,
          template: selectedTemplate,
          initialConfigs: _widgetConfigs,
          staffId: widget.cswdId,
          onSave: () async {
            await _loadWidgetConfigs();
          },
        ),
      );
    } catch (e) {
      debugPrint('[DashboardScreen/_openConfigDialog] Error: $e');
    }
  }

  /// Builds a map of form display name → hex color for the color-synced pie chart.
  /// Maps from template form names to their card color settings.
  Map<String, String> _buildFormColorsMap() {
    final colorMap = <String, String>{};
    for (final template in _templates) {
      final color = _cardColors[template.templateId] ?? '#4C8BF5';
      colorMap[template.formName] = color;
    }
    return colorMap;
  }

  /// Returns the number of grid columns based on screen width.
  int _gridColumns(double width) {
    if (width < 700) return 1;
    if (width < 1100) return 2;
    return 2;
  }

  /// Section header shared across the dashboard: leading icon + bold title,
  /// with an optional muted subtitle. Matches the pattern used on the polished
  /// Manage Staff / Applicants screens so headings stay visually consistent.
  Widget _sectionHeader(IconData icon, String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textDark, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Card-shaped placeholder shown in place of a chart when its dataset is
  /// empty. Keeps a titled card + muted centered message so gaps read as
  /// intentional empty states rather than missing widgets.
  Widget _buildInlineEmptyCard(String title, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.data_exploration,
                    size: 32,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle =
        _selectedFormId == 'all' ? 'Dashboard' : _selectedFormName;
    final pageSubtitle = _selectedFormId == 'all'
        ? 'Agency-wide analytics and insights'
        : 'Form-specific submission analytics';

    return WebShell(
      activePath: '/dashboard',
      pageTitle: pageTitle,
      pageSubtitle: pageSubtitle,
      role: widget.role,
      cswdId: widget.cswdId,
      displayName: widget.displayName,
      onLogout: () => WebSession.logout(context),
      onNavigate: (path) => WebNavigator.go(
        context,
        path,
        cswdId: widget.cswdId,
        role: widget.role,
        displayName: widget.displayName,
      ),
      headerActions: _selectedFormId != 'all'
          ? [
              WebHeaderButton(
                'Configure Dashboard',
                Icons.settings,
                onPressed: _openConfigDialog,
              ),
            ]
          : null,
      child: SingleChildScrollView(
        child: Container(
          color: AppColors.pageBg,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Form cards section
              _buildFormCardsSection(),
              const SizedBox(height: 32),

              // Animate the swap between the agency-wide and per-form views.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey(_selectedFormId),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedFormId == 'all')
                      _buildAllFormsView()
                    else ...[
                      // Date range selector
                      _buildDateRangeSelector(),
                      const SizedBox(height: 24),
                      // Chart widgets for selected form
                      _buildChartWidgetsSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _sectionHeader(
            Icons.dashboard_outlined,
            'Forms',
            subtitle: 'Select a form to view submission analytics',
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // All Forms card
              GestureDetector(
                onTap: _selectAllForms,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  constraints:
                      const BoxConstraints(minWidth: 200, maxWidth: 280),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _selectedFormId == 'all'
                        ? AppColors.highlight.withValues(alpha: 0.95)
                        : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selectedFormId == 'all'
                          ? AppColors.highlight
                          : AppColors.cardBorder,
                      width: _selectedFormId == 'all' ? 2 : 1,
                    ),
                    boxShadow: [
                      if (_selectedFormId == 'all')
                        BoxShadow(
                          color: AppColors.highlight.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      else
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'All Forms',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _selectedFormId == 'all'
                              ? Colors.white
                              : AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _totalCount.toString(),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: _selectedFormId == 'all'
                                  ? Colors.white
                                  : AppColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'submissions',
                            style: TextStyle(
                              fontSize: 12,
                              color: _selectedFormId == 'all'
                                  ? Colors.white70
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Individual form cards
              ..._templates.map(
                (template) => Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: DashboardFormCard(
                    formName: template.formName,
                    submissionCount:
                        _submissionCounts[template.templateId] ?? 0,
                    cardColor:
                        _cardColors[template.templateId] ?? '#4C8BF5',
                    isSelected: _selectedFormId == template.templateId,
                    onTap: () =>
                        _selectForm(template.templateId, template.formName),
                    onColorChanged: (color) async {
                      await _analyticsService.upsertCardSettings(
                        template.templateId,
                        color,
                        widget.cswdId,
                      );
                      setState(() {
                        _cardColors[template.templateId] = color;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'DATE RANGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTimeRangePill('All Time', 'all'),
              _buildTimeRangePill('This Year', 'year'),
              _buildTimeRangePill('This Month', 'month'),
              _buildTimeRangePill('This Week', 'week'),
              _buildTimeRangePill('Today', 'today'),
              _buildTimeRangePill(
                'Custom...',
                'custom',
                icon: Icons.tune,
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDateRange = picked);
                    _selectedTimeRange = 'custom';
                    await _refreshFormCards();
                    if (_selectedFormId != 'all') {
                      _distributionFutures.clear();
                      await _loadWidgetConfigs();
                    } else {
                      await _refreshAllFormsData();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A single date-range pill. Selected pills use the highlight accent; the
  /// rest sit on the page background with a hairline border (system pill look).
  Widget _buildTimeRangePill(
    String label,
    String value, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedTimeRange == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap ?? () => _onTimeRangeChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color:
                  isSelected ? AppColors.highlight : AppColors.pageBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? AppColors.highlight
                    : AppColors.cardBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color:
                        isSelected ? Colors.white : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        isSelected ? Colors.white : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartWidgetsSection() {
    if (_isLoadingConfigs) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(40),
        child: const CircularProgressIndicator(),
      );
    }

    if (_widgetConfigs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
        decoration: AppColors.cardDecoration(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.highlight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.dashboard_customize,
                size: 40,
                color: AppColors.highlight,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Dashboard Not Configured',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Configure Dashboard" to select fields and chart types',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openConfigDialog,
              icon: const Icon(Icons.settings),
              label: const Text('Configure Dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.highlight,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Responsive grid layout for chart widgets
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth);
        final itemWidth = columns > 1
            ? ((constraints.maxWidth - 16) / columns).clamp(200.0, double.infinity)
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _widgetConfigs
              .map((config) => SizedBox(
                    width: itemWidth,
                    child: _buildChartWidget(config),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildChartWidget(DashboardWidgetConfig config) {
    final cacheKey = _getCacheKey(config);

    return FutureBuilder<Map<String, int>>(
      future: _distributionFutures[cacheKey] ??= _distributionFutures.putIfAbsent(
        cacheKey,
        () => _analyticsService.fetchFieldDistribution(
          formType: _selectedFormName,
          fieldName: config.fieldName,
          topN: 15,
          timeRange: _selectedDateRange,
        ),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildChartSkeleton(config);
        }

        if (snapshot.hasError) {
          return _buildChartError(config, snapshot.error.toString());
        }

        final data = snapshot.data ?? {};

        if (data.isEmpty) {
          return _buildChartEmpty(config);
        }

        return _buildChartForType(config, data);
      },
    );
  }

  Widget _buildChartForType(DashboardWidgetConfig config, Map<String, int> data) {
    switch (config.chartType) {
      case 'pie':
        return SimplePieChart(
          title: config.fieldLabel,
          data: data,
        );
      case 'line':
        return LineChart(
          title: config.fieldLabel,
          data: data,
        );
      case 'hbar':
        return SimpleBarChart(
          title: config.fieldLabel,
          data: data,
        );
      case 'bar':
        return SimpleVerticalBarChart(
          title: config.fieldLabel,
          data: data,
        );
      case 'histogram':
        return _buildHistogramWidget(config, data);
      default:
        return SimpleBarChart(
          title: config.fieldLabel,
          data: data,
        );
    }
  }

  Widget _buildHistogramWidget(DashboardWidgetConfig config, Map<String, int> data) {
    // Compute stats from the raw data values
    // For histogram, data keys are bucket labels and values are counts
    // We compute average/median/min/max from the original field values
    // by re-fetching with isNumeric=true
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchHistogramStats(config),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};
        return HistogramChart(
          title: config.fieldLabel,
          buckets: data,
          average: stats['average'] as double?,
          median: stats['median'] as double?,
          minVal: stats['min'] as double?,
          maxVal: stats['max'] as double?,
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchHistogramStats(DashboardWidgetConfig config) async {
    try {
      // Fetch raw numeric values for stat computation
      final rawData = await _analyticsService.fetchFieldDistribution(
        formType: _selectedFormName,
        fieldName: config.fieldName,
        isNumeric: true,
        topN: 50,
        timeRange: _selectedDateRange,
      );
      
      // Parse bucket labels to extract numeric values for stats
      final values = <double>[];
      for (final entry in rawData.entries) {
        // Try to extract a representative value from bucket label
        final numVal = double.tryParse(entry.key.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (numVal != null) {
          // Repeat the value by its count for weighted stats
          for (int i = 0; i < entry.value; i++) {
            values.add(numVal);
          }
        }
      }
      
      if (values.isEmpty) return {};
      
      values.sort();
      final sum = values.fold<double>(0, (a, b) => a + b);
      final avg = sum / values.length;
      final median = values.length.isOdd
          ? values[values.length ~/ 2]
          : (values[values.length ~/ 2 - 1] + values[values.length ~/ 2]) / 2;
      
      return {
        'average': avg,
        'median': median,
        'min': values.first,
        'max': values.last,
      };
    } catch (e) {
      debugPrint('[DashboardScreen/_fetchHistogramStats] Error: $e');
      return {};
    }
  }

  Widget _buildChartSkeleton(DashboardWidgetConfig config) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        height: 220,
        padding: const EdgeInsets.all(24),
        decoration: AppColors.cardDecoration(elevation: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 200,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [
                    AppColors.cardBorder,
                    AppColors.pageBg,
                    AppColors.cardBorder,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartError(DashboardWidgetConfig config, String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(elevation: 2).copyWith(
        border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.fieldLabel,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 36,
                    color: AppColors.dangerRed.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Error loading chart',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.dangerRed,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartEmpty(DashboardWidgetConfig config) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(elevation: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.fieldLabel,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.data_exploration,
                    size: 36,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No data available for this period',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAllFormsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date range selector
        _buildDateRangeSelector(),
        const SizedBox(height: 24),
        // Summary metrics
        _buildSummaryMetrics(),
        const SizedBox(height: 32),

        // Data-retention summary (admin-only): how many records have gone
        // stale, with a jump into the full retention screen.
        if (widget.role == 'admin' || widget.role == 'superadmin') ...[
          DashboardRetentionSummary(
            refreshToken: _refreshToken,
            onReview: () => WebNavigator.go(
              context,
              'DataRetention',
              cswdId: widget.cswdId,
              role: widget.role,
              displayName: widget.displayName,
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Responsive row for charts
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final chartWidth = wide
                ? ((constraints.maxWidth - 16) / 2).clamp(200.0, double.infinity)
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // Submissions by form type - Enhanced with color syncing
                if (_countsByFormType.isNotEmpty)
                  SizedBox(
                    width: chartWidth,
                    child: ColorSyncPieChart(
                      title: 'Submissions by Form Type',
                      data: _countsByFormType,
                      formColors: _buildFormColorsMap(),
                    ),
                  ),

                // Staff Submission Activity - 3-Level Drill-Down
                SizedBox(
                  width: chartWidth,
                  child: StaffSubmissionActivity(
                    analyticsService: _analyticsService,
                    timeRange: _selectedDateRange,
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Demographics section header
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: _sectionHeader(
            Icons.insights_outlined,
            'Demographics & Planning',
          ),
        ),

        // Gender ratio and age brackets - responsive
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final itemWidth = wide
                ? ((constraints.maxWidth - 16) / 2).clamp(200.0, double.infinity)
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _genderRatio.isNotEmpty
                      ? SimplePieChart(
                          title: 'Gender Distribution',
                          data: _genderRatio,
                        )
                      : _buildInlineEmptyCard(
                          'Gender Distribution',
                          'No gender data available',
                        ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ageBrackets.isNotEmpty
                      ? SimpleBarChart(
                          title: 'Age Brackets',
                          data: _ageBrackets,
                          primaryColor: AppColors.highlight,
                        )
                      : _buildInlineEmptyCard(
                          'Age Brackets',
                          'No age data available',
                        ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Barangay volume
        if (_barangayVolume.isNotEmpty)
          SimpleBarChart(
            title: 'Top Barangays by Volume',
            data: _barangayVolume,
            primaryColor: AppColors.warningAmber,
          ),

        const SizedBox(height: 24),

        // Monthly submission trend
        if (_monthlyTrend.isNotEmpty)
          LineChart(
            title: 'Monthly Submission Trend',
            data: _monthlyTrend,
          ),

        const SizedBox(height: 32),

        // Client 360 section
        _buildClient360Section(),
      ],
    );
  }

  Widget _buildSummaryMetrics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.leaderboard_outlined, 'Summary Metrics'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            // Use a Wrap with fixed widths to prevent overflow instead of Row with Expanded
            final itemWidth = wide
                ? ((constraints.maxWidth - 36) / 4).clamp(120.0, double.infinity)
                : ((constraints.maxWidth - 12) / 2).clamp(120.0, double.infinity);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: MetricCard(
                    label: 'Total Submissions',
                    value: _totalCount.toString(),
                    icon: Icons.assignment,
                    color: AppColors.highlight,
                    expand: false,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: MetricCard(
                    label: 'Active Forms',
                    value: _activeFormCount.toString(),
                    icon: Icons.description,
                    color: AppColors.successGreen,
                    expand: false,
                  ),
                ),
                if (wide) ...[
                  SizedBox(
                    width: itemWidth,
                    child: MetricCard(
                      label: 'Staff Accounts',
                      value: _staffAccountCount.toString(),
                      icon: Icons.people,
                      color: AppColors.warningAmber,
                      expand: false,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        // Show remaining cards on non-wide screens
        if (MediaQuery.of(context).size.width < 900)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 60) / 2,
                  child: MetricCard(
                    label: 'Staff Accounts',
                    value: _staffAccountCount.toString(),
                    icon: Icons.people,
                    color: AppColors.warningAmber,
                    expand: false,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildClient360Section() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.person_search_outlined,
            'Client 360 View',
            subtitle: 'Look up a client to review their submission history',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _clientSearchController,
            style: const TextStyle(fontSize: 14, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'Search clients by name...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.pageBg,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.highlight),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            // Debounced: client search now decrypts server-side, so one call
            // per keystroke would mean one bulk decrypt per keystroke.
            onChanged: (_) => _clientSearchDebouncer.run(() {
              if (!mounted) return;
              _controller.searchClients();
            }),
            onSubmitted: (_) => _clientSearchDebouncer.flush(() {
              if (!mounted) return;
              _controller.searchClients();
            }),
          ),
          if (_isSearchingClients) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ] else if (_clientSearchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _clientSearchResults.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.cardBorder),
                itemBuilder: (context, index) {
                  final client = _clientSearchResults[index];
                  final name = client['name'] ?? 'Unknown';
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _controller.selectClient(
                        client,
                        timeRange: _selectedDateRange,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            _clientAvatar(name, 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.textMuted,
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
          if (_selectedClientId != null) ...[
            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.cardBorder),
            const SizedBox(height: 16),
            Row(
              children: [
                _clientAvatar(_selectedClientName, 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedClientName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_selectedClientFlags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedClientFlags.entries
                    .map((entry) => _flagBadge(entry.value))
                    .toList(),
              ),
            ],
            if (_isLoadingClientHistory) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ] else if (_selectedClientHistory.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'SUBMISSION HISTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              ..._selectedClientHistory.take(5).map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.pageBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.description_outlined,
                                  size: 16,
                                  color: AppColors.highlight,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item['form_type']?.toString() ?? 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item['intake_reference']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }

  /// Circular initials avatar used in the Client 360 search results and header.
  Widget _clientAvatar(String name, double size) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.highlight.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
          color: AppColors.highlight,
        ),
      ),
    );
  }

  /// Tinted pill badge for client eligibility / frequency flags.
  Widget _flagBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.dangerRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.dangerRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.dangerRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
