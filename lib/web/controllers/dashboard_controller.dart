import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/components/auto_chart_builder.dart';

/// Coordinates dashboard data loading, chart generation, and client search state.
class DashboardController extends ChangeNotifier {
  DashboardController({
    DashboardAnalyticsService? analyticsService,
    FormTemplateService? templateService,
    AutoChartBuilder? chartBuilder,
  }) : _analyticsService = analyticsService ?? DashboardAnalyticsService(),
       _templateService = templateService ?? FormTemplateService(),
       _chartBuilder = chartBuilder ?? AutoChartBuilder();

  final DashboardAnalyticsService _analyticsService;
  final FormTemplateService _templateService;
  final AutoChartBuilder _chartBuilder;

  final TextEditingController clientSearchController = TextEditingController();

  Map<String, int> countsByFormType = {};
  int totalCount = 0;
  List<String> availableFormTypes = [];
  bool isLoadingCounts = true;

  String selectedFormType = 'All';
  List<ChartConfig> charts = [];
  bool isLoadingCharts = false;

  bool isLoadingInsights = true;
  Map<String, int> staffWorkload = {};
  Map<String, int> genderRatio = {};
  Map<String, int> ageBrackets = {};
  Map<String, int> barangayVolume = {};
  String planningScopeFormType = 'All';

  bool isSearchingClients = false;
  bool isLoadingClientHistory = false;
  List<Map<String, String>> clientSearchResults = [];
  String? selectedClientId;
  String selectedClientName = '';
  List<Map<String, dynamic>> selectedClientHistory = [];
  Map<String, String> selectedClientFlags = {};

  void setStaffId(String cswdId) {
    _analyticsService.setStaffId(cswdId);
  }

  Future<void> loadSummary() async {
    isLoadingCounts = true;
    notifyListeners();

    try {
      final counts = await _analyticsService.fetchCountsByFormType();
      final types = counts.keys.toList()..sort();

      countsByFormType = counts;
      totalCount = counts.values.fold(0, (a, b) => a + b);
      availableFormTypes = types;
      isLoadingCounts = false;
      notifyListeners();

      await Future.wait([
        loadOperationalInsights(),
        loadPlanningInsights('All'),
        loadChartsFor('All'),
      ]);
    } catch (e) {
      debugPrint('[DashboardController/loadSummary] Error: $e');
      isLoadingCounts = false;
      notifyListeners();
    }
  }

  Future<void> loadOperationalInsights() async {
    try {
      final workload = await _analyticsService.fetchStaffWorkloadDistribution();
      staffWorkload = workload;
      notifyListeners();
    } catch (e) {
      debugPrint('[DashboardController/loadOperationalInsights] Error: $e');
    }
  }

  Future<void> loadPlanningInsights(String formType) async {
    isLoadingInsights = true;
    planningScopeFormType = formType;
    notifyListeners();

    try {
      final scopedForm = formType == 'All' ? 'All' : formType;
      final results = await Future.wait([
        _analyticsService.fetchGenderRatio(formType: scopedForm),
        _analyticsService.fetchAgeBracketDistribution(formType: scopedForm),
        _analyticsService.fetchBarangayVolume(formType: scopedForm),
      ]);

      genderRatio = results[0] as Map<String, int>;
      ageBrackets = results[1] as Map<String, int>;
      barangayVolume = results[2] as Map<String, int>;
    } catch (e) {
      debugPrint('[DashboardController/loadPlanningInsights] Error: $e');
    } finally {
      isLoadingInsights = false;
      notifyListeners();
    }
  }

  Future<void> loadChartsFor(String formType) async {
    final planningFuture = loadPlanningInsights(formType);

    selectedFormType = formType;
    isLoadingCharts = true;
    charts = [];
    notifyListeners();

    if (formType == 'All') {
      isLoadingCharts = false;
      notifyListeners();
      await planningFuture;
      return;
    }

    try {
      final templates = await _templateService.fetchActiveTemplates();
      final matched = templates.where((t) => t.formName == formType);
      final template = matched.isEmpty ? null : matched.first;

      if (template == null) {
        isLoadingCharts = false;
        notifyListeners();
        return;
      }

      charts = await _chartBuilder.buildCharts(template: template, formType: formType);
    } catch (e) {
      debugPrint('[DashboardController/loadChartsFor] Error: $e');
    } finally {
      isLoadingCharts = false;
      notifyListeners();
      await planningFuture;
    }
  }

  Future<void> searchClients() async {
    final query = clientSearchController.text.trim();
    if (query.isEmpty) {
      clientSearchResults = [];
      notifyListeners();
      return;
    }

    isSearchingClients = true;
    notifyListeners();

    try {
      clientSearchResults = await _analyticsService.searchClientsByName(query);
    } catch (e) {
      debugPrint('[DashboardController/searchClients] Error: $e');
    } finally {
      isSearchingClients = false;
      notifyListeners();
    }
  }

  Future<void> selectClient(Map<String, String> client) async {
    final clientId = client['user_id'] ?? '';
    if (clientId.isEmpty) return;

    selectedClientId = clientId;
    selectedClientName = client['name'] ?? '';
    selectedClientHistory = [];
    selectedClientFlags = {};
    isLoadingClientHistory = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _analyticsService.fetchClientHistory(clientId),
        _analyticsService.fetchEligibilityFrequencyFlags(clientId),
      ]);

      selectedClientHistory = results[0] as List<Map<String, dynamic>>;
      selectedClientFlags = results[1] as Map<String, String>;
    } catch (e) {
      debugPrint('[DashboardController/selectClient] Error: $e');
    } finally {
      isLoadingClientHistory = false;
      notifyListeners();
    }
  }

  Map<String, int> groupHistoryByFormType(List<Map<String, dynamic>> history) {
    final grouped = <String, int>{};
    for (final item in history) {
      final key = item['form_type']?.toString().trim() ?? 'Unknown';
      grouped[key] = (grouped[key] ?? 0) + 1;
    }
    return grouped;
  }

  @override
  void dispose() {
    clientSearchController.dispose();
    super.dispose();
  }
}
