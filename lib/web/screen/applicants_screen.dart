import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

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
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _applicants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApplicants();
  }

  Future<void> _loadApplicants() async {
    setState(() => _isLoading = true);
    try {
      final submissions = await _supabase
          .from('client_submissions')
          .select('id, form_type, data, created_at, last_edited_by, last_edited_at')
          .order('created_at', ascending: false);

      setState(() {
        _applicants = List<Map<String, dynamic>>.from(submissions);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load applicants error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading applicants: $e')),
        );
      }
    }
  }

  String _extractApplicantName(Map<String, dynamic> data) {
    final firstName = data['First Name'] ?? '';
    final lastName = data['Last Name'] ?? '';
    return '$firstName $lastName'.trim();
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _deleteApplicant(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Applicant'),
        content: const Text('Are you sure you want to delete this applicant form? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        debugPrint('Attempting to delete applicant with id: $id');
        
        final response = await _supabase
            .from('client_submissions')
            .delete()
            .eq('id', id);

        debugPrint('Delete response: $response');
        
        // Forcefully refresh after deletion
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          setState(() => _isLoading = true);
          await _loadApplicants();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Applicant deleted successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Delete error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting applicant: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _viewApplicant(Map<String, dynamic> applicant) {
    Navigator.of(context).pushReplacement(
      ContentFadeRoute(
        page: ViewApplicantScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          applicantId: applicant['id'],
          applicantData: Map<String, dynamic>.from(applicant['data'] ?? {}),
          formType: applicant['form_type'] ?? 'General Intake Sheet',
        ),
      ),
    );
  }

  void _editApplicant(Map<String, dynamic> applicant) {
    Navigator.of(context).pushReplacement(
      ContentFadeRoute(
        page: EditApplicantScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          applicantId: applicant['id'],
          applicantData: Map<String, dynamic>.from(applicant['data'] ?? {}),
          formType: applicant['form_type'] ?? 'General Intake Sheet',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'Applicants',
      pageSubtitle: 'View and manage submitted forms',
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      headerActions: [
        ElevatedButton.icon(
          onPressed: _loadApplicants,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            foregroundColor: Colors.white,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _applicants.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined,
                            size: 64, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'No applicants found',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _applicants.length,
                    itemBuilder: (ctx, idx) {
                      final applicant = _applicants[idx];
                      final data = applicant['data'] ?? {};
                      final name = _extractApplicantName(data);
                      final formType = applicant['form_type'] ?? 'Unknown';
                      final submitDate = _formatDate(applicant['created_at'] ?? '');
                      final lastEditedBy = applicant['last_edited_by'] ?? 'None';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              // Applicant info
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _viewApplicant(applicant),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isNotEmpty ? name : 'Unknown Applicant',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.highlight,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Form: $formType',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            'Submitted: $submitDate',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            'Last Edited: $lastEditedBy',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.highlight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),                                ),                              ),
                              const SizedBox(width: 20),
                              // Action buttons
                              SizedBox(
                                width: 180,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () => _editApplicant(applicant),
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.highlight,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _deleteApplicant(applicant['id']),
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Delete'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          onLogout: () => Navigator.pop(context),
        );
        break;
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
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }
}

// ============================================================================
// View Applicant Screen (Read-Only Display)
// ============================================================================

class ViewApplicantScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final dynamic applicantId;
  final Map<String, dynamic> applicantData;
  final String formType;

  const ViewApplicantScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.applicantId,
    required this.applicantData,
    required this.formType,
  });

  @override
  State<ViewApplicantScreen> createState() => _ViewApplicantScreenState();
}

class _ViewApplicantScreenState extends State<ViewApplicantScreen> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'View Applicant',
      pageSubtitle: 'Review applicant submitted information',
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    ContentFadeRoute(
                      page: ApplicantsScreen(
                        cswd_id: widget.cswd_id,
                        role: widget.role,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Applicants'),
                ),
              ),
              // Form Title
              Text(
                '${widget.applicantData['First Name'] ?? ''} ${widget.applicantData['Last Name'] ?? ''}'
                    .trim(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Form Type: ${widget.formType}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              // Form fields in a grid
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  // Regular text fields
                  ...widget.applicantData.entries
                      .where((entry) => !entry.key.startsWith('__'))
                      .map((entry) {
                    final key = entry.key;
                    final value = entry.value;

                    return SizedBox(
                      width: 300,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              key,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              value?.toString() ?? '(No data)',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  // Signature display
                  if (widget.applicantData.containsKey('__signature') &&
                      widget.applicantData['__signature'] != null &&
                      (widget.applicantData['__signature'] as String).isNotEmpty)
                    SizedBox(
                      width: 350,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.highlight, width: 2),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Digital Signature',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.highlight,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              height: 150,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.cardBorder),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.grey[100],
                              ),
                              child: Image.memory(
                                _base64ToBytes(widget.applicantData['__signature'] as String),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      'Could not display signature',
                                      style: TextStyle(color: Colors.red[400]),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 40),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      ContentFadeRoute(
                        page: ApplicantsScreen(
                          cswd_id: widget.cswd_id,
                          role: widget.role,
                        ),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _navigateToEdit(),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Form'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.highlight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToEdit() {
    Navigator.of(context).pushReplacement(
      ContentFadeRoute(
        page: EditApplicantScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          applicantId: widget.applicantId,
          applicantData: widget.applicantData,
          formType: widget.formType,
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          onLogout: () => Navigator.pop(context),
        );
        break;
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
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }

  Uint8List _base64ToBytes(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (e) {
      debugPrint('Error decoding base64: $e');
      return Uint8List(0);
    }
  }
}

// ============================================================================
// Edit Applicant Screen
// ============================================================================

class EditApplicantScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final dynamic applicantId;
  final Map<String, dynamic> applicantData;
  final String formType;

  const EditApplicantScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.applicantId,
    required this.applicantData,
    required this.formType,
  });

  @override
  State<EditApplicantScreen> createState() => _EditApplicantScreenState();
}

class _EditApplicantScreenState extends State<EditApplicantScreen> {
  final _supabase = Supabase.instance.client;
  late Map<String, TextEditingController> _controllers;
  late Map<String, String> _radioValues;
  bool _isSaving = false;

  // Radio button options for specific fields
  static const Map<String, List<String>> radioOptions = {
    'Kasarian': ['Male', 'Female', 'Other'],
    'Estadong Sibil': ['Single', 'Married', 'Widowed', 'Divorced', 'Separated', 'Live-in'],
    'Relihiyon': ['Catholic', 'Protestant', 'Muslim', 'Buddhist', 'Atheist', 'Other'],
  };

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeRadioValues();
  }

  void _initializeRadioValues() {
    _radioValues = {};
    for (var field in radioOptions.keys) {
      _radioValues[field] = widget.applicantData[field] ?? '';
    }
  }

  void _initializeControllers() {
    _controllers = {};
    // Initialize controllers for all possible fields
    final allLabels = [
      "Last Name", "First Name", "Middle Name", "Date of Birth", "Age",
      "House number, street name, phase/purok", "Subdivision", "Barangay",
      "Kasarian", "Estadong Sibil", "Relihiyon", "CP Number", "Email Address",
      "Natapos o naabot sa pag-aaral", "Lugar ng Kapanganakan",
      "Trabaho/Pinagkakakitaan", "Kumpanyang Pinagtratrabuhan",
      "Buwanang Kita (A)", "Total Gross Family Income (A+B+C)=(D)",
      "Household Size (E)", "Monthly Per Capita Income (D/E)",
      "Total Monthly Expense (F)", "Net Monthly Income (D-F)",
      "Bayad sa bahay", "Food items", "Non-food items", "Utility bills",
      "Baby's needs", "School needs", "Medical needs", "Transpo expense",
      "Loans", "Gasul", "Kabuuang Tulong/Sustento kada Buwan (C)"
    ];

    for (var label in allLabels) {
      if (!radioOptions.containsKey(label)) {
        _controllers[label] = TextEditingController(
          text: widget.applicantData[label] ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final updatedData = <String, String>{};
    _controllers.forEach((key, controller) {
      updatedData[key] = controller.text;
    });
    
    // Include radio button values
    for (var field in _radioValues.keys) {
      updatedData[field] = _radioValues[field]!;
    }

    try {
      await _supabase
          .from('client_submissions')
          .update({
            'data': updatedData,
            'last_edited_at': DateTime.now().toIso8601String(),
            'last_edited_by': widget.cswd_id,
          })
          .eq('id', widget.applicantId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes saved successfully!')),
        );
        Navigator.of(context).pushReplacement(
          ContentFadeRoute(
            page: ApplicantsScreen(
              cswd_id: widget.cswd_id,
              role: widget.role,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Applicants',
      pageTitle: 'Edit Applicant',
      pageSubtitle: 'Update applicant information',
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    ContentFadeRoute(
                      page: ApplicantsScreen(
                        cswd_id: widget.cswd_id,
                        role: widget.role,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Applicants'),
                ),
              ),
              // Form Title
              Text(
                '${widget.applicantData['First Name'] ?? ''} ${widget.applicantData['Last Name'] ?? ''}'
                    .trim(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Form Type: ${widget.formType}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              // Form fields in a grid
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  // Text input fields
                  ..._controllers.entries.map((entry) {
                    return SizedBox(
                      width: 300,
                      child: TextField(
                        controller: entry.value,
                        decoration: InputDecoration(
                          labelText: entry.key,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    );
                  }).toList(),
                  // Radio button fields
                  ..._radioValues.entries.map((entry) {
                    final field = entry.key;
                    final currentValue = entry.value;
                    final options = radioOptions[field] ?? [];

                    return SizedBox(
                      width: 320,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...options.map((option) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: option,
                                      groupValue: currentValue,
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _radioValues[field] = val;
                                          });
                                        }
                                      },
                                    ),
                                    Text(option),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
              const SizedBox(height: 40),
              // Save button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      ContentFadeRoute(
                        page: ApplicantsScreen(
                          cswd_id: widget.cswd_id,
                          role: widget.role,
                        ),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveChanges,
                    icon: const Icon(Icons.save),
                    label: _isSaving
                        ? const Text('Saving...')
                        : const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.highlight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          onLogout: () => Navigator.pop(context),
        );
        break;
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
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }
}
