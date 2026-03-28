// First-time setup for newly created staff accounts.
// Uses the OTP sent at account creation time and does not auto-send a new code.

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/services/staff_email_service.dart';
import 'package:sappiire/web/services/web_auth_service.dart';
import 'package:sappiire/web/services/audit_log_service.dart';

class NewStaffSetupScreen extends StatefulWidget {
  const NewStaffSetupScreen({super.key});

  @override
  State<NewStaffSetupScreen> createState() => _NewStaffSetupScreenState();
}

class _NewStaffSetupScreenState extends State<NewStaffSetupScreen> {
  final _emailService = StaffEmailService();
  final _authService = WebAuthService();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _step = 1;
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _infoMessage;
  String? _verifiedCswdId;

  final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final RegExp _otpRegex = RegExp(r'^\d{6,8}$');

  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUppercase =>
      _newPasswordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _passwordsMatch =>
      _newPasswordController.text == _confirmPasswordController.text &&
      _newPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleContinueFromEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address.');
      return;
    }

    if (!_emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await _emailService.validatePendingSetupEmail(email: email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      setState(() {
        _step = 2;
        _infoMessage =
            'Enter the original OTP sent when your account was created.';
      });
    } else {
      setState(() => _errorMessage = result['message']?.toString());
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (!_otpRegex.hasMatch(_otpController.text.trim())) {
      setState(() => _errorMessage = 'Enter the OTP code from your email (6 to 8 digits).');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await _emailService.verifyPendingSetupOtp(
      email: _emailController.text.trim(),
      otp: _otpController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      _verifiedCswdId = result['cswd_id']?.toString();
      setState(() => _step = 3);
    } else {
      setState(() => _errorMessage = result['message']?.toString());
    }
  }

  Future<void> _handleSetPassword() async {
    if (!_hasMinLength) {
      setState(() => _errorMessage = 'Password must be at least 8 characters.');
      return;
    }
    if (!_passwordsMatch) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }
    if (_verifiedCswdId == null) {
      setState(() => _errorMessage = 'Session expired. Please start over.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await _authService.resetPasswordWithOtp(
      cswd_id: _verifiedCswdId!,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await AuditLogService().log(
        actionType: kAuditPasswordChanged,
        category: kCategoryAuth,
        severity: kSeverityInfo,
        actorId: _verifiedCswdId,
        details: {'initiated_by': 'new_staff_setup'},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Setup complete. You can now log in.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B4E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text(
          'New Staff Setup',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF152257),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: 28),
              if (_step == 1) _buildStep1(),
              if (_step == 2) _buildStep2(),
              if (_step == 3) _buildStep3(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.dangerRed.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppColors.dangerRed,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (_infoMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.successGreen.withOpacity(0.45),
                    ),
                  ),
                  child: Text(
                    _infoMessage!,
                    style: const TextStyle(
                      color: AppColors.successGreen,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['Email', 'Verify OTP', 'Set Password'];
    return Row(
      children: List.generate(steps.length, (i) {
        final stepNum = i + 1;
        final isActive = _step == stepNum;
        final isDone = _step > stepNum;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.successGreen
                            : isActive
                                ? AppColors.highlight
                                : Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : Text(
                                '$stepNum',
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive ? Colors.white : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: _step > stepNum
                        ? AppColors.successGreen
                        : Colors.white12,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter the same email used by the superadmin when creating your account.',
          style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use the original OTP sent during account creation.',
          style: TextStyle(color: Color(0xFF8BAEE0), fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 20),
        _styledField(
          controller: _emailController,
          hint: 'name@cswd.gov.ph',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _isLoading ? null : _handleContinueFromEmail(),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the OTP code sent to\n${_emailController.text.trim()}',
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 20),
        _styledField(
          controller: _otpController,
          hint: 'Enter code',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _isLoading ? null : _handleVerifyOtp(),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isLoading
              ? null
              : () async {
                  final result = await _emailService.sendAccountCreationOtp(
                    email: _emailController.text.trim(),
                  );
                  if (!mounted) return;
                  setState(() {
                    if (result['success'] == true) {
                      _infoMessage = 'A new OTP was sent to your email.';
                      _errorMessage = null;
                    } else {
                      _errorMessage = result['message']?.toString();
                    }
                  });
                },
          child: const Text(
            'Resend OTP',
            style: TextStyle(color: Color(0xFF6EA8FE), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set your password',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 20),
        _passwordField(
          controller: _newPasswordController,
          hint: 'New password',
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _passwordField(
          controller: _confirmPasswordController,
          hint: 'Confirm new password',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _requirementRow('8+ characters', _hasMinLength),
        const SizedBox(height: 4),
        _requirementRow('Uppercase letter', _hasUppercase),
        const SizedBox(height: 4),
        _requirementRow('Contains a number', _hasNumber),
      ],
    );
  }

  Widget _buildActionButton() {
    final labels = ['Continue', 'Verify OTP', 'Set Password'];
    final actions = [
      _handleContinueFromEmail,
      _handleVerifyOtp,
      _handleSetPassword,
    ];

    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : actions[_step - 1],
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.highlight,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                labels[_step - 1],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B4E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3F7A), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A6499), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF6EA8FE), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B4E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3F7A), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A6499), fontSize: 13),
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color(0xFF6EA8FE),
              size: 18,
            ),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _requirementRow(String label, bool met) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: met ? AppColors.successGreen : Colors.white38,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: met ? AppColors.successGreen : Colors.white54,
          ),
        ),
      ],
    );
  }
}
