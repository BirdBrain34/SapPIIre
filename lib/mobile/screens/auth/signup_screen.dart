import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

// ── Contact method enum ───────────────────────────────────────
enum _ContactMethod { email, phone, both }

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
  int _phoneOtpCountdown = 0;

  // Pages:
  // 0 → Personal Info
  // 1 → Contact method choice (email / phone / both)
  // 2 → Email entry + OTP (if email chosen)
  // 3 → Phone entry + OTP (if phone chosen)
  // 4 → Username & Password
  int _currentPage = 0;
  bool _isLoading = false;
  String? _verifiedUserId;

  // Contact method chosen on page 1
  _ContactMethod _contactMethod = _ContactMethod.email;

  // Email flow state
  bool _emailOtpSent = false;
  bool _emailVerified = false;

  // Phone flow state
  bool _phoneOtpSent = false;
  bool _phoneVerified = false;

  // Page 0 — Personal Info
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

  // Page 2 — Email
  final _emailCtrl = TextEditingController();
  final _emailOtpCtrl = TextEditingController();

  // Page 3 — Phone
  final _phoneCtrl = TextEditingController();
  final _phoneOtpCtrl = TextEditingController();

  // Page 4 — Username & Password
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Computed: which pages to show based on contact method
  // Always: 0 (personal), 1 (contact choice), 4 (username/password)
  // Optional: 2 (email), 3 (phone)
  List<int> get _pageSequence {
    switch (_contactMethod) {
      case _ContactMethod.email:
        return [0, 1, 2, 4]; // personal → choice → email → credentials
      case _ContactMethod.phone:
        return [0, 1, 3, 4]; // personal → choice → phone → credentials
      case _ContactMethod.both:
        return [0, 1, 2, 3, 4]; // personal → choice → email → phone → credentials
    }
  }

  int get _totalSteps => _pageSequence.length;
  int get _currentStepIndex => _currentPage; // tracks index in _pageSequence
  int get _currentActualPage => _pageSequence[_currentPage];

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
        _emailCtrl, _emailOtpCtrl,
        _phoneCtrl, _phoneOtpCtrl,
        _usernameCtrl, _passwordCtrl, _confirmPasswordCtrl,
      ];

  @override
  void dispose() {
    _emailOtpTimer?.cancel();
    _phoneOtpTimer?.cancel();
    for (final c in _allControllers) c.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String get _stepTitle {
    switch (_currentActualPage) {
      case 0: return 'Step 1 of $_totalSteps — Personal Info';
      case 1: return 'Step 2 of $_totalSteps — Contact Method';
      case 2: return 'Email Verification';
      case 3: return 'Phone Verification';
      case 4: return 'Step $_totalSteps of $_totalSteps — Credentials';
      default: return 'Sign Up';
    }
  }

  bool get _currentPageValid {
    switch (_currentActualPage) {
      case 0:
        return _lastNameCtrl.text.isNotEmpty &&
            _firstNameCtrl.text.isNotEmpty &&
            _dobCtrl.text.isNotEmpty &&
            _addressCtrl.text.isNotEmpty &&
            _placeOfBirthCtrl.text.isNotEmpty &&
            _sex.isNotEmpty &&
            _maritalStatus.isNotEmpty;
      case 1:
        return true; // always can proceed from contact choice
      case 2:
        // email page: need verified
        return _emailVerified;
      case 3:
        // phone page: need verified
        return _phoneVerified;
      case 4:
        return _usernameCtrl.text.isNotEmpty &&
            _passwordCtrl.text.length >= 6 &&
            _passwordCtrl.text == _confirmPasswordCtrl.text;
      default:
        return false;
    }
  }

  // ── Timers ────────────────────────────────────────────────
  void _startEmailCountdown() {
    _emailOtpCountdown = 60;
    _emailOtpTimer?.cancel();
    _emailOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (_emailOtpCountdown > 0) _emailOtpCountdown--; else t.cancel(); });
    });
  }

  void _startPhoneCountdown() {
    _phoneOtpCountdown = 120;
    _phoneOtpTimer?.cancel();
    _phoneOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (_phoneOtpCountdown > 0) _phoneOtpCountdown--; else t.cancel(); });
    });
  }

  // ── Navigation ────────────────────────────────────────────
  void _goNextPage() {
    if (_currentPage < _totalSteps - 1) {
      _currentPage++;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {});
    }
  }

  void _goPrevPage() {
    if (_currentPage > 0) {
      _currentPage--;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {});
    }
  }

  Future<void> _onNext() async {
    switch (_currentActualPage) {
      case 0:
        _goNextPage();
        break;
      case 1:
        // Contact method chosen — reset verification states
        _emailVerified = false;
        _phoneVerified = false;
        _emailOtpSent = false;
        _phoneOtpSent = false;
        _goNextPage();
        break;
      case 2:
        // Email page
        if (!_emailOtpSent) {
          await _handleSendEmailOtp();
        } else if (!_emailVerified) {
          await _handleVerifyEmailOtp();
        } else {
          _goNextPage();
        }
        break;
      case 3:
        // Phone page
        if (!_phoneOtpSent) {
          await _handleSendPhoneOtp();
        } else if (!_phoneVerified) {
          await _handleVerifyPhoneOtp();
        } else {
          _goNextPage();
        }
        break;
      case 4:
        await _handleCreateAccount();
        break;
    }
  }

  // ── Email actions ─────────────────────────────────────────
  Future<void> _handleSendEmailOtp() async {
    setState(() => _isLoading = true);
    final dupCheck = await _supabaseService.checkDuplicateSignup(email: _emailCtrl.text.trim());
    if (!dupCheck['success']) {
      setState(() => _isLoading = false);
      _showError(dupCheck['message']);
      return;
    }
    final result = await _supabaseService.signUpWithEmail(email: _emailCtrl.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      _verifiedUserId = result['user_id'];
      setState(() => _emailOtpSent = true);
      _startEmailCountdown();
      _showSuccess('Code sent to ${_emailCtrl.text.trim()}');
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleVerifyEmailOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyEmailOtp(
      email: _emailCtrl.text.trim(),
      otp: _emailOtpCtrl.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      _verifiedUserId = result['user_id'];
      setState(() => _emailVerified = true);
      _showSuccess('Email verified!');
      _goNextPage();
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
      _showSuccess('Code resent!');
    } else {
      _showError(result['message']?.toString() ?? 'Failed to resend.');
    }
  }

  // ── Phone actions ─────────────────────────────────────────
  Future<void> _handleSendPhoneOtp() async {
    setState(() => _isLoading = true);
    // Check duplicate phone first
    final dupCheck = await _supabaseService.checkDuplicateSignup(phone: _phoneCtrl.text.trim());
    if (!dupCheck['success']) {
      setState(() => _isLoading = false);
      _showError(dupCheck['message']);
      return;
    }
    final result = await _supabaseService.sendPhoneOtp(_phoneCtrl.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      setState(() => _phoneOtpSent = true);
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
    if (result['success']) {
      // If phone-only, we need to create a Supabase auth user via email workaround
      // or sign up with phone. For now, if phone-only, we generate a temp email.
      if (_contactMethod == _ContactMethod.phone && _verifiedUserId == null) {
        // Phone-only users: signup with a generated email
        final tempEmail = '${_phoneCtrl.text.trim().replaceAll('+', '')}@sappiire.phone';
        final signupResult = await _supabaseService.signUpWithEmail(
          email: tempEmail,
          password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : 'temp${DateTime.now().millisecondsSinceEpoch}',
        );
        if (signupResult['success'] == true) {
          _verifiedUserId = signupResult['user_id'];
        }
      }
      setState(() => _phoneVerified = true);
      _showSuccess('Phone verified!');
      _goNextPage();
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleResendPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.sendPhoneOtp(_phoneCtrl.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      _startPhoneCountdown();
      _showSuccess('Code resent!');
    } else {
      _showError(result['message']);
    }
  }

  // ── Create account ────────────────────────────────────────
  Future<void> _handleCreateAccount() async {
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      username: _usernameCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      _showError(dupCheck['message']);
      return;
    }
    if (_verifiedUserId == null) {
      _showError('Session expired. Please start over.');
      return;
    }
    setState(() => _isLoading = true);

    final phoneNumber = (_contactMethod == _ContactMethod.email) ? '' : _phoneCtrl.text.trim();
    final email = (_contactMethod == _ContactMethod.phone)
        ? '${_phoneCtrl.text.trim().replaceAll('+', '')}@sappiire.phone'
        : _emailCtrl.text.trim();

    final result = await _supabaseService.saveProfileAfterVerification(
      userId: _verifiedUserId!,
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      email: email,
      firstName: _firstNameCtrl.text.trim(),
      middleName: _middleNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      dateOfBirth: _dobCtrl.text,
      phoneNumber: phoneNumber,
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
        MaterialPageRoute(builder: (_) => SignUpSuccessScreen(userId: result['user_id'])),
      );
    } else {
      _showError(result['message']);
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen(returnOnly: true)),
    );
    if (result != null && result is IdInformation) {
      setState(() {
        _firstNameCtrl.text = result.firstName;
        _middleNameCtrl.text = result.middleName;
        _lastNameCtrl.text = result.lastName;
        _dobCtrl.text = result.dateOfBirth;
        if (result.address.isNotEmpty) _addressCtrl.text = result.address;
        if (result.placeOfBirth.isNotEmpty) _placeOfBirthCtrl.text = result.placeOfBirth;
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
      setState(() { _dobCtrl.text = '${picked.month}/${picked.day}/${picked.year}'; });
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage == 0) { Navigator.pop(context); return; }
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
              if (_currentPage > 0) {
                _goPrevPage();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_stepTitle, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentPage + 1) / _totalSteps,
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
                  onPageChanged: (p) => setState(() => _currentPage = p),
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

  // ── Page 0: Personal Info ─────────────────────────────────
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

          _SignupField(controller: _lastNameCtrl, label: 'Last Name', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          _SignupField(controller: _firstNameCtrl, label: 'First Name / Given Name', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          _SignupField(controller: _middleNameCtrl, label: 'Middle Name (Optional)', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),

          // DOB picker
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _dobCtrl.text.isEmpty ? AppColors.borderNavy : AppColors.lightBlue,
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.lightBlue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _dobCtrl.text.isEmpty ? 'Date of Birth *' : _dobCtrl.text,
                    style: TextStyle(color: _dobCtrl.text.isEmpty ? Colors.white54 : Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _SignupField(controller: _addressCtrl, label: 'Address', textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          _SignupField(controller: _placeOfBirthCtrl, label: 'Place of Birth', textInputAction: TextInputAction.done),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Sex *',
            value: _sex.isEmpty ? null : _sex,
            items: const ['Male', 'Female'],
            onChanged: (v) => setState(() => _sex = v ?? ''),
          ),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Marital Status *',
            value: _maritalStatus.isEmpty ? null : _maritalStatus,
            items: const ['Single', 'Married', 'Widowed', 'Separated', 'Annulled'],
            onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Page 1: Contact Method Choice ────────────────────────
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
                    value: _ContactMethod.email,
                    isSelected: _contactMethod == _ContactMethod.email,
                  ),
                  const SizedBox(height: 14),

                  _buildContactOptionCard(
                    icon: Icons.phone_android_outlined,
                    title: 'Phone Number',
                    subtitle: 'Verify with a code sent via SMS',
                    value: _ContactMethod.phone,
                    isSelected: _contactMethod == _ContactMethod.phone,
                  ),
                  const SizedBox(height: 14),

                  _buildContactOptionCard(
                    icon: Icons.verified_user_outlined,
                    title: 'Both Email & Phone',
                    subtitle: 'Verify with both for maximum security',
                    value: _ContactMethod.both,
                    isSelected: _contactMethod == _ContactMethod.both,
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: const [
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
  required _ContactMethod value,
  required bool isSelected,
}) {
  return GestureDetector(
    onTap: () => setState(() => _contactMethod = value),
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
        crossAxisAlignment: CrossAxisAlignment.start, // ✅ prevents vertical overflow
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

          // ✅ Flexible prevents overflow
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
                    height: 1.3, // ✅ improves wrapping
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

  // ── Page 2: Email OTP ─────────────────────────────────────
  Widget _buildEmailPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Email Verification', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (!_emailOtpSent) ...[
            const Text('Enter your email address. A verification code will be sent.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            _SignupField(
              controller: _emailCtrl,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
          ] else if (!_emailVerified) ...[
            // OTP entry
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.mark_email_read, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Check ${_emailCtrl.text}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Enter the 8-digit code we sent to your email.', style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                _SignupField(
                  controller: _emailOtpCtrl,
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
                      onPressed: (_isLoading || _emailOtpCountdown > 0) ? null : _handleResendEmailOtp,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        _emailOtpCountdown > 0 ? 'Resend in ${_emailOtpCountdown}s' : 'Resend Code',
                        style: TextStyle(color: _emailOtpCountdown > 0 ? Colors.white38 : AppColors.lightBlue, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _emailOtpSent = false;
                    _emailOtpCtrl.clear();
                  }),
                  child: const Text('Use a different email', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ],
            ),
          ] else ...[
            // Verified state
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
                Text(_emailCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Page 3: Phone OTP ─────────────────────────────────────
  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Phone Verification', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (!_phoneOtpSent) ...[
            const Text('Enter your Philippine mobile number. We will send a 6-digit code via SMS.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            _SignupField(
              controller: _phoneCtrl,
              label: '09XXXXXXXXX',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
            ),
          ] else if (!_phoneVerified) ...[
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.sms, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Check ${_phoneCtrl.text}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Enter the 6-digit SMS code.', style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                _SignupField(
                  controller: _phoneOtpCtrl,
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
                      onPressed: (_isLoading || _phoneOtpCountdown > 0) ? null : _handleResendPhoneOtp,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        _phoneOtpCountdown > 0 ? 'Resend in ${_phoneOtpCountdown}s' : 'Resend Code',
                        style: TextStyle(color: _phoneOtpCountdown > 0 ? Colors.white38 : AppColors.lightBlue, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _phoneOtpSent = false;
                    _phoneOtpCtrl.clear();
                  }),
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
                Text(_phoneCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Page 4: Username & Password ───────────────────────────
  Widget _buildCredentialsPage() {
    final match = _passwordCtrl.text.isNotEmpty && _passwordCtrl.text == _confirmPasswordCtrl.text;
    final tooShort = _passwordCtrl.text.isNotEmpty && _passwordCtrl.text.length < 6;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Set Your Credentials', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('This is how you will log in to SapPIIre.', style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),

          _SignupField(controller: _usernameCtrl, label: 'Username', icon: Icons.person_outline, textInputAction: TextInputAction.next),
          const SizedBox(height: 14),

          _SignupField(
            controller: _passwordCtrl,
            label: 'Password (min. 6 characters)',
            icon: Icons.lock_outline,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60, size: 20),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          if (tooShort) ...[
            const SizedBox(height: 4),
            const Text('Password must be at least 6 characters.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 14),

          _SignupField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            obscureText: !_showConfirmPassword,
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              icon: Icon(_showConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60, size: 20),
              onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
            ),
          ),
          if (_confirmPasswordCtrl.text.isNotEmpty && !match) ...[
            const SizedBox(height: 4),
            const Text('Passwords do not match.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (_confirmPasswordCtrl.text.isNotEmpty && match) ...[
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

  // ── Footer ────────────────────────────────────────────────
  Widget _buildFooter() {
    String label;
    switch (_currentActualPage) {
      case 2:
        if (!_emailOtpSent) label = 'Send Code';
        else if (!_emailVerified) label = 'Verify Email';
        else label = 'Continue';
        break;
      case 3:
        if (!_phoneOtpSent) label = 'Send Code';
        else if (!_phoneVerified) label = 'Verify Phone';
        else label = 'Continue';
        break;
      case 4:
        label = 'Create Account';
        break;
      default:
        label = 'Next';
    }

    // Determine if next button should be active
    bool canProceed;
    switch (_currentActualPage) {
      case 2:
        if (!_emailOtpSent) canProceed = _emailCtrl.text.contains('@');
        else if (!_emailVerified) canProceed = _emailOtpCtrl.text.length == 8;
        else canProceed = true;
        break;
      case 3:
        if (!_phoneOtpSent) canProceed = _phoneCtrl.text.length >= 10;
        else if (!_phoneVerified) canProceed = _phoneOtpCtrl.text.length == 6;
        else canProceed = true;
        break;
      default:
        canProceed = _currentPageValid;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          if (_isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: label,
              onPressed: canProceed ? _onNext : () {},
              backgroundColor: canProceed ? AppColors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 8),
          if (_currentPage > 0)
            TextButton(
              onPressed: _goPrevPage,
              child: const Text('Back', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  // ── Dropdown helper ───────────────────────────────────────
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
}

// ── Reusable sign-up field ────────────────────────────────────
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
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.lightBlue, fontSize: 12, fontWeight: FontWeight.w600),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.lightBlue, size: 20) : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.inputBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBlue, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ── Success Screen ────────────────────────────────────────────
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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 56),
              ),
              const SizedBox(height: 24),
              const Text('All signed up!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Welcome to SapPIIre', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('Your information is saved and ready for autofill.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 36),
              CustomButton(
                text: 'Proceed',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => ManageInfoScreen(userId: userId)),
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