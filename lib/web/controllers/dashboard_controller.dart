import 'package:flutter/material.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';
import 'package:sappiire/services/forms/applicant_search_service.dart';

/// Coordinates dashboard data loading, planning insights, and client search state.
class DashboardController extends ChangeNotifier {
  DashboardController({DashboardAnalyticsService? analyticsService})
    : _analyticsService = analyticsService ?? DashboardAnalyticsService();

  final DashboardAnalyticsService _analyticsService;

  final TextEditingController clientSearchController = TextEditingController();

  Map<String, int> countsByFormType = {};
  int totalCount = 0;
  List<String> availableFormTypes = [];
  bool isLoadingCounts = true;

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

  Future<void> loadSummary({DateTimeRange? timeRange}) async {
    isLoadingCounts = true;
    notifyListeners();

    try {
      final counts = await _analyticsService.fetchSubmissionsByFormType(
        timeRange: timeRange,
      );
      final types = counts.keys.toList()..sort();

      countsByFormType = counts;
      totalCount = counts.values.fold(0, (a, b) => a + b);
      if (availableFormTypes.isEmpty) {
        availableFormTypes = types;
      }
      isLoadingCounts = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[DashboardController/loadSummary] Error: $e');
      isLoadingCounts = false;
      notifyListeners();
    }
  }

  Future<void> loadOperationalInsights({DateTimeRange? timeRange}) async {
    try {
      final workload = await _analyticsService.fetchStaffWorkloadDistribution(
        timeRange: timeRange,
      );
      staffWorkload = workload;
      notifyListeners();
    } catch (e) {
      debugPrint('[DashboardController/loadOperationalInsights] Error: $e');
    }
  }

  Future<void> loadPlanningInsights(
    String formType, {
    DateTimeRange? timeRange,
  }) async {
    isLoadingInsights = true;
    planningScopeFormType = formType;
    notifyListeners();

    try {
      final scopedForm = formType == 'All' ? 'All' : formType;
      final results = await Future.wait([
        _analyticsService.fetchGenderRatio(
          formType: scopedForm,
          timeRange: timeRange,
        ),
        _analyticsService.fetchAgeBracketDistribution(
          formType: scopedForm,
          timeRange: timeRange,
        ),
        _analyticsService.fetchBarangayVolume(
          formType: scopedForm,
          timeRange: timeRange,
        ),
      ]);

      genderRatio = results[0];
      ageBrackets = results[1];
      barangayVolume = results[2];
    } catch (e) {
      debugPrint('[DashboardController/loadPlanningInsights] Error: $e');
    } finally {
      isLoadingInsights = false;
      notifyListeners();
    }
  }

  Future<void> searchClients() async {
    final query = clientSearchController.text.trim();
    // Below the minimum, a query would scan almost everything server-side and
    // return nothing an admin can use.
    if (query.length < ApplicantSearchService.minQueryLength) {
      clientSearchResults = [];
      isSearchingClients = false;
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

  Future<void> selectClient(
    Map<String, String> client, {
    DateTimeRange? timeRange,
  }) async {
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
        _analyticsService.fetchClientHistory(clientId, timeRange: timeRange),
        _analyticsService.fetchEligibilityFrequencyFlags(
          clientId,
          timeRange: timeRange,
        ),
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
