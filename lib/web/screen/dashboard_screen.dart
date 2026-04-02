import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/components/auto_chart_builder.dart';
import 'package:sappiire/web/components/intake_chart_widgets.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/widget/web_shell.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int> _countsByFormType = {};
  int _totalCount = 0;
  List<String> _availableFormTypes = [];
  bool _isLoadingCounts = true;

  String _selectedFormType = 'All';
  String _formSearchQuery = '';
  bool _showFormListView = false;

  List<ChartConfig> _charts = [];
  bool _isLoadingCharts = false;

  bool _isLoadingInsights = true;
  Map<String, int> _staffWorkload = {};
  Map<String, int> _genderRatio = {};
  Map<String, int> _ageBrackets = {};
  Map<String, int> _barangayVolume = {};
  String _planningScopeFormType = 'All';

  final TextEditingController _clientSearchController = TextEditingController();
  bool _isSearchingClients = false;
  bool _isLoadingClientHistory = false;
  List<Map<String, String>> _clientSearchResults = [];
  String? _selectedClientId;
  String _selectedClientName = '';
  List<Map<String, dynamic>> _selectedClientHistory = [];
  Map<String, String> _selectedClientFlags = {};

  final _analyticsService = DashboardAnalyticsService();
  final _templateService = FormTemplateService();
  final _chartBuilder = AutoChartBuilder();

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _clientSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoadingCounts = true);
    try {
      final counts = await _analyticsService.fetchCountsByFormType();
      final types = counts.keys.toList()..sort();

      if (!mounted) {
        return;
      }

      setState(() {
        _countsByFormType = counts;
        _totalCount = counts.values.fold(0, (a, b) => a + b);
        _availableFormTypes = types;
        _isLoadingCounts = false;
      });

      await Future.wait([
        _loadOperationalInsights(),
        _loadPlanningInsights('All'),
        _loadChartsFor('All'),
      ]);
    } catch (e) {
      debugPrint('_loadSummary error: $e');
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingCounts = false);
    }
  }

  Future<void> _loadOperationalInsights() async {
    try {
      final workload = await _analyticsService.fetchStaffWorkloadDistribution();

      if (!mounted) {
        return;
      }

      setState(() {
        _staffWorkload = workload;
      });
    } catch (e) {
      debugPrint('_loadOperationalInsights error: $e');
    }
  }

  Future<void> _loadPlanningInsights(String formType) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingInsights = true;
      _planningScopeFormType = formType;
    });

    try {
      final scopedForm = formType == 'All' ? 'All' : formType;
      final results = await Future.wait([
        _analyticsService.fetchGenderRatio(formType: scopedForm),
        _analyticsService.fetchAgeBracketDistribution(formType: scopedForm),
        _analyticsService.fetchBarangayVolume(formType: scopedForm),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _genderRatio = results[0] as Map<String, int>;
        _ageBrackets = results[1] as Map<String, int>;
        _barangayVolume = results[2] as Map<String, int>;
        _isLoadingInsights = false;
      });
    } catch (e) {
      debugPrint('_loadPlanningInsights error: $e');
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingInsights = false);
    }
  }

  Future<void> _loadChartsFor(String formType) async {
    final planningFuture = _loadPlanningInsights(formType);

    setState(() {
      _selectedFormType = formType;
      _isLoadingCharts = true;
      _charts = [];
    });

    if (formType == 'All') {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingCharts = false);
      await planningFuture;
      return;
    }

    try {
      final templates = await _templateService.fetchActiveTemplates();
      final matched = templates.where((t) => t.formName == formType);
      final template = matched.isEmpty ? null : matched.first;

      if (template == null) {
        if (!mounted) {
          return;
        }
        setState(() => _isLoadingCharts = false);
        return;
      }

      final charts = await _chartBuilder.buildCharts(
        template: template,
        formType: formType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _charts = charts;
        _isLoadingCharts = false;
      });

      await planningFuture;
    } catch (e) {
      debugPrint('_loadChartsFor error: $e');
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingCharts = false);
      await planningFuture;
    }
  }

  Future<void> _searchClients() async {
    final query = _clientSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _clientSearchResults = [];
      });
      return;
    }

    setState(() => _isSearchingClients = true);
    try {
      final results = await _analyticsService.searchClientsByName(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _clientSearchResults = results;
        _isSearchingClients = false;
      });
    } catch (e) {
      debugPrint('_searchClients error: $e');
      if (!mounted) {
        return;
      }
      setState(() => _isSearchingClients = false);
    }
  }

  Future<void> _selectClient(Map<String, String> client) async {
    final clientId = client['user_id'] ?? '';
    if (clientId.isEmpty) {
      return;
    }

    setState(() {
      _selectedClientId = clientId;
      _selectedClientName = client['name'] ?? '';
      _selectedClientHistory = [];
      _selectedClientFlags = {};
      _isLoadingClientHistory = true;
    });

    try {
      final results = await Future.wait([
        _analyticsService.fetchClientHistory(clientId),
        _analyticsService.fetchEligibilityFrequencyFlags(clientId),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedClientHistory = results[0] as List<Map<String, dynamic>>;
        _selectedClientFlags = results[1] as Map<String, String>;
        _isLoadingClientHistory = false;
      });
    } catch (e) {
      debugPrint('_selectClient error: $e');
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingClientHistory = false);
    }
  }

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
      onNavigate: (path) => _navigateToScreen(context, path),
      child: _isLoadingCounts
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormCardsSection(),
                  const SizedBox(height: 28),
                  _buildChartsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildFormCardsSection() {
    return _FormCardsSection(
      countsByFormType: _countsByFormType,
      totalCount: _totalCount,
      availableFormTypes: _availableFormTypes,
      selectedFormType: _selectedFormType,
      onSelectForm: _loadChartsFor,
    );
  }

  Widget _buildChartsSection() {
    if (_selectedFormType == 'All') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAllFormsOverview(),
          const SizedBox(height: 28),
          _buildOperationalSection(),
          const SizedBox(height: 28),
          _buildPlanningSection(),
          const SizedBox(height: 28),
          _buildClientHistorySection(),
        ],
      );
    }

    if (_isLoadingCharts) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(60),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_charts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNoChartsPlaceholder(),
          const SizedBox(height: 24),
          _buildPlanningSection(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._charts.map((chart) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: chart.style == ChartStyle.pie
                ? SimpleDistributionPie(title: chart.title, data: chart.data)
                : SimpleBarChart(
                    title: chart.title,
                    data: chart.data,
                    primaryColor: AppColors.highlight,
                  ),
          );
        }),
        _buildPlanningSection(),
      ],
    );
  }

  Widget _buildAllFormsOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Submission Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        SimpleBarChart(
          title: 'Submissions by Form Type',
          data: _countsByFormType,
          primaryColor: AppColors.highlight,
        ),
      ],
    );
  }

  Widget _buildOperationalSection() {
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
          primaryColor: const Color(0xFF4ECDC4),
        ),
      ],
    );
  }

  Widget _buildPlanningSection() {
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
                    primaryColor: const Color(0xFF9B6EF3),
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
                    primaryColor: const Color(0xFF9B6EF3),
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
          primaryColor: const Color(0xFF2EC4B6),
        ),
      ],
    );
  }

  Widget _buildClientHistorySection() {
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
                            onPressed: _isSearchingClients
                                ? null
                                : _searchClients,
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
                    final isSelected =
                        (client['user_id'] ?? '') == _selectedClientId;
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
                  child: CircularProgressIndicator(),
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

  Map<String, int> _groupHistoryByFormType(List<Map<String, dynamic>> history) {
    final grouped = <String, int>{};
    for (final item in history) {
      final key = item['form_type']?.toString().trim() ?? 'Unknown';
      grouped[key] = (grouped[key] ?? 0) + 1;
    }
    return grouped;
  }

  Widget _buildNoChartsPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 64,
            color: AppColors.textMuted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No charts available for this form',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Charts appear automatically when this form has dropdown, radio,\n'
            'checkbox, or number fields with enough collected data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

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

  void _navigateToScreen(BuildContext context, String screenPath) {
    if ((screenPath == 'Staff' || screenPath == 'CreateStaff') &&
        widget.role != 'superadmin') {
      return;
    }
    Widget nextScreen;
    switch (screenPath) {
      case 'Forms':
        nextScreen = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'Staff':
        nextScreen = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'CreateStaff':
        nextScreen = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'FormBuilder':
        if (widget.role != 'superadmin') return;
        nextScreen = FormBuilderScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'AuditLogs':
        if (widget.role != 'superadmin') return;
        nextScreen = AuditLogsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(ContentFadeRoute(page: nextScreen));
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

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              color: AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
