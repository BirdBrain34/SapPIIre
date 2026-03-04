import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/resources/GIS.dart';
import 'package:sappiire/resources/signature_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApplicantsScreen extends StatefulWidget {
  final String cswd_id;
  final String role;

  const ApplicantsScreen({
    super.key,
    required this.cswd_id,
    required this.role,
  });

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _selectedSubmission;
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ── Read-only controllers (populated when a submission is selected) ──────────
  final Map<String, TextEditingController> _viewControllers = {};

  // ── Complex field state (read-only mirrors) ──────────────────────────────────
  Map<String, bool> _membershipData = {
    'solo_parent': false,
    'pwd': false,
    'four_ps_member': false,
    'phic_member': false,
  };
  List<Map<String, dynamic>> _familyMembers = [];
  List<Map<String, dynamic>> _supportingFamily = [];
  bool _hasSupport = false;
  String? _housingStatus;
  String? _signatureBase64;

  // --- editing mode state --------------------------------------------------
  final Map<String, TextEditingController> _editControllers = {};
  Map<String, bool> _fieldChecks = {};
  bool _isEditMode = false;
  bool _isSaving = false;



  static const List<String> _allLabels = [
    "Last Name", "First Name", "Middle Name", "Date of Birth", "Age",
    "House number, street name, phase/purok", "Subdivision", "Barangay",
    "Kasarian", "Estadong Sibil", "Relihiyon", "CP Number", "Email Address",
    "Natapos o naabot sa pag-aaral", "Lugar ng Kapanganakan",
    "Trabaho/Pinagkakitaan", "Kumpanyang Pinagtratrabuhan",
    "Buwanang Kita (A)", "Total Gross Family Income (A+B+C)=(D)",
    "Household Size (E)", "Monthly Per Capita Income (D/E)",
    "Total Monthly Expense (F)", "Net Monthly Income (D-F)",
    "Bayad sa bahay", "Food items", "Non-food items", "Utility bills",
    "Baby's needs", "School needs", "Medical needs", "Transpo expense",
    "Loans", "Gasul", "Kabuuang Tulong/Sustento kada Buwan (C)"
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeEditControllers();
    _fetchSubmissions();
  }

  void _initializeControllers() {
    for (final label in _allLabels) {
      _viewControllers[label] = TextEditingController();
    }
  }

  /// Prepare a separate set of controllers used while the user is editing a
  /// submission so that we can discard or save without altering the viewable
  /// controllers.
  void _initializeEditControllers() {
    for (final label in _allLabels) {
      _editControllers[label] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _viewControllers.values) c.dispose();
    for (final c in _editControllers.values) c.dispose();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────────
  Future<void> _fetchSubmissions() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('client_submissions')
          .select('id, form_type, data, created_at')
          .order('created_at', ascending: false);

      setState(() {
        _submissions = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching submissions: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Populate all view-only controllers from a selected submission's data map.
  void _loadSubmissionIntoView(Map<String, dynamic> submission) {
    final data = submission['data'] as Map<String, dynamic>? ?? {};

    // Clear first
    for (final c in _viewControllers.values) c.clear();

    // Build normalized lookup of data keys to handle small label differences
    String _normalize(String s) =>
        s.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final Map<String, String> normalizedToKey = {};
    data.forEach((k, v) {
      normalizedToKey[_normalize(k)] = k;
    });

    // Populate by exact key first
    data.forEach((key, value) {
      if (_viewControllers.containsKey(key)) {
        _viewControllers[key]!.text = value?.toString() ?? '';
      }
    });

    // Populate remaining controllers by normalized key match
    for (final label in _viewControllers.keys) {
      if (_viewControllers[label]!.text.isEmpty) {
        final sourceKey = normalizedToKey[_normalize(label)];
        if (sourceKey != null && data.containsKey(sourceKey)) {
          _viewControllers[label]!.text =
              data[sourceKey]?.toString() ?? '';
        }
      }
    }

    // Membership
    final membership = data['__membership'] as Map<String, dynamic>? ?? {};
    _membershipData = {
      'solo_parent': membership['solo_parent'] ?? false,
      'pwd': membership['pwd'] ?? false,
      'four_ps_member': membership['four_ps_member'] ?? false,
      'phic_member': membership['phic_member'] ?? false,
    };

    // Family composition
    _familyMembers = data.containsKey('__family_composition')
        ? List<Map<String, dynamic>>.from(data['__family_composition'] ?? [])
        : [];

    // Supporting family
    _supportingFamily = data.containsKey('__supporting_family')
        ? List<Map<String, dynamic>>.from(data['__supporting_family'] ?? [])
        : [];

    _hasSupport = data['__has_support'] ?? false;
    _housingStatus = data['__housing_status'];
    _signatureBase64 = data['__signature'];

    // reset any editing state when a new submission is chosen
    _fieldChecks.clear();

    if (_isEditMode) {
      _copyViewToEdit();
    }

    setState(() => _selectedSubmission = submission);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  void _copyViewToEdit() {
    for (final key in _viewControllers.keys) {
      _editControllers[key]!.text = _viewControllers[key]!.text;
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (_isEditMode) {
        _fieldChecks.clear();
        _copyViewToEdit();
      }
    });
  }

  void _cancelEdit() {
    setState(() => _isEditMode = false);
  }

  Future<void> _saveChanges() async {
    if (_selectedSubmission == null) return;
    setState(() => _isSaving = true);

    final updatedData = <String, dynamic>{};
    for (final entry in _editControllers.entries) {
      updatedData[entry.key] = entry.value.text;
    }
    updatedData['__membership'] = _membershipData;
    updatedData['__family_composition'] = _familyMembers;
    updatedData['__supporting_family'] = _supportingFamily;
    updatedData['__has_support'] = _hasSupport;
    updatedData['__housing_status'] = _housingStatus;
    updatedData['__signature'] = _signatureBase64 ?? '';

    try {
      await Supabase.instance.client
          .from('client_submissions')
          .update({'data': updatedData})
          .eq('id', _selectedSubmission!['id']);
      await _fetchSubmissions();
      setState(() {
        _isEditMode = false;
        _isSaving = false;
      });
      _loadSubmissionIntoView(_submissions.firstWhere(
          (e) => e['id'] == _selectedSubmission!['id'],
          orElse: () => {}));
    } catch (e) {
      debugPrint('Error saving changes: $e');
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteSubmission() async {
    if (_selectedSubmission == null) return;
    final id = _selectedSubmission!['id'];
    try {
      await Supabase.instance.client
          .from('client_submissions')
          .delete()
          .eq('id', id);
      setState(() {
        _selectedSubmission = null;
        _isEditMode = false;
      });
      await _fetchSubmissions();
    } catch (e) {
      debugPrint('Error deleting submission: $e');
    }
  }

  String _getApplicantName(Map<String, dynamic> submission) {
    final data = submission['data'] as Map<String, dynamic>? ?? {};
    final first = data['First Name'] ?? '';
    final middle = data['Middle Name'] ?? '';
    final last = data['Last Name'] ?? '';
    if (first.isEmpty && last.isEmpty) return 'Unknown Applicant';
    return '$last, $first${middle.isNotEmpty ? ' ${middle[0]}.' : ''}'.trim();
  }

  String _getFormattedDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  List<Map<String, dynamic>> get _filteredSubmissions {
    if (_searchQuery.isEmpty) return _submissions;
    final q = _searchQuery.toLowerCase();
    return _submissions.where((s) {
      return _getApplicantName(s).toLowerCase().contains(q) ||
          (s['form_type'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // ── Navigation / logout ───────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(page: const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          onLogout: _handleLogout,
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
      case 'Forms':
        nextScreen = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      default:
        return;
    }
    Navigator.of(context).pushReplacement(ContentFadeRoute(page: nextScreen));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'Applicants',
      pageSubtitle: 'Review submitted client intake forms',
      onLogout: _handleLogout,
      headerActions: [
        _buildHeaderButton("Refresh", Icons.refresh, onPressed: _fetchSubmissions),
        if (_selectedSubmission != null) ...[
          if (!_isEditMode)
            _buildHeaderButton("Edit", Icons.edit, onPressed: _toggleEditMode),
          if (_isEditMode) ...[
            _buildHeaderButton("Delete", Icons.delete, onPressed: _deleteSubmission),
          ],
        ],
      ],
      onNavigate: (path) => _navigateToScreen(context, path),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    // ── LEFT: Applicant list panel ─────────────────────────────
                    _buildApplicantListPanel(),

                    // ── RIGHT: Form detail panel (mirrors ManageForms style) ───
                    Expanded(
                      child: _selectedSubmission == null
                          ? _buildEmptyState()
                          : _buildFormDetailPanel(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Left panel: list of submissions ──────────────────────────────────────────
  Widget _buildApplicantListPanel() {
    return Container(
      width: 300,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search applicants...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: Colors.grey.shade400, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF4F7FE),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filteredSubmissions.length} submission${_filteredSubmissions.length != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSubmissions.isEmpty
                    ? Center(
                        child: Text(
                          'No submissions found.',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredSubmissions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sub = _filteredSubmissions[index];
                          final isSelected =
                              _selectedSubmission?['id'] == sub['id'];
                          final name = _getApplicantName(sub);
                          final date = _getFormattedDate(
                              sub['created_at'] as String?);
                          final formType =
                              sub['form_type'] as String? ?? 'GIS';

                          return InkWell(
                            onTap: () => _loadSubmissionIntoView(sub),
                            child: Container(
                              color: isSelected
                                  ? AppColors.primaryBlue.withOpacity(0.08)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isSelected
                                        ? AppColors.primaryBlue
                                        : const Color(0xFFE8EDF8),
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.primaryBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isSelected
                                                ? AppColors.primaryBlue
                                                : const Color(0xFF1A1A2E),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(formType,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500)),
                                        Text(date,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade400)),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.chevron_right,
                                        color: AppColors.primaryBlue,
                                        size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ── Right panel: empty state ──────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search_outlined,
              size: 64, color: Colors.white.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'Select an applicant to view their form',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── Right panel: form detail (mirrors ManageFormsScreen section cards) ────────
  Widget _buildFormDetailPanel() {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              children: [
                // Client Info
                _buildSectionCard(
                  child: ClientInfoSection(
                    selectAll: false,
                    controllers:
                        _isEditMode ? _editControllers : _viewControllers,
                    fieldChecks: _fieldChecks,
                    onCheckChanged: (field, val) {
                      if (!_isEditMode) return;
                      setState(() => _fieldChecks[field] = val);
                    },
                    membershipData: _membershipData,
                    onMembershipChanged: _isEditMode
                        ? (key, val) =>
                            setState(() => _membershipData[key] = val)
                        : (_, __) {},
                  ),
                ),

                // Family Composition
                _buildSectionCard(
                  child: FamilyTable(
                    selectAll: false,
                    controllers:
                        _isEditMode ? _editControllers : _viewControllers,
                    familyMembers: _familyMembers,
                    onFamilyChanged: _isEditMode
                        ? (list) => setState(() => _familyMembers = list)
                        : (_) {},
                    fieldChecks: _fieldChecks,
                    onCheckChanged: (field, val) {
                      if (!_isEditMode) return;
                      setState(() => _fieldChecks[field] = val);
                    },
                  ),
                ),

                // Socio-Economic
                _buildSectionCard(
                  child: SocioEconomicSection(
                    selectAll: false,
                    controllers:
                        _isEditMode ? _editControllers : _viewControllers,
                    hasSupport: _hasSupport,
                    housingStatus: _housingStatus,
                    supportingFamily: _supportingFamily,
                    onHasSupportChanged: _isEditMode
                        ? (val) => setState(() => _hasSupport = val)
                        : (_) {},
                    onHousingStatusChanged: _isEditMode
                        ? (val) => setState(() => _housingStatus = val)
                        : (_) {},
                    onSupportingFamilyChanged: _isEditMode
                        ? (list) =>
                            setState(() => _supportingFamily = list)
                        : (_) {},
                    fieldChecks: _fieldChecks,
                    onCheckChanged: (field, val) {
                      if (!_isEditMode) return;
                      setState(() => _fieldChecks[field] = val);
                    },
                  ),
                ),

                // Signature
                _buildSectionCard(
                  child: SignatureField(
                    points: (_signatureBase64 != null &&
                            _signatureBase64!.isNotEmpty)
                        ? []
                        : null,
                    label: "Digital Signature",
                    signatureImageBase64: _signatureBase64,
                    isChecked: false,
                    onCheckboxChanged: (_) {},
                    onCaptured: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_isEditMode)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 15,
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _cancelEdit,
                    child: const Text('Discard'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.buttonOutlineBlue),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Shared card wrapper (matches ManageFormsScreen style) ─────────────────────
  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Header button (matches ManageFormsScreen style) ────────────────────────────
  Widget _buildHeaderButton(String label, IconData icon,
      {VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: AppColors.primaryBlue),
      label: Text(label,
          style: const TextStyle(
              color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.buttonOutlineBlue),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
