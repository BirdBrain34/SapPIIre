import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/change_password_controller.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/cp_text_field.dart';
import 'package:sappiire/mobile/widgets/password_changed_dialog.dart';

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
  late final ChangePasswordController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChangePasswordController();
    _controller.addListener(() => setState(() {}));
    for (final c in [
      _controller.emailCtrl, _controller.phoneCtrl, _controller.otpCtrl,
      _controller.newPasswordCtrl, _controller.confirmPasswordCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() => _controller.goNext(_pageController);
  void _goPrev() => _controller.goPrev(_pageController);

  Future<void> _onNext() async {
    bool success = false;
    switch (_controller.currentPage) {
      case 0:
        success = _controller.useEmail
            ? await _controller.handleSendEmailOtp(context)
            : await _controller.handleSendPhoneOtp(context);
        break;
      case 1:
        success = _controller.useEmail
            ? await _controller.handleVerifyEmailOtp(context)
            : await _controller.handleVerifyPhoneOtp(context);
        break;
      case 2:
        success = await _controller.handleChangePassword(
          context,
          fromProfile: widget.fromProfile,
        );
        if (success && !widget.fromProfile) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const PasswordChangedDialog(),
          ).then((_) {
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          });
          return;
        }
        if (success && widget.fromProfile && mounted) {
          Navigator.pop(context);
          return;
        }
        return;
    }
    if (success) _goNext();
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_controller.currentPage == 0) { Navigator.pop(context); return; }
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
              if (_controller.currentPage > 0) {
                if (await _confirmCancel() && mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_controller.stepTitle,
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
                  value: (_controller.currentPage + 1) / 3,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (p) => _controller.setPage(p),
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
                  selected: _controller.useEmail,
                  onTap: () => setState(() {
                    _controller.useEmail = true;
                    _controller.otpCtrl.clear();
                  }),
                ),
                _toggleTab(
                  label: 'Phone',
                  icon: Icons.phone_android_outlined,
                  selected: !_controller.useEmail,
                  onTap: () => setState(() {
                    _controller.useEmail = false;
                    _controller.otpCtrl.clear();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_controller.useEmail) ...[
            const Text('Enter your registered email address.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            CpTextField(
              controller: _controller.emailCtrl,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
          ] else ...[
            const Text('Enter your registered phone number.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            CpTextField(
              controller: _controller.phoneCtrl,
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
        _controller.useEmail ? _controller.emailCtrl.text : _controller.phoneCtrl.text;
    final digitCount = _controller.useEmail ? '8-digit' : '6-digit';
    final icon = _controller.useEmail
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
            _controller.useEmail ? 'Check Your Email' : 'Check Your Phone',
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
          CpTextField(
            controller: _controller.otpCtrl,
            label: 'Enter $digitCount code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _controller.isLoading
                ? null
                : () => _controller.useEmail
                    ? _controller.handleResendEmailOtp(context)
                    : _controller.handleResendPhoneOtp(context),
            child: const Text('Resend Code',
                style: TextStyle(
                    color: Colors.white60, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordPage() {
    final match = _controller.newPasswordCtrl.text.isNotEmpty &&
        _controller.newPasswordCtrl.text == _controller.confirmPasswordCtrl.text;
    final tooShort = _controller.newPasswordCtrl.text.isNotEmpty &&
        _controller.newPasswordCtrl.text.length < 6;

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

          CpTextField(
            controller: _controller.newPasswordCtrl,
            label: 'New Password (min. 6 characters)',
            icon: Icons.lock_outline,
            obscureText: !_controller.showNewPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _controller.showNewPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white60,
                size: 20,
              ),
              onPressed: () =>
                  _controller.togglePasswordVisibility(isNew: true),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.',
                style: TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 14),

          CpTextField(
            controller: _controller.confirmPasswordCtrl,
            label: 'Confirm New Password',
            icon: Icons.lock_outline,
            obscureText: !_controller.showConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _controller.showConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white60,
                size: 20,
              ),
              onPressed: () => _controller.togglePasswordVisibility(isNew: false),
            ),
          ),
          if (_controller.confirmPasswordCtrl.text.isNotEmpty && !match) ...[
            const SizedBox(height: 4),
            const Text('Passwords do not match.',
                style: TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (_controller.confirmPasswordCtrl.text.isNotEmpty && match) ...[
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
    final label = switch (_controller.currentPage) {
      0 => 'Send Code',
      1 => 'Verify',
      _ => 'Change Password',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          if (_controller.isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: label,
              onPressed: _controller.pageValid ? _onNext : () {},
              backgroundColor:
                  _controller.pageValid ? Colors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 8),
          if (_controller.currentPage > 0)
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
