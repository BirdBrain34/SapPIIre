import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/auth/password_reset_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordScreen extends StatefulWidget {
  /// When true: came from ProfileScreen — no sign-out on success, pops back.
  /// When false (default): came from LoginScreen — signs out, goes to Login.
  final bool fromProfile;

  const ChangePasswordScreen({super.key, this.fromProfile = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _pageController = PageController();
  final _passwordResetService = PasswordResetService();

  int _currentPage = 0;
  bool _isLoading = false;
  bool _useEmail = true;

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  String? _resolvedEmail;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _emailCtrl, _phoneCtrl, _otpCtrl,
      _newPasswordCtrl, _confirmPasswordCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _emailCtrl, _phoneCtrl, _otpCtrl,
      _newPasswordCtrl, _confirmPasswordCtrl, _pageController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _stepTitle => switch (_currentPage) {
    0 => 'Step 1 of 3 — Identify Account',
    1 => 'Step 2 of 3 — Verify Identity',
    _ => 'Step 3 of 3 — New Password',
  };

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green));

  void _goNext() => _pageController.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  void _goPrev() => _pageController.previousPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  bool get _pageValid => switch (_currentPage) {
    0 => _useEmail
        ? _emailCtrl.text.contains('@')
        : _phoneCtrl.text.length >= 10,
    1 => _useEmail
        ? _otpCtrl.text.length == 8
        : _otpCtrl.text.length == 6,
    _ => _newPasswordCtrl.text.length >= 6 &&
        _newPasswordCtrl.text == _confirmPasswordCtrl.text,
  };

  void _onNext() {
    switch (_currentPage) {
      case 0:
        _useEmail ? _handleSendEmailOtp() : _handleSendPhoneOtp();
        break;
      case 1:
        _useEmail ? _handleVerifyEmailOtp() : _handleVerifyPhoneOtp();
        break;
      case 2:
        _handleChangePassword();
        break;
    }
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _handleSendEmailOtp() async {
    setState(() => _isLoading = true);
    try {
      final result =
          await _passwordResetService.sendEmailOtp(_emailCtrl.text);
      if (result['success'] != true) {
        _showError(result['message']?.toString() ?? 'Failed to send OTP.');
        return;
      }
      _resolvedEmail = result['email']?.toString();
      _goNext();
    } catch (e) {
      _showError('Failed to send OTP: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResendEmailOtp() async {
    setState(() => _isLoading = true);
    try {
      final result = await _passwordResetService.resendEmailOtp(
          _emailCtrl.text);
      if (result['success'] == true) {
        _showSuccess(result['message']?.toString() ??
            'Code resent! Check your email.');
      } else {
        _showError(
            result['message']?.toString() ?? 'Failed to resend OTP.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyEmailOtp() async {
    setState(() => _isLoading = true);
    try {
      final result = await _passwordResetService.verifyEmailOtp(
        email: _emailCtrl.text,
        otp: _otpCtrl.text,
      );
      if (result['success'] != true) {
        _showError(
            result['message']?.toString() ?? 'Invalid or expired code.');
        return;
      }
      _goNext();
    } catch (e) {
      _showError('Verification error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPhoneOtp() async {
    setState(() => _isLoading = true);
    try {
      final result =
          await _passwordResetService.sendPhoneOtp(_phoneCtrl.text);
      if (result['success']) {
        _resolvedEmail = result['email']?.toString();
        _goNext();
      } else {
        _showError(result['message']);
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResendPhoneOtp() async {
    setState(() => _isLoading = true);
    final result =
        await _passwordResetService.resendPhoneOtp(_phoneCtrl.text);
    if (mounted) {
      setState(() => _isLoading = false);
      result['success']
          ? _showSuccess('Code resent!')
          : _showError(result['message']);
    }
  }

  Future<void> _handleVerifyPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _passwordResetService.verifyPhoneOtp(
      phone: _phoneCtrl.text,
      otp: _otpCtrl.text,
    );
    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success']) {
        if (_resolvedEmail != null) {
          try {
            await _passwordResetService
                .bootstrapEmailOtpForResolvedEmail(_resolvedEmail);
          } catch (_) {}
        }
        _goNext();
      } else {
        _showError(result['message']);
      }
    }
  }

  Future<void> _handleChangePassword() async {
    setState(() => _isLoading = true);
    try {
      // updateCurrentUserPassword must call Supabase auth.updateUser
      final result = await _passwordResetService.updateCurrentUserPassword(
        _newPasswordCtrl.text,
      );

      if (result['success'] != true) {
        _showError(result['message']?.toString() ??
            'Failed to update password. Please try again.');
        return;
      }

      if (widget.fromProfile) {
        if (!mounted) return;
        _showSuccess('Password updated successfully!');
        Navigator.pop(context);
      } else {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _PasswordChangedDialog(),
        ).then((_) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel password reset?'),
        content: const Text(
            'Going back will cancel the process. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage == 0) { Navigator.pop(context); return; }
        if (await _confirmCancel() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryBlue,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_currentPage > 0) {
                if (await _confirmCancel() && mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_stepTitle,
              style:
                  const TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 8),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / 3,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (p) => setState(() => _currentPage = p),
                  children: [
                    _buildIdentifyPage(),
                    _buildOtpPage(),
                    _buildNewPasswordPage(),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pages ─────────────────────────────────────────────────

  Widget _buildIdentifyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reset Password',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Verify your identity to reset your password.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          // Toggle: Email / Phone
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
            ),
            child: Row(
              children: [
                _toggleTab(
                  label: 'Email',
                  icon: Icons.email_outlined,
                  selected: _useEmail,
                  onTap: () => setState(() {
                    _useEmail = true;
                    _otpCtrl.clear();
                  }),
                ),
                _toggleTab(
                  label: 'Phone',
                  icon: Icons.phone_android_outlined,
                  selected: !_useEmail,
                  onTap: () => setState(() {
                    _useEmail = false;
                    _otpCtrl.clear();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_useEmail) ...[
            const Text('Enter your registered email address.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            _CpField(
              controller: _emailCtrl,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
          ] else ...[
            const Text('Enter your registered phone number.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            _CpField(
              controller: _phoneCtrl,
              label: '09XXXXXXXXX',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggleTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected ? Colors.white : Colors.white54,
                  size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 14,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpPage() {
    final destination =
        _useEmail ? _emailCtrl.text : _phoneCtrl.text;
    final digitCount = _useEmail ? '8-digit' : '6-digit';
    final icon = _useEmail
        ? Icons.mark_email_read
        : Icons.sms_outlined;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          Text(
            _useEmail ? 'Check Your Email' : 'Check Your Phone',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'A $digitCount code was sent to\n$destination',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 30),
          _CpField(
            controller: _otpCtrl,
            label: 'Enter $digitCount code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => _useEmail
                    ? _handleResendEmailOtp()
                    : _handleResendPhoneOtp(),
            child: const Text('Resend Code',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordPage() {
    final match = _newPasswordCtrl.text.isNotEmpty &&
        _newPasswordCtrl.text == _confirmPasswordCtrl.text;
    final tooShort = _newPasswordCtrl.text.isNotEmpty &&
        _newPasswordCtrl.text.length < 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('New Password',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Choose a strong password for your account.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          _CpField(
            controller: _newPasswordCtrl,
            label: 'New Password (min. 6 characters)',
            icon: Icons.lock_outline,
            obscureText: !_showNewPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _showNewPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white60,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _showNewPassword = !_showNewPassword),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.',
                style: TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 14),

          _CpField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm New Password',
            icon: Icons.lock_outline,
            obscureText: !_showConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _showConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white60,
                size: 20,
              ),
              onPressed: () => setState(
                  () => _showConfirmPassword = !_showConfirmPassword),
            ),
          ),
          if (_confirmPasswordCtrl.text.isNotEmpty && !match) ...[
            const SizedBox(height: 4),
            const Text('Passwords do not match.',
                style: TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (_confirmPasswordCtrl.text.isNotEmpty && match) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.greenAccent, size: 14),
                SizedBox(width: 4),
                Text('Passwords match!',
                    style: TextStyle(
                        color: Colors.greenAccent, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final label = switch (_currentPage) {
      0 => 'Send Code',
      1 => 'Verify',
      _ => 'Change Password',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          if (_isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: label,
              onPressed: _pageValid ? _onNext : () {},
              backgroundColor:
                  _pageValid ? AppColors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 8),
          if (_currentPage > 0)
            TextButton(
              onPressed: _goPrev,
              child: const Text('Back',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}

// ── Reusable field for ChangePassword (same floating label style) ─────────────

class _CpField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  const _CpField({
    required this.controller,
    required this.label,
    this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Colors.white60, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: AppColors.lightBlue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: icon != null
            ? Icon(icon, color: AppColors.lightBlue, size: 20)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.inputBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.lightBlue, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ── Success Dialog ────────────────────────────────────────────────────────────

class _PasswordChangedDialog extends StatelessWidget {
  const _PasswordChangedDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.primaryBlue,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.check_circle_outline,
              color: Colors.white, size: 70),
          const SizedBox(height: 16),
          const Text(
            'Password Changed!',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your password has been updated successfully. '
            'Please log in with your new password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back to Login',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}