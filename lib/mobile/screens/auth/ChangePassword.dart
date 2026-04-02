import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordScreen extends StatefulWidget {
  /// When true: came from ProfileScreen — no sign-out on success, pops back.
  /// When false (default): came from LoginScreen — signs out, goes to Login.
  final bool fromProfile;

  const ChangePasswordScreen({
    super.key,
    this.fromProfile = false,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final PageController _pageController = PageController();
  final SupabaseService _supabaseService = SupabaseService();

  int _currentPage = 0;
  bool _isLoading = false;
  bool _useEmail = true;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;

  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  String? _resolvedUserId;
  String? _resolvedEmail;

  @override
  void initState() {
    super.initState();
    for (var c in [
      _emailController,
      _phoneController,
      _otpController,
      _newPasswordController,
      _confirmPasswordController,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (var c in [
      _emailController,
      _phoneController,
      _otpController,
      _newPasswordController,
      _confirmPasswordController,
      _pageController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _getStepTitle() {
    switch (_currentPage) {
      case 0: return 'Step 1 of 3 — Identify Account';
      case 1: return 'Step 2 of 3 — Verify Identity';
      case 2: return 'Step 3 of 3 — New Password';
      default: return '';
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );

  void _goNext() => _pageController.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  void _goPrev() => _pageController.previousPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  bool _isPageValid() {
    switch (_currentPage) {
      case 0:
        return _useEmail
            ? _emailController.text.contains('@')
            : _phoneController.text.length >= 10;
      case 1:
        return _useEmail
            ? _otpController.text.length == 8
            : _otpController.text.length == 6;
      case 2:
        return _newPasswordController.text.length >= 6 &&
            _newPasswordController.text == _confirmPasswordController.text;
      default:
        return false;
    }
  }

  void _onNext() {
    switch (_currentPage) {
      case 0: _useEmail ? _handleSendEmailOtp() : _handleSendPhoneOtp(); break;
      case 1: _useEmail ? _handleVerifyEmailOtp() : _handleVerifyPhoneOtp(); break;
      case 2: _handleChangePassword(); break;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _handleSendEmailOtp() async {
    setState(() => _isLoading = true);
    try {
      final account = await Supabase.instance.client
          .from('user_accounts')
          .select('user_id, email, is_active')
          .eq('email', _emailController.text.trim())
          .maybeSingle();

      if (account == null) { _showError('No account found with that email.'); return; }
      if (account['is_active'] == false) { _showError('This account is deactivated.'); return; }

      _resolvedUserId = account['user_id'];
      _resolvedEmail = account['email'];

      await Supabase.instance.client.auth.signInWithOtp(
        email: _emailController.text.trim(),
        shouldCreateUser: false,
      );

      setState(() => _otpSent = true);
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
      await Supabase.instance.client.auth.signInWithOtp(
        email: _emailController.text.trim(),
        shouldCreateUser: false,
      );
      _showSuccess('Code resent! Check your email.');
    } catch (e) {
      _showError('Failed to resend: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyEmailOtp() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
        type: OtpType.email,
      );
      if (response.user == null) { _showError('Invalid or expired code.'); return; }
      _resolvedUserId = response.user!.id;
      _goNext();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Verification error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPhoneOtp() async {
    setState(() => _isLoading = true);
    try {
      final phoneRows = await Supabase.instance.client
          .from('user_field_values')
          .select('user_id, field_value')
          .eq('field_value', _phoneController.text.trim())
          .limit(1)
          .maybeSingle();

      if (phoneRows == null) { _showError('No account found with that phone number.'); return; }

      _resolvedUserId = phoneRows['user_id'];

      final account = await Supabase.instance.client
          .from('user_accounts')
          .select('email')
          .eq('user_id', _resolvedUserId!)
          .maybeSingle();
      _resolvedEmail = account?['email'];

      final result = await _supabaseService.sendPhoneOtp(_phoneController.text.trim());
      if (result['success']) {
        setState(() => _otpSent = true);
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
    final result = await _supabaseService.sendPhoneOtp(_phoneController.text.trim());
    if (mounted) {
      setState(() => _isLoading = false);
      result['success'] ? _showSuccess('Code resent!') : _showError(result['message']);
    }
  }

  Future<void> _handleVerifyPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyPhoneOtp(
      phone: _phoneController.text.trim(),
      otp: _otpController.text.trim(),
    );
    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success']) {
        if (_resolvedEmail != null) {
          try {
            await Supabase.instance.client.auth.signInWithOtp(
              email: _resolvedEmail!, shouldCreateUser: false,
            );
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
      final response = await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      if (response.user == null) {
        _showError('Failed to update password. Please try again.');
        return;
      }

      if (widget.fromProfile) {
        // ── From ProfileScreen: pop back, snackbar shown there
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        // ── From LoginScreen: sign out → show dialog → go to Login
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

  // ── Build ─────────────────────────────────────────────────────────────────

  Future<bool> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel password reset?'),
        content: const Text('Going back will cancel the process. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

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
        resizeToAvoidBottomInset: false,
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
          title: Text(_getStepTitle(),
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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

  // ── Pages ─────────────────────────────────────────────────────────────────

  Widget _buildIdentifyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reset Password',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Verify your identity to reset your password.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
            ),
            child: Row(
              children: [
                _buildToggleTab(label: 'Email', icon: Icons.email_outlined, selected: _useEmail,
                    onTap: () => setState(() { _useEmail = true; _otpController.clear(); })),
                _buildToggleTab(label: 'Phone', icon: Icons.phone_android_outlined, selected: !_useEmail,
                    onTap: () => setState(() { _useEmail = false; _otpController.clear(); })),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_useEmail) ...[
            const Text('Enter your registered email address.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: 'Email Address',
              controller: _emailController,
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.white),
            ),
          ] else ...[
            const Text('Enter your registered phone number.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: '09XXXXXXXXX',
              controller: _phoneController,
              prefixIcon: const Icon(Icons.phone_android_outlined, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleTab({
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
            color: selected ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpPage() {
    final destination = _useEmail ? _emailController.text : _phoneController.text;
    final digitCount = _useEmail ? '8-digit' : '6-digit';
    final icon = _useEmail ? Icons.mark_email_read : Icons.sms_outlined;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          Text(_useEmail ? 'Check Your Email' : 'Check Your Phone',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('A $digitCount code was sent to\n$destination',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 30),
          CustomTextField(hintText: 'Enter $digitCount code', controller: _otpController),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isLoading ? null : () => _useEmail ? _handleResendEmailOtp() : _handleResendPhoneOtp(),
            child: const Text('Resend Code', style: TextStyle(color: Colors.white60, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordPage() {
    final passwordsMatch = _newPasswordController.text.isNotEmpty &&
        _newPasswordController.text == _confirmPasswordController.text;
    final tooShort = _newPasswordController.text.isNotEmpty &&
        _newPasswordController.text.length < 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('New Password',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Choose a strong password for your account.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          CustomTextField(
            hintText: 'New Password (min. 6 characters)',
            controller: _newPasswordController,
            obscureText: !_showNewPassword,
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white),
            suffixIcon: IconButton(
              icon: Icon(
                _showNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white60, size: 20,
              ),
              onPressed: () => setState(() => _showNewPassword = !_showNewPassword),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 12),

          CustomTextField(
            hintText: 'Confirm New Password',
            controller: _confirmPasswordController,
            obscureText: !_showConfirmPassword,
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white),
            suffixIcon: IconButton(
              icon: Icon(
                _showConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white60, size: 20,
              ),
              onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
            ),
          ),
          if (_confirmPasswordController.text.isNotEmpty && !passwordsMatch) ...[
            const SizedBox(height: 4),
            const Text('Passwords do not match.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (_confirmPasswordController.text.isNotEmpty && passwordsMatch) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 14),
                SizedBox(width: 4),
                Text('Passwords match!', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final bool valid = _isPageValid();
    final String label = switch (_currentPage) {
      0 => 'Send Code',
      1 => 'Verify',
      2 => 'Change Password',
      _ => 'Next',
    };

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          if (_isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: label,
              onPressed: valid ? _onNext : () {},
              backgroundColor: valid ? AppColors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 10),
          if (_currentPage > 0)
            TextButton(
              onPressed: _goPrev,
              child: const Text('Back', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}

// ── Success Dialog (only shown when fromProfile = false) ──────────────────

class _PasswordChangedDialog extends StatelessWidget {
  const _PasswordChangedDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 70),
          const SizedBox(height: 16),
          const Text('Password Changed!',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Your password has been updated successfully. Please log in with your new password.',
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back to Login', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}