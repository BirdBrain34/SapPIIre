import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _pageController = PageController();
  final _supabaseService = SupabaseService();

  // OTP countdown timers
  Timer? _emailOtpTimer;
  int _emailOtpCountdown = 0;
  Timer? _phoneOtpTimer;
  int _phoneOtpCountdown = 0; // 120s for phone due to Semaphore token limits

  // Pages:
  // 0 → Personal Info
  // 1 → Email (required) + optional phone hint
  // 2 → Email OTP
  // 3 → Phone Number (optional — can skip)
  // 4 → Username & Password
  int _currentPage = 0;
  bool _isLoading = false;
  String? _verifiedUserId;
  bool _phoneSent = false;
  bool _phoneSkipped = false;

  // Page 0
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

  // Page 1
  final _emailCtrl = TextEditingController();

  // Page 2
  final _otpCtrl = TextEditingController();

  // Page 3
  final _phoneCtrl = TextEditingController();
  final _phoneOtpCtrl = TextEditingController();

  // Page 4
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    for (final c in _allControllers) {
      c.addListener(() => setState(() {}));
    }
  }

  List<TextEditingController> get _allControllers => [
        _lastNameCtrl, _firstNameCtrl, _middleNameCtrl,
        _dobCtrl, _addressCtrl, _placeOfBirthCtrl,
        _emailCtrl, _otpCtrl,
        _phoneCtrl, _phoneOtpCtrl,
        _usernameCtrl, _passwordCtrl, _confirmPasswordCtrl,
      ];

  @override
  void dispose() {
    _emailOtpTimer?.cancel();
    _phoneOtpTimer?.cancel();
    for (final c in [..._allControllers, _pageController]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Step titles ───────────────────────────────────────────
  String get _stepTitle => switch (_currentPage) {
    0 => 'Step 1 of 4 — Personal Info',
    1 => 'Step 2 of 4 — Email',
    2 => 'Step 2 of 4 — Verify Email',
    3 => 'Step 3 of 4 — Phone Number',
    _ => 'Step 4 of 4 — Username & Password',
  };

  // ── Validation ────────────────────────────────────────────
  bool get _pageValid => switch (_currentPage) {
    0 => _lastNameCtrl.text.isNotEmpty &&
        _firstNameCtrl.text.isNotEmpty &&
        _dobCtrl.text.isNotEmpty &&
        _addressCtrl.text.isNotEmpty &&
        _placeOfBirthCtrl.text.isNotEmpty &&
        _sex.isNotEmpty &&
        _maritalStatus.isNotEmpty,
    1 => _emailCtrl.text.contains('@'),
    2 => _otpCtrl.text.length == 8,
    3 => _phoneSkipped ||
        (_phoneSent
            ? _phoneOtpCtrl.text.length == 6
            : _phoneCtrl.text.length >= 10),
    _ => _usernameCtrl.text.isNotEmpty &&
        _passwordCtrl.text.length >= 6 &&
        _passwordCtrl.text == _confirmPasswordCtrl.text,
  };

  // ── Navigation helpers ────────────────────────────────────
  void _goNext() => _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
  void _goPrev() => _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

  void _onNext() {
    switch (_currentPage) {
      case 0:
        _goNext();
        break;
      case 1:
        _handleSendEmailOtp();
        break;
      case 2:
        _handleVerifyEmailOtp();
        break;
      case 3:
        if (_phoneSkipped) {
          _goNext();
        } else if (!_phoneSent) {
          _handleSendPhoneOtp();
        } else {
          _handleVerifyPhoneOtp();
        }
        break;
      case 4:
        _handleCreateAccount();
        break;
    }
  }

  // ── Timers ────────────────────────────────────────────────
  void _startEmailCountdown() {
    _emailOtpCountdown = 60;
    _emailOtpTimer?.cancel();
    _emailOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_emailOtpCountdown > 0) _emailOtpCountdown--;
        else t.cancel();
      });
    });
  }

  void _startPhoneCountdown() {
    _phoneOtpCountdown = 120; // 2 minutes — Semaphore token conservation
    _phoneOtpTimer?.cancel();
    _phoneOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_phoneOtpCountdown > 0) _phoneOtpCountdown--;
        else t.cancel();
      });
    });
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _handleSendEmailOtp() async {
    setState(() => _isLoading = true);
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      email: _emailCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      setState(() => _isLoading = false);
      _showError(dupCheck['message']);
      return;
    }
    final result = await _supabaseService.signUpWithEmail(
      email: _emailCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      _verifiedUserId = result['user_id'];
      _startEmailCountdown();
      _goNext();
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleResendEmailOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.resendEmailOtp(_emailCtrl.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      _startEmailCountdown();
      _showSuccess(result['message']?.toString() ?? 'Code resent!');
    } else {
      _showError(result['message']?.toString() ?? 'Failed to resend OTP.');
    }
  }

  Future<void> _handleVerifyEmailOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyEmailOtp(
      email: _emailCtrl.text.trim(),
      otp: _otpCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      _verifiedUserId = result['user_id'];
      _goNext();
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleSendPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.sendPhoneOtp(_phoneCtrl.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      setState(() => _phoneSent = true);
      _startPhoneCountdown();
      _showSuccess('Code sent to your phone!');
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleVerifyPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyPhoneOtp(
      phone: _phoneCtrl.text.trim(),
      otp: _phoneOtpCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) _goNext();
    else _showError(result['message']);
  }

  Future<void> _handleCreateAccount() async {
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      phone: _phoneSkipped ? null : _phoneCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      _showError(dupCheck['message']);
      return;
    }
    if (_verifiedUserId == null) {
      _showError('Session expired. Please start over.');
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
      return;
    }
    setState(() => _isLoading = true);
    final result = await _supabaseService.saveProfileAfterVerification(
      userId: _verifiedUserId!,
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      email: _emailCtrl.text.trim(),
      firstName: _firstNameCtrl.text.trim(),
      middleName: _middleNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      dateOfBirth: _dobCtrl.text,
      phoneNumber: _phoneSkipped ? '' : _phoneCtrl.text.trim(),
      birthplace: _placeOfBirthCtrl.text.trim(),
      gender: _sex == 'Male' ? 'M' : _sex == 'Female' ? 'F' : _sex,
      civilStatus: switch (_maritalStatus) {
        'Single' => 'S',
        'Married' => 'M',
        'Widowed' => 'W',
        'Separated' => 'Sep',
        'Annulled' => 'A',
        _ => _maritalStatus,
      },
      addressLine: _addressCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SignUpSuccessScreen(userId: result['user_id']),
        ),
      );
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InfoScannerScreen(returnOnly: true),
      ),
    );
    if (result != null && result is IdInformation) {
      setState(() {
        _firstNameCtrl.text = result.firstName;
        _middleNameCtrl.text = result.middleName;
        _lastNameCtrl.text = result.lastName;
        _dobCtrl.text = result.dateOfBirth;
        if (result.address.isNotEmpty) _addressCtrl.text = result.address;
        if (result.sex.isNotEmpty) {
          _sex = result.sex.toLowerCase().startsWith('f') ? 'Female' : 'Male';
        }
        if (result.maritalStatus.isNotEmpty) {
          final l = result.maritalStatus.toLowerCase();
          if (l.contains('single')) _maritalStatus = 'Single';
          else if (l.contains('married')) _maritalStatus = 'Married';
          else if (l.contains('widow')) _maritalStatus = 'Widowed';
          else if (l.contains('separated')) _maritalStatus = 'Separated';
          else if (l.contains('annul')) _maritalStatus = 'Annulled';
        }
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1A237E),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text = '${picked.month}/${picked.day}/${picked.year}';
      });
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage == 0) { Navigator.pop(context); return; }
        final confirmed = await _confirmCancel();
        if (confirmed && context.mounted) Navigator.pop(context);
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
          title: Text(
            _stepTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / 5,
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
                    _buildPersonalInfoPage(),
                    _buildEmailPage(),
                    _buildEmailOtpPage(),
                    _buildPhonePage(),
                    _buildUsernamePasswordPage(),
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

  Future<bool> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel sign up?'),
        content: const Text(
            'Going back will lose your progress. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed),
            child: const Text('Cancel Sign Up',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ── Pages ─────────────────────────────────────────────────

  Widget _buildPersonalInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Personal Information',
              style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('This info will be used for form autofill.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: _handleInfoScan,
            icon: const Icon(Icons.document_scanner_outlined,
                color: Colors.white70),
            label: const Text('Scan National ID to autofill',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white30),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          _SignupField(controller: _lastNameCtrl, label: 'Last Name'),
          const SizedBox(height: 14),
          _SignupField(
              controller: _firstNameCtrl, label: 'First Name / Given Name'),
          const SizedBox(height: 14),
          _SignupField(controller: _middleNameCtrl, label: 'Middle Name'),
          const SizedBox(height: 14),

          // Date of birth
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _dobCtrl.text.isEmpty
                      ? AppColors.borderNavy
                      : AppColors.lightBlue,
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: AppColors.lightBlue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _dobCtrl.text.isEmpty
                        ? 'Date of Birth'
                        : _dobCtrl.text,
                    style: TextStyle(
                      color: _dobCtrl.text.isEmpty
                          ? Colors.white54
                          : Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _SignupField(controller: _addressCtrl, label: 'Address'),
          const SizedBox(height: 14),
          _SignupField(
              controller: _placeOfBirthCtrl, label: 'Place of Birth'),
          const SizedBox(height: 14),

          _buildDropdownField(
            label: 'Sex',
            value: _sex.isEmpty ? null : _sex,
            items: const ['Male', 'Female'],
            onChanged: (v) => setState(() => _sex = v ?? ''),
          ),
          const SizedBox(height: 14),

          _buildDropdownField(
            label: 'Marital Status',
            value: _maritalStatus.isEmpty ? null : _maritalStatus,
            items: const [
              'Single', 'Married', 'Widowed', 'Separated', 'Annulled',
            ],
            onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildEmailPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Email Address',
              style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'A verification code will be sent to your email. '
            'You can optionally add a phone number on the next step.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _SignupField(
            controller: _emailCtrl,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  Widget _buildEmailOtpPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_read, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          const Text('Check Your Email',
              style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'An 8-digit code was sent to\n${_emailCtrl.text}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 30),
          _SignupField(
            controller: _otpCtrl,
            label: 'Enter 8-digit code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: (_isLoading || _emailOtpCountdown > 0)
                ? null
                : _handleResendEmailOtp,
            child: Text(
              _emailOtpCountdown > 0
                  ? 'Resend in ${_emailOtpCountdown}s'
                  : 'Resend Code',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Phone Number',
              style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          // Notify user this is optional
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.white60, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phone number is optional. You need at least an email '
                    'OR a phone number to recover your account.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!_phoneSkipped) ...[
            _SignupField(
              controller: _phoneCtrl,
              label: '09XXXXXXXXX',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              enabled: !_phoneSent,
            ),
            const SizedBox(height: 14),

            if (_phoneSent) ...[
              _SignupField(
                controller: _phoneOtpCtrl,
                label: 'Enter 6-digit code',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: (_isLoading || _phoneOtpCountdown > 0)
                      ? null
                      : _handleSendPhoneOtp,
                  child: Text(
                    _phoneOtpCountdown > 0
                        ? 'Resend in ${_phoneOtpCountdown}s'
                        : 'Resend Code',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],

          if (!_phoneSent) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => setState(() {
                  _phoneSkipped = true;
                  _phoneSent = false;
                  _phoneCtrl.clear();
                  _phoneOtpCtrl.clear();
                }),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                ),
                child: const Text(
                  'Skip — I don\'t have a phone number',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],

          if (_phoneSkipped) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Phone number skipped. You can add it later from your profile.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _phoneSkipped = false;
                      _phoneSent = false;
                    }),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.lightBlue,
                        padding: EdgeInsets.zero),
                    child: const Text('Undo', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsernamePasswordPage() {
    final match = _passwordCtrl.text.isNotEmpty &&
        _passwordCtrl.text == _confirmPasswordCtrl.text;
    final tooShort = _passwordCtrl.text.isNotEmpty &&
        _passwordCtrl.text.length < 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Username & Password',
              style: TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('This is how you will log in to SapPIIre.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          _SignupField(
            controller: _usernameCtrl,
            label: 'Username',
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),

          _SignupField(
            controller: _passwordCtrl,
            label: 'Password (min. 6 characters)',
            icon: Icons.lock_outline,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white60,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _showPassword = !_showPassword),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.',
                style: TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 14),

          _SignupField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            obscureText: !_showConfirmPassword,
            textInputAction: TextInputAction.done,
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

  // ── Shared widgets ────────────────────────────────────────

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value != null ? AppColors.lightBlue : AppColors.borderNavy,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14)),
          dropdownColor: const Color(0xFF1A237E),
          isExpanded: true,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: items
              .map((item) =>
                  DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────
  Widget _buildFooter() {
    final label = _currentPage == 4
        ? 'Create Account'
        : _currentPage == 3 && _phoneSkipped
        ? 'Continue'
        : 'Next';

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

// ── Reusable floating-label field for signup ──────────────────────────────────

class _SignupField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool enabled;

  const _SignupField({
    required this.controller,
    required this.label,
    this.icon,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.suffixIcon,
    this.keyboardType,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      enabled: enabled,
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ── Success Screen ─────────────────────────────────────────────────────────

class SignUpSuccessScreen extends StatelessWidget {
  final String userId;
  const SignUpSuccessScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text('All signed up!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Welcome to SapPIIre Autofill App',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 30),
              CustomButton(
                text: 'Proceed',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ManageInfoScreen(userId: userId),
                  ),
                ),
                backgroundColor: Colors.white,
                textColor: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}