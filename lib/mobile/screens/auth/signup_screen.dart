// signup_screen.dart — username uniqueness check added in _handleCreateAccount
// Only the _handleCreateAccount method changes from the original.
// All other methods and widgets are identical to what you already have.
//
// KEY FIX: Before calling saveProfileAfterVerification, we now check if the
// username already exists in user_accounts. If it does, we show an error and
// stay on page 4 so the user can pick a different username.
//
// Also fixes: phone number is allowed to be duplicate during signup (per your note).

// ── Replace your existing _handleCreateAccount with this: ──────────────────

/*
  Future<void> _handleCreateAccount() async {
    if (_verifiedUserId == null) {
      _showError('Session expired. Please start over.');
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      return;
    }
    if (_pin != _confirmPin) {
      _showError('PINs do not match. Please try again.');
      setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
      return;
    }

    // CHECK: username uniqueness before hitting the backend
    setState(() => _isLoading = true);
    try {
      final existing = await Supabase.instance.client
          .from('user_accounts')
          .select('user_id')
          .eq('username', _usernameController.text.trim())
          .maybeSingle();

      if (existing != null) {
        setState(() => _isLoading = false);
        _showError('Username "${_usernameController.text.trim()}" is already taken. Please choose another.');
        // Stay on page 4 — reset PIN so they re-enter after fixing username
        setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
        return;
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Could not verify username. Please try again.');
      return;
    }

    final result = await _supabaseService.saveProfileAfterVerification(
      userId: _verifiedUserId!,
      username: _usernameController.text.trim(),
      pin: _pin,
      email: _emailController.text.trim(),
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dobController.text,
      phoneNumber: _phoneController.text.trim(),
      birthplace: _placeOfBirthController.text.trim(),
      gender: _sex == 'Male' ? 'M' : _sex == 'Female' ? 'F' : _sex,
      civilStatus: _maritalStatus == 'Single'   ? 'S'
          : _maritalStatus == 'Married'          ? 'M'
          : _maritalStatus == 'Widowed'          ? 'W'
          : _maritalStatus == 'Separated'        ? 'Sep'
          : _maritalStatus == 'Annulled'         ? 'A'
          : _maritalStatus,
      addressLine: _addressController.text.trim(),
      allowDuplicatePhone: true, // phone duplicate allowed during signup
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
      // If the error is about username, reset PIN
      if (result['message'].toString().toLowerCase().contains('username')) {
        setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
      }
    }
  }
*/

// ── FULL signup_screen.dart with the fix applied ───────────────────────────

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final PageController _pageController = PageController();
  final SupabaseService _supabaseService = SupabaseService();

  int _currentPage = 0;
  bool _isLoading = false;
  String? _verifiedUserId;
  bool _phoneSent = false;

  String _pin = '';
  String _confirmPin = '';
  bool _pinConfirmStep = false;

  final _lastNameController     = TextEditingController();
  final _firstNameController    = TextEditingController();
  final _middleNameController   = TextEditingController();
  final _dobController          = TextEditingController();
  final _addressController      = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

  final _emailController    = TextEditingController();
  final _otpController      = TextEditingController();
  final _phoneController    = TextEditingController();
  final _phoneOtpController = TextEditingController();
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (var c in [
      _lastNameController, _firstNameController, _middleNameController,
      _dobController, _addressController, _placeOfBirthController,
      _emailController, _otpController, _phoneController,
      _usernameController, _phoneOtpController,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (var c in [
      _lastNameController, _firstNameController, _middleNameController,
      _dobController, _addressController, _placeOfBirthController,
      _emailController, _otpController, _phoneController,
      _usernameController, _phoneOtpController, _pageController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _getStepTitle() {
    switch (_currentPage) {
      case 0: return 'Step 1 of 4 — Personal Info';
      case 1: return 'Step 2 of 4 — Email';
      case 2: return 'Step 2 of 4 — Verify Email';
      case 3: return 'Step 3 of 4 — Phone Number';
      case 4: return 'Step 4 of 4 — Username & PIN';
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

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1A237E), onPrimary: Colors.white,
            surface: Colors.white, onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dobController.text = '${picked.month}/${picked.day}/${picked.year}';
      });
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen(returnOnly: true)),
    );
    if (result != null && result is IdInformation) {
      setState(() {
        _firstNameController.text  = result.firstName;
        _middleNameController.text = result.middleName;
        _lastNameController.text   = result.lastName;
        _dobController.text        = result.dateOfBirth;
        if (result.address.isNotEmpty) _addressController.text = result.address;
        if (result.sex.isNotEmpty) {
          _sex = result.sex.toLowerCase().startsWith('f') ? 'Female' : 'Male';
        }
        if (result.maritalStatus.isNotEmpty) {
          final l = result.maritalStatus.toLowerCase();
          if (l.contains('single'))    _maritalStatus = 'Single';
          else if (l.contains('married'))   _maritalStatus = 'Married';
          else if (l.contains('widow'))     _maritalStatus = 'Widowed';
          else if (l.contains('separated')) _maritalStatus = 'Separated';
          else if (l.contains('annul'))     _maritalStatus = 'Annulled';
        }
      });
    }
  }

  void _onPinKey(String key) {
    if (_pinConfirmStep) {
      if (_confirmPin.length >= 6) return;
      setState(() => _confirmPin += key);
    } else {
      if (_pin.length >= 6) return;
      setState(() => _pin += key);
      if (_pin.length == 6) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _pinConfirmStep = true);
        });
      }
    }
  }

  void _onPinDelete() {
    if (_pinConfirmStep) {
      if (_confirmPin.isEmpty) return;
      setState(() => _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
    } else {
      if (_pin.isEmpty) return;
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  bool _isPageValid() {
    switch (_currentPage) {
      case 0:
        return _lastNameController.text.isNotEmpty &&
            _firstNameController.text.isNotEmpty &&
            _dobController.text.isNotEmpty &&
            _addressController.text.isNotEmpty &&
            _placeOfBirthController.text.isNotEmpty &&
            _sex.isNotEmpty && _maritalStatus.isNotEmpty;
      case 1: return _emailController.text.contains('@');
      case 2: return _otpController.text.length == 8;
      case 3: return _phoneSent
          ? _phoneOtpController.text.length == 6
          : _phoneController.text.isNotEmpty;
      case 4: return _usernameController.text.isNotEmpty &&
          _pin.length == 6 && _confirmPin.length == 6 && _pin == _confirmPin;
      default: return false;
    }
  }

  void _onNext() {
    switch (_currentPage) {
      case 0: _goNext(); break;
      case 1: _handleSendOtp(); break;
      case 2: _handleVerifyOtp(); break;
      case 3: _phoneSent ? _handleVerifyPhoneOtp() : _handleSendPhoneOtp(); break;
      case 4: _handleCreateAccount(); break;
    }
  }

  Future<void> _handleSendOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.signUpWithEmail(email: _emailController.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) { _verifiedUserId = result['user_id']; _goNext(); }
    else { _showError(result['message']); }
  }

  Future<void> _handleVerifyOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyEmailOtp(
      email: _emailController.text.trim(), otp: _otpController.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) { _verifiedUserId = result['user_id']; _goNext(); }
    else { _showError(result['message']); }
  }

  Future<void> _handleResendOtp() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: _emailController.text.trim());
      if (!mounted) return;
      _showSuccess('Code resent! Check your email.');
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to resend: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.sendPhoneOtp(_phoneController.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) { setState(() => _phoneSent = true); _showSuccess('Code sent to your phone!'); }
    else { _showError(result['message']); }
  }

  Future<void> _handleVerifyPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyPhoneOtp(
      phone: _phoneController.text.trim(), otp: _phoneOtpController.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) { _goNext(); } else { _showError(result['message']); }
  }

  Future<void> _handleCreateAccount() async {
    if (_verifiedUserId == null) {
      _showError('Session expired. Please start over.');
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      return;
    }
    if (_pin != _confirmPin) {
      _showError('PINs do not match. Please try again.');
      setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
      return;
    }

    setState(() => _isLoading = true);

    // FIX: Check username uniqueness before calling backend
    try {
      final existing = await Supabase.instance.client
          .from('user_accounts')
          .select('user_id')
          .eq('username', _usernameController.text.trim())
          .maybeSingle();

      if (existing != null) {
        setState(() => _isLoading = false);
        _showError('Username "${_usernameController.text.trim()}" is already taken. Please choose another.');
        setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
        return;
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Could not verify username availability. Please try again.');
      return;
    }

    final result = await _supabaseService.saveProfileAfterVerification(
      userId:      _verifiedUserId!,
      username:    _usernameController.text.trim(),
      pin:         _pin,
      email:       _emailController.text.trim(),
      firstName:   _firstNameController.text.trim(),
      middleName:  _middleNameController.text.trim(),
      lastName:    _lastNameController.text.trim(),
      dateOfBirth: _dobController.text,
      phoneNumber: _phoneController.text.trim(),
      birthplace:  _placeOfBirthController.text.trim(),
      gender: _sex == 'Male' ? 'M' : _sex == 'Female' ? 'F' : _sex,
      civilStatus: _maritalStatus == 'Single'    ? 'S'
          : _maritalStatus == 'Married'           ? 'M'
          : _maritalStatus == 'Widowed'           ? 'W'
          : _maritalStatus == 'Separated'         ? 'Sep'
          : _maritalStatus == 'Annulled'          ? 'A'
          : _maritalStatus,
      addressLine:          _addressController.text.trim(),
      allowDuplicatePhone:  true, // phone duplicate allowed during signup per spec
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
      if (result['message'].toString().toLowerCase().contains('username')) {
        setState(() { _pin = ''; _confirmPin = ''; _pinConfirmStep = false; });
      }
    }
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
                  value: (_currentPage + 1) / 5,
                  backgroundColor: Colors.white24, color: Colors.white,
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
                    _buildOtpPage(),
                    _buildPhonePage(),
                    _buildUsernamePinPage(),
                  ],
                ),
              ),
              if (_currentPage != 4 || _usernameController.text.isEmpty)
                _buildFooter(),
              if (_currentPage == 4 && _usernameController.text.isNotEmpty)
                _buildPinFooter(),
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

  // ── Pages ──────────────────────────────────────────────────────────────────

  Widget _buildPersonalInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Personal Information',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('This info will be used for form autofill.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),

        OutlinedButton.icon(
          onPressed: _handleInfoScan,
          icon: const Icon(Icons.document_scanner_outlined, color: Colors.white70),
          label: const Text('Scan National ID to autofill',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white30),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 16),

        CustomTextField(hintText: 'Last Name',             controller: _lastNameController),
        const SizedBox(height: 10),
        CustomTextField(hintText: 'First Name / Given Name', controller: _firstNameController),
        const SizedBox(height: 10),
        CustomTextField(hintText: 'Middle Name',           controller: _middleNameController),
        const SizedBox(height: 10),

        GestureDetector(
          onTap: _selectDate,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(children: [
              const Icon(Icons.calendar_today, color: Colors.white, size: 18),
              const SizedBox(width: 12),
              Text(
                _dobController.text.isEmpty ? 'Date of Birth' : _dobController.text,
                style: TextStyle(
                  color: _dobController.text.isEmpty ? Colors.white60 : Colors.white,
                  fontSize: 16,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        CustomTextField(hintText: 'Address',       controller: _addressController),
        const SizedBox(height: 10),
        CustomTextField(hintText: 'Place of Birth', controller: _placeOfBirthController),
        const SizedBox(height: 16),

        _buildDropdownField(
          label: 'Sex', value: _sex.isEmpty ? null : _sex,
          items: const ['Male', 'Female'],
          onChanged: (v) => setState(() => _sex = v ?? ''),
        ),
        const SizedBox(height: 10),
        _buildDropdownField(
          label: 'Marital Status', value: _maritalStatus.isEmpty ? null : _maritalStatus,
          items: const ['Single', 'Married', 'Widowed', 'Separated', 'Annulled'],
          onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
        ),
      ]),
    );
  }

  Widget _buildEmailPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Email Address',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('A verification code will be sent to your email.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),
        CustomTextField(hintText: 'Email Address', controller: _emailController),
      ]),
    );
  }

  Widget _buildOtpPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.mark_email_read, size: 80, color: Colors.white),
        const SizedBox(height: 20),
        const Text('Check Your Email',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('An 8-digit code was sent to\n${_emailController.text}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 30),
        CustomTextField(hintText: 'Enter 8-digit code', controller: _otpController),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _isLoading ? null : _handleResendOtp,
          child: const Text('Resend Code', style: TextStyle(color: Colors.white60, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        const Text('Phone Number',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('A verification code will be sent via SMS.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 30),
        CustomTextField(hintText: '09XXXXXXXXX', controller: _phoneController),
        if (_phoneSent) ...[
          const SizedBox(height: 16),
          const Text('Enter the 6-digit code sent to your number',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 8),
          CustomTextField(hintText: 'Enter 6-digit code', controller: _phoneOtpController),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading ? null : _handleSendPhoneOtp,
            child: const Text('Resend Code', style: TextStyle(color: Colors.white60, fontSize: 13)),
          ),
        ],
      ]),
    );
  }

  Widget _buildUsernamePinPage() {
    final currentPinDisplay = _pinConfirmStep ? _confirmPin : _pin;
    final pinTitle    = _pinConfirmStep ? 'Confirm your PIN' : 'Create a 6-digit PIN';
    final pinSubtitle = _pinConfirmStep ? 'Re-enter your PIN to confirm' : 'This PIN protects your PII vault';
    final showMismatch = _pinConfirmStep && _confirmPin.length == 6 && _confirmPin != _pin;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Username & PIN',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('This is how you will log in to SapPIIre.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),

        if (_pin.isEmpty && !_pinConfirmStep) ...[
          CustomTextField(
            hintText: 'Username', controller: _usernameController,
            prefixIcon: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(height: 24),
        ],

        if (_usernameController.text.isNotEmpty) ...[
          Center(
            child: Column(children: [
              Text(pinTitle, style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(pinSubtitle, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < currentPinDisplay.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 16 : 14, height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: showMismatch ? Colors.redAccent
                          : filled ? Colors.white : Colors.white.withOpacity(0.25),
                      border: Border.all(
                        color: showMismatch ? Colors.redAccent : Colors.white.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              if (showMismatch) ...[
                const SizedBox(height: 8),
                const Text('PINs do not match. Try again.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              if (_pinConfirmStep && !showMismatch) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _pinConfirmStep = false; _pin = ''; _confirmPin = '';
                  }),
                  child: const Text('Re-enter PIN',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 20),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildPinFooter() {
    const keys = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']];

    if (_confirmPin.length == 6 && _confirmPin == _pin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isPageValid() && !_isLoading) _handleCreateAccount();
      });
    }
    if (_confirmPin.length == 6 && _confirmPin != _pin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _confirmPin = '');
        });
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            ...keys.map((row) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) => key.isEmpty
                  ? const SizedBox(width: 72, height: 72)
                  : _buildPinKey(key)).toList(),
            )),
          if (_currentPage > 0)
            TextButton(
              onPressed: _goPrev,
              child: const Text('Back', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  Widget _buildPinKey(String key) {
    final isDelete = key == '⌫';
    return GestureDetector(
      onTap: () => isDelete ? _onPinDelete() : _onPinKey(key),
      child: Container(
        width: 72, height: 72, margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDelete ? Colors.transparent : Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
          border: isDelete ? null : Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Center(
          child: isDelete
              ? const Icon(Icons.backspace_outlined, color: Colors.white70, size: 22)
              : Text(key, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final bool valid = _isPageValid();
    final String label = _currentPage == 4 ? 'Create Account' : 'Next';
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(children: [
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
      ]),
    );
  }

  Widget _buildDropdownField({
    required String label, required String? value,
    required List<String> items, required void Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
          dropdownColor: const Color(0xFF1A237E),
          isExpanded: true,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
          onChanged: onChanged,
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text('All signed up!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Welcome to SapPIIre Autofill App',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white, fontSize: 16)),
              const SizedBox(height: 30),
              CustomButton(
                text: 'Proceed',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => ManageInfoScreen(userId: userId)),
                ),
                backgroundColor: AppColors.white,
                textColor: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}