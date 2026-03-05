import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/services/intake_analytics_service.dart';
import 'package:sappiire/web/components/intake_chart_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late IntakeAnalyticsService _analyticsService;
  
  // State variables for analytics data
  int _totalSubmissions = 0;
  Map<String, int> _genderDistribution = {};
  Map<String, int> _ageDistribution = {};
  Map<String, int> _membershipDistribution = {};
  Map<String, int> _incomeDistribution = {};
  Map<String, int> _employmentDistribution = {};
  Map<String, int> _educationDistribution = {};
  Map<String, int> _housingDistribution = {};
  int _youthCount = 0;
  double _averageHouseholdSize = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _analyticsService = IntakeAnalyticsService();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    try {
      setState(() => _isLoading = true);

      final stats = await _analyticsService.getSummaryStats();
      final [
        genderDist,
        ageDist,
        membershipDist,
        incomeDist,
        employmentDist,
        educationDist,
        housingDist,
      ] = await Future.wait([
        _analyticsService.getGenderDistribution(),
        _analyticsService.getAgeGroupDistribution(),
        _analyticsService.getMembershipDistribution(),
        _analyticsService.getIncomeDistribution(),
        _analyticsService.getEmploymentDistribution(),
        _analyticsService.getEducationDistribution(),
        _analyticsService.getHousingDistribution(),
      ]);

      setState(() {
        _totalSubmissions = stats['totalSubmissions'] as int;
        _genderDistribution = genderDist;
        _ageDistribution = ageDist;
        _membershipDistribution = membershipDist;
        _incomeDistribution = incomeDist;
        _employmentDistribution = employmentDist;
        _educationDistribution = educationDist;
        _housingDistribution = housingDist;
        _youthCount = stats['youthCount'] as int;
        _averageHouseholdSize = stats['averageHouseholdSize'] as double;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading analytics data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Dashboard',
      pageTitle: 'Intake Analytics Dashboard',
      pageSubtitle: 'Comprehensive insights from General Intake submissions',
      onLogout: widget.onLogout,
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── HEADER SECTION ───────────────────────────────────────────
                    _buildHeaderSection(),
                    const SizedBox(height: 40),

                    // ─── KEY METRICS ──────────────────────────────────────────────
                    _buildKeyMetricsSection(),
                    const SizedBox(height: 40),

                    // ─── DEMOGRAPHICS SECTION ─────────────────────────────────────
                    _buildSectionHeader(
                      'Demographics',
                      Icons.people_outline,
                      AppColors.highlight,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SimpleDistributionPie(
                            title: 'Gender Distribution',
                            data: _genderDistribution,
                            showPercentage: true,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: SimpleBarChart(
                            title: 'Age Groups',
                            data: _ageDistribution,
                            primaryColor: const Color(0xFF95E1D3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // ─── ECONOMIC & INCOME SECTION ────────────────────────────────
                    _buildSectionHeader(
                      'Economic Status',
                      Icons.trending_up,
                      const Color(0xFFFFA500),
                    ),
                    const SizedBox(height: 20),
                    SimpleBarChart(
                      title: 'Monthly Income Distribution',
                      data: _incomeDistribution,
                      primaryColor: const Color(0xFFFFA500),
                    ),
                    const SizedBox(height: 40),

                    // ─── ASSISTANCE PROGRAMS SECTION ──────────────────────────────
                    _buildSectionHeader(
                      'Government Assistance Programs',
                      Icons.card_membership,
                      const Color(0xFFFF6B6B),
                    ),
                    const SizedBox(height: 20),
                    SimpleBarChart(
                      title: 'Program Membership Status',
                      data: _membershipDistribution,
                      primaryColor: const Color(0xFFFF6B6B),
                    ),
                    const SizedBox(height: 40),

                    // ─── EDUCATION & EMPLOYMENT ───────────────────────────────────
                    _buildSectionHeader(
                      'Education & Employment',
                      Icons.school_outlined,
                      const Color(0xFFAA96DA),
                    ),
                    const SizedBox(height: 20),
                    if (_educationDistribution.isNotEmpty)
                      SimpleBarChart(
                        title: 'Educational Attainment',
                        data: _educationDistribution,
                        primaryColor: const Color(0xFFF38181),
                      )
                    else
                      const SizedBox(),
                    if (_educationDistribution.isNotEmpty)
                      const SizedBox(height: 20)
                    else
                      const SizedBox(),
                    if (_employmentDistribution.isNotEmpty)
                      SimpleBarChart(
                        title: 'Employment Status',
                        data: _employmentDistribution,
                        primaryColor: const Color(0xFFAA96DA),
                      )
                    else
                      const SizedBox(),
                    if (_employmentDistribution.isNotEmpty)
                      const SizedBox(height: 40)
                    else
                      const SizedBox(),

                    // ─── HOUSING & LIVING CONDITIONS ──────────────────────────────
                    if (_housingDistribution.isNotEmpty)
                      _buildSectionHeader(
                        'Housing & Living Conditions',
                        Icons.home_outlined,
                        const Color(0xFF4ECDC4),
                      )
                    else
                      const SizedBox(),
                    if (_housingDistribution.isNotEmpty)
                      const SizedBox(height: 20)
                    else
                      const SizedBox(),
                    if (_housingDistribution.isNotEmpty)
                      SimpleDistributionPie(
                        title: 'Housing Status Distribution',
                        data: _housingDistribution,
                        showPercentage: true,
                      )
                    else
                      const SizedBox(),
                    const SizedBox(height: 20),
                  ],
                ),
        ),
      ),
    );
  }

  /// Build header section with welcome message and last updated info
  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.highlight.withValues(alpha: 0.1),
            AppColors.highlight.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'General Intake Data Overview',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Real-time analytics and demographic insights',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.highlight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assessment,
                  color: AppColors.highlight,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build key metrics section with 3-column grid
  Widget _buildKeyMetricsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Key Metrics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Row(
          children: [
            MetricCard(
              label: "Total Submissions",
              value: _totalSubmissions.toString(),
              icon: Icons.description,
              color: AppColors.highlight,
              subtitle: 'Entries collected',
            ),
            const SizedBox(width: 20),
            MetricCard(
              label: "Youth (≤17 years)",
              value: _youthCount.toString(),
              icon: Icons.child_care,
              color: const Color(0xFF4ECDC4),
              subtitle: _totalSubmissions > 0
                  ? '${((_youthCount / _totalSubmissions) * 100).toStringAsFixed(1)}%'
                  : '0%',
            ),
            const SizedBox(width: 20),
            MetricCard(
              label: "Avg Household",
              value: _averageHouseholdSize.toStringAsFixed(1),
              unit: 'persons',
              icon: Icons.people,
              color: AppColors.successGreen,
              subtitle: 'Per family',
            ),
          ],
        ),
      ],
    );
  }

  /// Build section header with icon and divider
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Forms':
        nextScreen = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Staff':
        nextScreen = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'CreateStaff':
        nextScreen = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }
}