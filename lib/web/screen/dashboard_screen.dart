import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/dashboard_config_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/components/intake_chart_widgets.dart';
import 'package:sappiire/web/controllers/dashboard_controller.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
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

  List<FormTemplate> _templates = [];
  String _selectedFormType = 'All';
  String _selectedTimeRange = 'all';
  String? _selectedTemplateId;
  List<DashboardWidgetConfig> _widgetConfigs = [];
  final Map<String, Future<Map<String, int>>> _distributionFutures = {};
  bool _isLoadingWidgetConfigs = false;
  bool _isLoadingOverview = true;
  int _activeFormCount = 0;
  int _staffAccountCount = 0;
  int _uniqueClientCount = 0;
  Map<String, int> _workerAnalytics = {};
  int _refreshToken = 0;
  int _selectionToken = 0;

  Map<String, int> get _countsByFormType => _controller.countsByFormType;
  int get _totalCount => _controller.totalCount;
  List<String> get _availableFormTypes => _controller.availableFormTypes;
  bool get _isLoadingInsights => _controller.isLoadingInsights;
  Map<String, int> get _staffWorkload => _controller.staffWorkload;
  Map<String, int> get _genderRatio => _controller.genderRatio;
  Map<String, int> get _ageBrackets => _controller.ageBrackets;
  Map<String, int> get _barangayVolume => _controller.barangayVolume;
  String get _planningScopeFormType => _controller.planningScopeFormType;
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
  Map<String, String> get _selectedClientFlags => _controller.selectedClientFlags;

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
    await _refreshDashboardData();
  }

  Future<void> _loadTemplates() async {
    final templates = await _templateService.fetchActiveTemplates(
      forceRefresh: true,
    );

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _activeFormCount = templates.length;
      _controller.availableFormTypes = templates
          .map((template) => template.formName)
          .toSet()
          .toList()
        ..sort();
      if (_selectedFormType != 'All') {
        _selectedTemplateId = _resolveTemplateId(_selectedFormType);
      }
      _isLoadingOverview = false;
    });
  }

  DateTimeRange? _getTimeRange() {
    final now = DateTime.now();
    switch (_selectedTimeRange) {
      case 'daily':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case 'weekly':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case 'monthly':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'yearly':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      default:
        return null;
    }
  }

  String _timeRangeLabel() {
    switch (_selectedTimeRange) {
      case 'daily':
        return 'Today';
      case 'weekly':
        return 'This Week';
      case 'monthly':
        return 'This Month';
      case 'yearly':
        return 'This Year';
      default:
        return 'All Time';
    }
  }

  Future<void> _refreshDashboardData() async {
    final token = ++_refreshToken;
    final timeRange = _getTimeRange();
    final formType = _selectedFormType;

    _analyticsService.clearDecryptedCache();

    if (mounted) {
      setState(() => _isLoadingOverview = true);
    }

    await Future.wait([
      _controller.loadSummary(timeRange: timeRange),
      _controller.loadOperationalInsights(timeRange: timeRange),
      _controller.loadPlanningInsights(
        formType,
        timeRange: timeRange,
      ),
    ]);

    if (!mounted || token != _refreshToken) return;

    final workerAnalytics = await _analyticsService.fetchSubmissionsByWorker(
      formType: formType == 'All' ? null : formType,
      timeRange: timeRange,
    );
    final staffCount = await _analyticsService.fetchStaffAccountCount();
    final uniqueClients = await _analyticsService.fetchUniqueClientCount(
      timeRange: timeRange,
    );

    if (!mounted || token != _refreshToken) return;

    setState(() {
      _workerAnalytics = workerAnalytics;
      _staffAccountCount = staffCount;
      _uniqueClientCount = uniqueClients;
      _activeFormCount = _templates.length;
      _isLoadingOverview = false;
    });

    if (_selectedClientId != null) {
      await _controller.selectClient(
        {
          'user_id': _selectedClientId!,
          'name': _selectedClientName,
        },
        timeRange: timeRange,
      );
    }
  }

  String? _resolveTemplateId(String formType) {
    for (final template in _templates) {
      if (template.formName == formType) {
        return template.templateId;
      }
    }
    return null;
  }

  Future<void> _selectFormType(String formType) async {
    final token = ++_selectionToken;
    final templateId = formType == 'All' ? null : _resolveTemplateId(formType);

    setState(() {
      _selectedFormType = formType;
      _selectedTemplateId = templateId;
      _widgetConfigs = [];
      _distributionFutures.clear();
      _isLoadingWidgetConfigs = formType != 'All';
    });

    await _refreshDashboardData();
    if (!mounted || token != _selectionToken) return;

    if (formType == 'All') {
      setState(() => _isLoadingWidgetConfigs = false);
      return;
    }

    if (_selectedTemplateId == null) {
      setState(() => _isLoadingWidgetConfigs = false);
      return;
    }

    final configs = await _configService.fetchConfig(_selectedTemplateId!);
    if (!mounted || token != _selectionToken) return;

    setState(() {
      _widgetConfigs = configs;
      _isLoadingWidgetConfigs = false;
    });
  }

  Future<void> _searchClients() => _controller.searchClients();

  Future<void> _selectClient(Map<String, String> client) =>
      _controller.selectClient(client, timeRange: _getTimeRange());

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Dashboard',
      pageTitle: 'Analytics Dashboard',
      pageSubtitle: 'Operations, planning, and client insight center',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: widget.onLogout,
      headerActions: [
        if (widget.role == 'superadmin' || widget.role == 'admin')
          OutlinedButton.icon(
            onPressed: () => WebNavigator.go(
              context,
              'DashboardConfig',
              cswdId: widget.cswd_id,
              role: widget.role,
              displayName: widget.displayName,
              onLogout: widget.onLogout,
            ),
            icon: const Icon(Icons.settings),
            label: const Text('Configure Dashboard'),
          ),
      ],
      onNavigate: (path) => WebNavigator.go(
        context,
        path,
        cswdId: widget.cswd_id,
        role: widget.role,
        displayName: widget.displayName,
        onLogout: widget.onLogout,
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final isLoadingDashboard =
              _isLoadingOverview ||
              _controller.isLoadingCounts ||
              _controller.isLoadingInsights ||
              _isLoadingWidgetConfigs;

          return isLoadingDashboard
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.highlight,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormCardsSection(),
                      const SizedBox(height: 18),
                      _buildTimeRangeSelector(),
                      const SizedBox(height: 28),
                      _buildChartsSection(_getTimeRange()),
                    ],
                  ),
                );
        },
      ),
    );
  }

  Widget _buildFormCardsSection() {
    return _FormCardsSection(
      countsByFormType: _countsByFormType,
      totalCount: _totalCount,
      availableFormTypes: _availableFormTypes,
      selectedFormType: _selectedFormType,
      onSelectForm: _selectFormType,
    );
  }

  Widget _buildTimeRangeSelector() {
    final options = const [
      MapEntry('all', 'All Time'),
      MapEntry('yearly', 'Yearly'),
      MapEntry('monthly', 'Monthly'),
      MapEntry('weekly', 'Weekly'),
      MapEntry('daily', 'Daily'),
    ];

    final selected = options.map((option) => option.key == _selectedTimeRange).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToggleButtons(
          isSelected: selected,
          onPressed: (index) {
            final next = options[index].key;
            if (next == _selectedTimeRange) return;
            setState(() => _selectedTimeRange = next);
            _refreshDashboardData();
          },
          borderRadius: BorderRadius.circular(999),
          selectedColor: Colors.white,
          fillColor: AppColors.highlight,
          color: AppColors.textDark,
          borderColor: AppColors.cardBorder,
          selectedBorderColor: AppColors.highlight,
          constraints: const BoxConstraints(minHeight: 42),
          children: options
              .map(
                (option) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(option.value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Showing data for: ${_timeRangeLabel()}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildChartsSection(DateTimeRange? timeRange) {
    if (_selectedFormType == 'All') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGeneralMetricsSection(),
          const SizedBox(height: 28),
          _buildAllFormsOverview(timeRange),
          const SizedBox(height: 28),
          _buildWorkerAnalyticsSection('All', timeRange),
          const SizedBox(height: 28),
          // TODO: add a trend sparkline once time-bucketed analytics are exposed.
          _buildOperationalSection(timeRange),
          const SizedBox(height: 28),
          _buildPlanningSection(timeRange),
          const SizedBox(height: 28),
          _buildClientHistorySection(timeRange),
        ],
      );
    }

    if (_isLoadingWidgetConfigs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.highlight),
        ),
      );
    }

    if (_widgetConfigs.isEmpty) {
      return _buildNoDashboardConfigurationState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._widgetConfigs.map((config) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildConfiguredWidget(config, timeRange),
          );
        }),
        if (widget.role == 'superadmin' || widget.role == 'admin') ...[
          const SizedBox(height: 4),
          _buildWorkerAnalyticsSection(_selectedFormType, timeRange),
          const SizedBox(height: 28),
        ],
        _buildPlanningSection(timeRange),
      ],
    );
  }

  Widget _buildConfiguredWidget(
    DashboardWidgetConfig config,
    DateTimeRange? timeRange,
  ) {
    final cacheKey =
        '${config.fieldName}:${config.chartType}:${timeRange?.start.toIso8601String() ?? 'all'}:${timeRange?.end.toIso8601String() ?? 'all'}';
    final future = _distributionFutures.putIfAbsent(
      cacheKey,
      () => _analyticsService.fetchFieldDistribution(
        formType: _selectedFormType,
        fieldName: config.fieldName,
        isNumeric: false,
        isMultiSelect: false,
        topN: 20,
        timeRange: timeRange,
      ),
    );

    return FutureBuilder<Map<String, int>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.highlight),
            ),
          );
        }

        final data = snapshot.data ?? {};
        if (data.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              "No data yet for '${config.fieldLabel}'",
              style: const TextStyle(color: AppColors.textMuted),
            ),
          );
        }

        switch (config.chartType) {
          case 'pie':
            return SimpleDistributionPie(title: config.fieldLabel, data: data);
          case 'counter':
            final entries = data.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topEntry = entries.first;
            return MetricCard(
              label: config.fieldLabel,
              value: topEntry.value.toString(),
              icon: Icons.tag,
              color: AppColors.highlight,
              subtitle: topEntry.key,
              expand: false,
            );
          case 'hbar':
            return SimpleHorizontalBarChart(
              title: config.fieldLabel,
              data: data,
              primaryColor: AppColors.highlight,
            );
          case 'table':
            return SimpleDataTable(title: config.fieldLabel, data: data);
          default:
            return SimpleBarChart(
              title: config.fieldLabel,
              data: data,
              primaryColor: AppColors.highlight,
            );
        }
      },
    );
  }

  Widget _buildNoDashboardConfigurationState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 64,
            color: AppColors.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          const Text(
            'No dashboard configured for this form',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Go to Dashboard Configuration to define which fields to visualize.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          if (widget.role == 'superadmin' || widget.role == 'admin') ...[
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.highlight,
                foregroundColor: Colors.white,
              ),
              onPressed: () => WebNavigator.go(
                context,
                'DashboardConfig',
                cswdId: widget.cswd_id,
                role: widget.role,
                displayName: widget.displayName,
                onLogout: widget.onLogout,
              ),
              child: const Text('Configure Now'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneralMetricsSection() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        MetricCard(
          label: 'Total Submissions',
          value: _totalCount.toString(),
          icon: Icons.how_to_reg,
          color: AppColors.highlight,
          subtitle: _timeRangeLabel(),
          expand: false,
        ),
        MetricCard(
          label: 'Total Active Forms',
          value: _activeFormCount.toString(),
          icon: Icons.list_alt_rounded,
          color: AppColors.successGreen,
          subtitle: 'Configured templates',
          expand: false,
        ),
        MetricCard(
          label: 'Total Staff Accounts',
          value: _staffAccountCount.toString(),
          icon: Icons.groups_rounded,
          color: AppColors.highlight,
          subtitle: 'Worker accounts',
          expand: false,
        ),
        MetricCard(
          label: 'Total Clients',
          value: _uniqueClientCount.toString(),
          icon: Icons.people_alt_rounded,
          color: AppColors.highlight,
          subtitle: 'Unique applicants',
          expand: false,
        ),
      ],
    );
  }

  Widget _buildAllFormsOverview(DateTimeRange? timeRange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Forms Submitted Breakdown',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        SimpleDistributionPie(
          title: 'Submissions by Form Type',
          data: _countsByFormType,
        ),
      ],
    );
  }

  Widget _buildWorkerAnalyticsSection(
    String formType,
    DateTimeRange? timeRange,
  ) {
    final isGeneral = formType == 'All';
    final title = isGeneral ? 'Staff Submission Activity' : 'Staff Workload';
    final subtitle = isGeneral
        ? 'For audit and workload monitoring purposes'
        : 'Number of submissions handled per worker account';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (_workerAnalytics.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No submission data for this period.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            SimpleHorizontalBarChart(
              title: 'Submissions per Worker',
              data: _workerAnalytics,
              primaryColor: AppColors.highlight,
            ),
        ],
      ),
    );
  }

  Widget _buildOperationalSection(DateTimeRange? timeRange) {
    if (_isLoadingInsights) {
      return _buildLoadingCard('Loading operational metrics...');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operational & Efficiency',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        SimpleBarChart(
          title: 'Staff Workload Distribution (Audit Activity)',
          data: _staffWorkload,
          primaryColor: AppColors.highlight,
        ),
      ],
    );
  }

  Widget _buildPlanningSection(DateTimeRange? timeRange) {
    if (_isLoadingInsights) {
      return _buildLoadingCard('Loading planning analytics...');
    }

    final scopeLabel = _planningScopeFormType == 'All'
        ? 'All Forms'
        : _planningScopeFormType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Demographic & Trend Analytics - $scopeLabel',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            if (compact) {
              return Column(
                children: [
                  SimpleDistributionPie(
                    title: 'Automated GAD Report (Gender Ratio)',
                    data: _genderRatio,
                  ),
                  const SizedBox(height: 20),
                  SimpleBarChart(
                    title: 'Age Bracket Distribution',
                    data: _ageBrackets,
                    primaryColor: AppColors.highlight,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SimpleDistributionPie(
                    title: 'Automated GAD Report (Gender Ratio)',
                    data: _genderRatio,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SimpleBarChart(
                    title: 'Age Bracket Distribution',
                    data: _ageBrackets,
                    primaryColor: AppColors.highlight,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SimpleBarChart(
          title: 'Barangay Volume (Top Requests)',
          data: _barangayVolume,
          primaryColor: AppColors.highlight,
        ),
      ],
    );
  }

  Widget _buildClientHistorySection(DateTimeRange? timeRange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Holistic Client History (360 View)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _clientSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search client by name',
                            hintText: 'Type first name or last name',
                          ),
                          onSubmitted: (_) => _searchClients(),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton(
                            onPressed: _isSearchingClients ? null : _searchClients,
                            child: _isSearchingClients
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Lookup'),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _clientSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search client by name',
                            hintText: 'Type first name or last name',
                          ),
                          onSubmitted: (_) => _searchClients(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isSearchingClients ? null : _searchClients,
                        child: _isSearchingClients
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lookup'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (_clientSearchResults.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _clientSearchResults.map((client) {
                    final isSelected = (client['user_id'] ?? '') == _selectedClientId;
                    return GestureDetector(
                      onTap: () => _selectClient(client),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.highlight.withValues(alpha: 0.15)
                              : AppColors.pageBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.highlight
                                : AppColors.cardBorder,
                          ),
                        ),
                        child: Text(
                          client['name'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? AppColors.highlight
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_isLoadingClientHistory)
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: CircularProgressIndicator(color: AppColors.highlight),
                ),
              if (!_isLoadingClientHistory && _selectedClientId != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Selected: $_selectedClientName',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                if (_selectedClientFlags.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _selectedClientFlags.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                else
                  _buildInfoCard(
                    title: 'Eligibility Frequency Check',
                    body: 'No high-frequency assistance flags this year.',
                  ),
                const SizedBox(height: 12),
                if (_selectedClientHistory.isNotEmpty)
                  SimpleBarChart(
                    title: 'Cross-Service History (By Form Type)',
                    data: _groupHistoryByFormType(_selectedClientHistory),
                    primaryColor: AppColors.highlight,
                  )
                else
                  _buildInfoCard(
                    title: 'Cross-Service History',
                    body: 'No service history found for this client yet.',
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Map<String, int> _groupHistoryByFormType(
    List<Map<String, dynamic>> history,
  ) =>
      _controller.groupHistoryByFormType(history);

  Widget _buildLoadingCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 190,
        height: 180,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isActive ? AppColors.highlight : AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.highlight : AppColors.cardBorder,
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : AppColors.textDark,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Submissions',
              style: TextStyle(
                fontSize: 11,
                color: isActive ? Colors.white70 : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Tooltip(
              message: label,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppColors.textDark,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormCardsSection extends StatefulWidget {
  final Map<String, int> countsByFormType;
  final int totalCount;
  final List<String> availableFormTypes;
  final String selectedFormType;
  final ValueChanged<String> onSelectForm;

  const _FormCardsSection({
    required this.countsByFormType,
    required this.totalCount,
    required this.availableFormTypes,
    required this.selectedFormType,
    required this.onSelectForm,
  });

  @override
  State<_FormCardsSection> createState() => _FormCardsSectionState();
}

class _FormCardsSectionState extends State<_FormCardsSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showListView = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_syncSearchQuery);
  }

  @override
  void dispose() {
    _searchController.removeListener(_syncSearchQuery);
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchQuery() {
    final next = _searchController.text;
    if (next == _searchQuery) {
      return;
    }
    setState(() => _searchQuery = next);
  }

  List<_FormCardItem> _visibleFormCards() {
    final cards = <_FormCardItem>[
      _FormCardItem(
        label: 'All Forms',
        count: widget.totalCount,
        formType: 'All',
      ),
      ...widget.availableFormTypes.map(
        (formType) => _FormCardItem(
          label: formType,
          count: widget.countsByFormType[formType] ?? 0,
          formType: formType,
        ),
      ),
    ];

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return cards;
    }

    return cards
        .where((item) => item.label.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleCards = _visibleFormCards();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search forms...',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: AppColors.cardBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _showListView = !_showListView);
            },
            icon: Icon(
              _showListView ? Icons.grid_view : Icons.view_list,
              size: 18,
            ),
            label: Text(_showListView ? 'View as cards' : 'View as list'),
          ),
        ),
        const SizedBox(height: 16),
        if (visibleCards.isEmpty)
          _buildInfoCard(
            title: 'No matching forms',
            body: 'Try a different search term to find a form.',
          )
        else if (_showListView)
          _buildFormListView(visibleCards)
        else
          _buildSummaryCards(visibleCards),
      ],
    );
  }

  Widget _buildSummaryCards(List<_FormCardItem> cards) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards.map((item) {
        return _SummaryCard(
          label: item.label,
          count: item.count,
          isActive: widget.selectedFormType == item.formType,
          onTap: () => widget.onSelectForm(item.formType),
        );
      }).toList(),
    );
  }

  Widget _buildFormListView(List<_FormCardItem> cards) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Form Name',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Submission Count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                SizedBox(width: 72),
              ],
            ),
          ),
          ...cards.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Tooltip(
                      message: item.label,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      item.count.toString(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: TextButton(
                      onPressed: () => widget.onSelectForm(item.formType),
                      child: const Text('View'),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FormCardItem {
  final String label;
  final int count;
  final String formType;

  const _FormCardItem({
    required this.label,
    required this.count,
    required this.formType,
  });
}
