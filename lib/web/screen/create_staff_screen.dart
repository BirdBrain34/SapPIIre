// lib/web/screen/create_staff_screen.dart
// Dedicated screen for superadmin to create new staff accounts

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/auth/staff_admin_service.dart';
import 'package:sappiire/services/email/staff_email_service.dart';
import 'package:sappiire/web/utils/page_transitions.dart';

class CreateStaffScreen extends StatefulWidget {
  final String role;
  final String cswd_id;
  final String displayName;

  const CreateStaffScreen({
    super.key,
    required this.role,
    required this.cswd_id,
    this.displayName = '',
  });

  @override
  State<CreateStaffScreen> createState() => _CreateStaffScreenState();
}

class _CreateStaffScreenState extends State<CreateStaffScreen> {
  final _staffAdminService = StaffAdminService();
  static const String _fixedRole = 'admin';

  // Account creation form controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isCreatingAccount = false;

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.dangerRed : AppColors.successGreen,
      ),
    );
  }

  void _clearCreateForm() {
    _firstNameController.clear();
    _lastNameController.clear();
    _emailController.clear();
    _positionController.clear();
    _departmentController.clear();
    _phoneController.clear();
  }

  bool _isValidEmail(String email) {
    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return pattern.hasMatch(email);
  }

  InputDecoration _inputDecoration(String label, {bool required = false}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.highlight),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _createStaffAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final position = _positionController.text.trim();
    final department = _departmentController.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        position.isEmpty ||
        department.isEmpty) {
      _showSnackBar(
        'Please fill in all required fields, including position and department.',
        isError: true,
      );
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnackBar('Enter a valid email address.', isError: true);
      return;
    }

    setState(() => _isCreatingAccount = true);

    try {
      if (_fixedRole != 'admin') {
        _showSnackBar('Invalid role policy. Contact developer.', isError: true);
        setState(() => _isCreatingAccount = false);
        return;
      }

      final createResult = await _staffAdminService.createAdminStaffAccount(
        email: email,
        firstName: firstName,
        lastName: lastName,
        position: position,
        department: department,
        phoneNumber: _phoneController.text,
      );

      if (createResult['success'] != true) {
        _showSnackBar(
          createResult['message']?.toString() ?? 'Failed to create account.',
          isError: true,
        );
        setState(() => _isCreatingAccount = false);
        return;
      }

      final String? cswdId = createResult['cswd_id']?.toString();
      final String? generatedUsername = createResult['username']?.toString();

      if (cswdId == null || cswdId.isEmpty) {
        _showSnackBar(
          'Account created but failed to get ID. Contact developer.',
          isError: true,
        );
        setState(() => _isCreatingAccount = false);
        return;
      }

      if (generatedUsername == null || generatedUsername.isEmpty) {
        _showSnackBar(
          'Account created but failed to get username. Contact developer.',
          isError: true,
        );
        setState(() => _isCreatingAccount = false);
        return;
      }

      final emailResult = await StaffEmailService().sendAccountCreationOtp(
        email: email,
      );

      await AuditLogService().log(
        actionType: kAuditStaffCreated,
        category: kCategoryStaff,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'staff_account',
        targetId: cswdId,
        targetLabel: generatedUsername,
        details: {
          'username': generatedUsername,
          'role': _fixedRole,
          'email': email,
        },
      );

      if (!mounted) return;

      if (emailResult['success'] == true) {
        _showSnackBar(
          'Admin account created. OTP sent. Staff should use New staff setup to verify OTP and set password.',
        );
      } else {
        _showSnackBar(
          'Admin account created, but OTP email failed: ${emailResult['message'] ?? 'Unknown error'}',
          isError: true,
        );
      }

      _clearCreateForm();
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isCreatingAccount = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'CreateStaff',
      pageTitle: 'Create Staff Account',
      pageSubtitle: 'Add a new team member to the system',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > 860
                  ? 860.0
                  : constraints.maxWidth;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.highlight.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: AppColors.highlight,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create Staff Account',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'All accounts created here are provisioned with admin access.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.highlight.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.highlight.withOpacity(0.25),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                                color: AppColors.highlight,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Access Role: Admin only',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.pageBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Account Identity',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Username is auto-generated from first and last name. Email is used for login and OTP delivery.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _firstNameController,
                                      decoration: _inputDecoration(
                                        'First Name',
                                        required: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _lastNameController,
                                      decoration: _inputDecoration(
                                        'Last Name',
                                        required: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: _inputDecoration(
                                        'Email Address',
                                        required: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.pageBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profile Details',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Required profile fields for staff records.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _positionController,
                                      decoration: _inputDecoration(
                                        'Position',
                                        required: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _departmentController,
                                      decoration: _inputDecoration(
                                        'Department',
                                        required: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: _inputDecoration('Phone Number'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FBFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.mail_outline_rounded,
                                    size: 18,
                                    color: AppColors.highlight,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'After Account Creation',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '1) Supabase sends an OTP email to the staff address.\n'
                                '2) Staff opens New staff setup from login.\n'
                                '3) Staff verifies OTP and sets their own password.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.highlight,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isCreatingAccount
                                ? null
                                : _createStaffAccount,
                            child: _isCreatingAccount
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'CREATE ADMIN ACCOUNT',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '* Required fields',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
          onLogout: () => Navigator.pop(context),
        );
        break;
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
