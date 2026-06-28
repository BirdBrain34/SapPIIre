import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/dashboard_config_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/components/intake_chart_widgets.dart';
import 'package:sappiire/web/components/enhanced_chart_widgets.dart';
import 'package:sappiire/web/controllers/dashboard_controller.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/widgets/dashboard_config_dialog.dart';
import 'package:sappiire/web/widgets/dashboard_form_card.dart';
import 'package:sappiire/web/widgets/web_shell.dart';

class DashboardScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
    required this.onLogout,
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
  Map<String, int> get _staffWorkload => _controller.staffWorkload;
  Map<String, int> get _genderRatio => _controller.genderRatio;
  Map<String, int> get _ageBrackets => _controller.ageBrackets;
  Map<String, int> get _barangayVolume => _controller.barangayVolume;
  TextEditingController get _clientSearchController =>
      _controller.clientSearchController;
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
    _controller.setStaffId(widget.cswd_id);
    _analyticsService.setStaffId(widget.cswd_id);
    _loadDashboardData();
  }

  @override
  void dispose() {
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
          staffId: widget.cswd_id,
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
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: widget.onLogout,
      onNavigate: (path) => WebNavigator.go(
        context,
        path,
        cswdId: widget.cswd_id,
        role: widget.role,
        displayName: widget.displayName,
        onLogout: widget.onLogout,
      ),
      headerActions: _selectedFormId != 'all'
          ? [
              ElevatedButton.icon(
                onPressed: _openConfigDialog,
                icon: const Icon(Icons.settings),
                label: const Text('Configure Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.highlight,
                  foregroundColor: Colors.white,
                ),
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

              if (_selectedFormId == 'all')
                _buildAllFormsView()
              else
                ...[
                  // Date range selector
                  _buildDateRangeSelector(),
                  const SizedBox(height: 24),
                  // Chart widgets for selected form
                  _buildChartWidgetsSection(),
                ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Forms',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a form to view submission analytics',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // All Forms card
              GestureDetector(
                onTap: _selectAllForms,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 200, maxWidth: 280),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _selectedFormId == 'all'
                        ? AppColors.highlight.withValues(alpha: 0.95)
                        : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
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
                          blurRadius: 8,
                          offset: const Offset(0, 2),
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
                        widget.cswd_id,
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
        const Text(
          'Date Range',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTimeRangeButton('All Time', 'all'),
              _buildTimeRangeButton('This Year', 'year'),
              _buildTimeRangeButton('This Month', 'month'),
              _buildTimeRangeButton('This Week', 'week'),
              _buildTimeRangeButton('Today', 'today'),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTimeRange == 'custom'
                      ? AppColors.highlight
                      : AppColors.cardBg,
                  foregroundColor: _selectedTimeRange == 'custom'
                      ? Colors.white
                      : AppColors.textDark,
                ),
                child: const Text('Custom...'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRangeButton(String label, String value) {
    final isSelected = _selectedTimeRange == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton(
        onPressed: () => _onTimeRangeChanged(value),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? AppColors.highlight : AppColors.cardBg,
          foregroundColor:
              isSelected ? Colors.white : AppColors.textDark,
          elevation: isSelected ? 4 : 0,
        ),
        child: Text(label),
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
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_customize,
              size: 64,
              color: Colors.grey.shade300,
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
      default:
        return SimpleBarChart(
          title: config.fieldLabel,
          data: data,
        );
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
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.highlight.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 200,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [
                    Colors.grey.shade200,
                    Colors.grey.shade100,
                    Colors.grey.shade200,
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
                  color: Colors.grey.shade100,
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
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.dangerRed.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -2),
          ),
        ],
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
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.highlight.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, -2),
          ),
        ],
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
                    color: AppColors.highlight.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.data_exploration,
                    size: 36,
                    color: Colors.grey.shade300,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No data available for this period',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
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

                // Staff workload - Interactive with drill-down
                if (_staffWorkload.isNotEmpty)
                  SizedBox(
                    width: chartWidth,
                    child: InteractiveBarChart(
                      title: 'Staff Workload Distribution',
                      data: _staffWorkload,
                      primaryColor: AppColors.successGreen,
                      onDrillDown: (account) async {
                        return _analyticsService.fetchSubmissionsByFormTypeForWorker(
                          account,
                          timeRange: _selectedDateRange,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Demographics section header
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 16),
          child: Text(
            'Demographics & Planning',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
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
                      : Container(
                          padding: const EdgeInsets.all(24),
                          decoration: AppColors.cardDecoration(),
                          child: const Text('No gender data'),
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
                      : Container(
                          padding: const EdgeInsets.all(24),
                          decoration: AppColors.cardDecoration(),
                          child: const Text('No age data'),
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
        const Text(
          'Summary Metrics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
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
          const Text(
            'Client 360 View',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _clientSearchController,
            decoration: InputDecoration(
              hintText: 'Search clients by name...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (_) => _controller.searchClients(),
          ),
          if (_isSearchingClients) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ] else if (_clientSearchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _clientSearchResults.length,
                itemBuilder: (context, index) {
                  final client = _clientSearchResults[index];
                  return ListTile(
                    dense: true,
                    title: Text(client['name'] ?? 'Unknown'),
                    onTap: () =>
                        _controller.selectClient(client, timeRange: _selectedDateRange),
                  );
                },
              ),
            ),
          ],
          if (_selectedClientId != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Client: $_selectedClientName',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            if (_selectedClientFlags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _selectedClientFlags.entries
                    .map(
                      (entry) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.dangerRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.dangerRed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (_isLoadingClientHistory) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ] else if (_selectedClientHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Submission History',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ..._selectedClientHistory.take(5).map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item['form_type']?.toString() ?? 'Unknown',
                            style: const TextStyle(fontSize: 12),
                          ),
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
}