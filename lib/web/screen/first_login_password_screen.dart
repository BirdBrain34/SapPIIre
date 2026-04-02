// Shown immediately after first login.
// User must set a new password before reaching the dashboard.
// No back navigation - the only exit is setting a valid password.

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';

class FirstLoginPasswordScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;
  final String username;

  const FirstLoginPasswordScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.displayName,
    required this.username,
  });

  @override
  State<FirstLoginPasswordScreen> createState() =>
      _FirstLoginPasswordScreenState();
}

class _FirstLoginPasswordScreenState extends State<FirstLoginPasswordScreen> {
  final _authService = WebAuthService();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUppercase =>
      _newPasswordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _passwordsMatch =>
      _newPasswordController.text == _confirmPasswordController.text &&
      _newPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSetPassword() async {
    setState(() => _errorMessage = null);

    if (_newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill in both fields.');
      return;
    }
    if (!_hasMinLength) {
      setState(() => _errorMessage = 'Password must be at least 8 characters.');
      return;
    }
    if (!_passwordsMatch) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.resetPasswordWithOtp(
      cswd_id: widget.cswd_id,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _authService.clearFirstLoginFlag(widget.cswd_id);

      await AuditLogService().log(
        actionType: kAuditPasswordChanged,
        category: kCategoryAuth,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'staff_account',
        targetId: widget.cswd_id,
        details: {'initiated_by': 'first_login_forced_reset'},
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(
          page: ManageFormsScreen(
            cswd_id: widget.cswd_id,
            role: widget.role,
            displayName: widget.displayName,
          ),
        ),
        (route) => false,
      );
      return;
    }

    setState(() {
      _errorMessage = result['message'] ?? 'Failed to set password.';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B4E),
        body: Center(
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF152257),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: AppColors.highlight,
                    size: 32,
                  ),
                ),
                const Text(
                  'Set Your Password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome, ${widget.displayName.isNotEmpty ? widget.displayName : widget.username}. '
                  'You must set a new password before accessing the portal.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Password requirements',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _requirementRow('At least 8 characters', _hasMinLength),
                      const SizedBox(height: 4),
                      _requirementRow(
                        'Contains an uppercase letter',
                        _hasUppercase,
                      ),
                      const SizedBox(height: 4),
                      _requirementRow('Contains a number', _hasNumber),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
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
                _fieldLabel('New Password'),
                const SizedBox(height: 8),
                _passwordField(
                  controller: _newPasswordController,
                  hint: 'Enter your new password',
                  obscure: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                _fieldLabel('Confirm Password'),
                const SizedBox(height: 8),
                _passwordField(
                  controller: _confirmPasswordController,
                  hint: 'Re-enter your new password',
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  onChanged: (_) => setState(() {}),
                ),
                if (_confirmPasswordController.text.isNotEmpty &&
                    !_passwordsMatch) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Passwords do not match',
                    style: TextStyle(color: AppColors.dangerRed, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSetPassword,
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
                        : const Text(
                            'Set Password & Enter Portal',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
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
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: met ? AppColors.successGreen : Colors.white54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFB8CCF0),
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );

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
}
