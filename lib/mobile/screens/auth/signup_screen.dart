import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/signup_controller.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/signup_text_field.dart';
import 'package:sappiire/mobile/widgets/signup_success_screen.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/models/id_information.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _pageController = PageController();
  late final SignupController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignupController();
    _controller.init();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<int> get _pageSequence => _controller.pageSequence;
  int get _totalSteps => _controller.totalSteps;
  int get _currentActualPage => _controller.currentActualPage;

  Future<void> _onNext() async {
    final result = await _controller.onNext(context, _pageController);
    if (result == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SignUpSuccessScreen(userId: _controller.verifiedUserId!),
        ),
      );
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen(returnOnly: true)),
    );
    if (result != null && result is IdInformation) {
      _controller.applyScannedIdInfo(result);
    }
  }

  Future<void> _selectDate() async {
    await _controller.selectDate(context);
  }

  Future<bool> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel sign up?'),
        content: const Text('Going back will lose your progress. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Cancel Sign Up', style: TextStyle(color: Colors.white)),
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
        if (await _confirmCancel() && mounted) Navigator.pop(context);
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
                _controller.goPrevPage(_pageController);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_controller.stepTitle, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_controller.currentPage + 1) / _totalSteps,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                    minHeight: 5,
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (p) => _controller.setPage(p),
                  children: List.generate(_totalSteps, (i) => _buildPageAt(i)),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageAt(int pageIndex) {
    final actual = _pageSequence[pageIndex];
    switch (actual) {
      case 0: return _buildPersonalInfoPage();
      case 1: return _buildContactChoicePage();
      case 2: return _buildEmailPage();
      case 3: return _buildPhonePage();
      case 4: return _buildCredentialsPage();
      default: return const SizedBox();
    }
  }

  Widget _buildPersonalInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Personal Information',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Fill in your details or scan your National ID.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: _handleInfoScan,
            icon: const Icon(Icons.document_scanner_outlined, color: Colors.white70),
            label: const Text('Scan National ID to autofill', style: TextStyle(color: Colors.white70, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white30),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          SignupTextField(controller: _controller.lastNameCtrl, label: 'Last Name', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          SignupTextField(controller: _controller.firstNameCtrl, label: 'First Name / Given Name', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          SignupTextField(controller: _controller.middleNameCtrl, label: 'Middle Name (Optional)', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),

          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _controller.dobCtrl.text.isEmpty ? AppColors.borderNavy : AppColors.lightBlue,
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.lightBlue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _controller.dobCtrl.text.isEmpty ? 'Date of Birth *' : _controller.dobCtrl.text,
                    style: TextStyle(color: _controller.dobCtrl.text.isEmpty ? Colors.white54 : Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          SignupTextField(controller: _controller.addressCtrl, label: 'Address', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          SignupTextField(controller: _controller.placeOfBirthCtrl, label: 'Place of Birth', textInputAction: TextInputAction.done),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Sex *',
            value: _controller.sex.isEmpty ? null : _controller.sex,
            items: const ['Male', 'Female'],
            onChanged: (v) => setState(() => _controller.sex = v ?? ''),
          ),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Marital Status *',
            value: _controller.maritalStatus.isEmpty ? null : _controller.maritalStatus,
            items: const ['Single', 'Married', 'Widowed', 'Separated', 'Annulled'],
            onChanged: (v) => setState(() => _controller.maritalStatus = v ?? ''),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildContactChoicePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How would you like to verify your account?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You need at least one contact method to verify your identity and recover your account if needed.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 32),

                  _buildContactOptionCard(
                    icon: Icons.email_outlined,
                    title: 'Email Address',
                    subtitle: 'Verify with a code sent to your email',
                    value: ContactMethod.email,
                    isSelected: _controller.contactMethod == ContactMethod.email,
                  ),
                  const SizedBox(height: 14),

                  _buildContactOptionCard(
                    icon: Icons.phone_android_outlined,
                    title: 'Phone Number',
                    subtitle: 'Verify with a code sent via SMS',
                    value: ContactMethod.phone,
                    isSelected: _controller.contactMethod == ContactMethod.phone,
                  ),
                  const SizedBox(height: 14),

                  _buildContactOptionCard(
                    icon: Icons.verified_user_outlined,
                    title: 'Both Email & Phone',
                    subtitle: 'Verify with both for maximum security',
                    value: ContactMethod.both,
                    isSelected: _controller.contactMethod == ContactMethod.both,
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.white54, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your contact information is encrypted and only used for verification and account recovery.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required ContactMethod value,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _controller.contactMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryBlue
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white60,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white60
                          : Colors.white38,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? Colors.white : Colors.white30,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Email Verification', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (!_controller.emailOtpSent) ...[
            const Text('Enter your email address. A verification code will be sent.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            SignupTextField(
              controller: _controller.emailCtrl,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
          ] else if (!_controller.emailVerified) ...[
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.mark_email_read, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Check ${_controller.emailCtrl.text}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Enter the 8-digit code we sent to your email.', style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                SignupTextField(
                  controller: _controller.emailOtpCtrl,
                  label: 'Enter 8-digit code',
                  icon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Didn't receive it? ", style: TextStyle(color: Colors.white60, fontSize: 13)),
                    TextButton(
                      onPressed: (_controller.isLoading || _controller.emailOtpCountdown > 0) ? null : () => _controller.handleResendEmailOtp(context),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        _controller.emailOtpCountdown > 0 ? 'Resend in ${_controller.emailOtpCountdown}s' : 'Resend Code',
                        style: TextStyle(color: _controller.emailOtpCountdown > 0 ? Colors.white38 : AppColors.lightBlue, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _controller.resetEmailOtp(),
                  child: const Text('Use a different email', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ],
            ),
          ] else ...[
            Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline, size: 44, color: Colors.greenAccent),
                ),
                const SizedBox(height: 16),
                const Text('Email Verified!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(_controller.emailCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Phone Verification', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (!_controller.phoneOtpSent) ...[
            const Text('Enter your Philippine mobile number. We will send a 6-digit code via SMS.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            SignupTextField(
              controller: _controller.phoneCtrl,
              label: '09XXXXXXXXX',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
            ),
          ] else if (!_controller.phoneVerified) ...[
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.sms, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Check ${_controller.phoneCtrl.text}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Enter the 6-digit SMS code.', style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                SignupTextField(
                  controller: _controller.phoneOtpCtrl,
                  label: 'Enter 6-digit code',
                  icon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Didn't receive it? ", style: TextStyle(color: Colors.white60, fontSize: 13)),
                    TextButton(
                      onPressed: (_controller.isLoading || _controller.phoneOtpCountdown > 0) ? null : () => _controller.handleResendPhoneOtp(context),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        _controller.phoneOtpCountdown > 0 ? 'Resend in ${_controller.phoneOtpCountdown}s' : 'Resend Code',
                        style: TextStyle(color: _controller.phoneOtpCountdown > 0 ? Colors.white38 : AppColors.lightBlue, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _controller.resetPhoneOtp(),
                  child: const Text('Use a different number', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ],
            ),
          ] else ...[
            Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline, size: 44, color: Colors.greenAccent),
                ),
                const SizedBox(height: 16),
                const Text('Phone Verified!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(_controller.phoneCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCredentialsPage() {
    final match = _controller.passwordCtrl.text.isNotEmpty && _controller.passwordCtrl.text == _controller.confirmPasswordCtrl.text;
    final tooShort = _controller.passwordCtrl.text.isNotEmpty && _controller.passwordCtrl.text.length < 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Set Your Credentials', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('This is how you will log in to SapPIIre.', style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          SignupTextField(controller: _controller.usernameCtrl, label: 'Username', icon: Icons.person_outline, textInputAction: TextInputAction.next),
          const SizedBox(height: 14),

          SignupTextField(
            controller: _controller.passwordCtrl,
            label: 'Password (min. 6 characters)',
            icon: Icons.lock_outline,
            obscureText: !_controller.showPassword,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(_controller.showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60, size: 20),
              onPressed: () => setState(() => _controller.showPassword = !_controller.showPassword),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 14),

          SignupTextField(
            controller: _controller.confirmPasswordCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            obscureText: !_controller.showConfirmPassword,
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              icon: Icon(_controller.showConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60, size: 20),
              onPressed: () => setState(() => _controller.showConfirmPassword = !_controller.showConfirmPassword),
            ),
          ),
          if (_controller.confirmPasswordCtrl.text.isNotEmpty && !match) ...[
            const SizedBox(height: 4),
            const Text('Passwords do not match.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (_controller.confirmPasswordCtrl.text.isNotEmpty && match) ...[
            const SizedBox(height: 4),
            const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 14),
              SizedBox(width: 4),
              Text('Passwords match!', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    String label;
    switch (_currentActualPage) {
      case 2:
        if (!_controller.emailOtpSent) label = 'Send Code';
        else if (!_controller.emailVerified) label = 'Verify Email';
        else label = 'Continue';
        break;
      case 3:
        if (!_controller.phoneOtpSent) label = 'Send Code';
        else if (!_controller.phoneVerified) label = 'Verify Phone';
        else label = 'Continue';
        break;
      case 4:
        label = 'Create Account';
        break;
      default:
        label = 'Next';
    }

    bool canProceed;
    switch (_currentActualPage) {
      case 2:
        if (!_controller.emailOtpSent) canProceed = _controller.emailCtrl.text.contains('@');
        else if (!_controller.emailVerified) canProceed = _controller.emailOtpCtrl.text.length == 8;
        else canProceed = true;
        break;
      case 3:
        if (!_controller.phoneOtpSent) canProceed = _controller.phoneCtrl.text.length >= 10;
        else if (!_controller.phoneVerified) canProceed = _controller.phoneOtpCtrl.text.length == 6;
        else canProceed = true;
        break;
      default:
        canProceed = _controller.currentPageValid;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          if (_controller.isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: label,
              onPressed: canProceed ? _onNext : () {},
              backgroundColor: canProceed ? Colors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 8),
          if (_controller.currentPage > 0)
            TextButton(
              onPressed: () => _controller.goPrevPage(_pageController),
              child: const Text('Back', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value != null ? AppColors.lightBlue : AppColors.borderNavy, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          dropdownColor: const Color(0xFF1A237E),
          isExpanded: true,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
