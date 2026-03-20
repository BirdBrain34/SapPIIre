import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/widgets/InfoScannerButton.dart';
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

  // Pages:
  // 0 → Personal Info (name, DOB, address, sex, marital status, place of birth)
  // 1 → Email + Password
  // 2 → Email OTP
  // 3 → Phone Number
  // 4 → Username (final step)
  int _currentPage = 0;
  bool _isLoading = false;
  String? _verifiedUserId;
  bool _phoneSent = false;
  final _phoneOtpController = TextEditingController();

  // Page 0 — Personal info
  final _lastNameController       = TextEditingController();
  final _firstNameController      = TextEditingController();
  final _middleNameController     = TextEditingController();
  final _dobController            = TextEditingController();
  final _addressController        = TextEditingController();
  final _placeOfBirthController   = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

  // Page 1 — Email + Password
  final _emailController          = TextEditingController();
  final _passwordController       = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Page 2 — OTP
  final _otpController            = TextEditingController();

  // Page 3 — Phone
  final _phoneController          = TextEditingController();

  // Page 4 — Username
  final _usernameController       = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (var c in [
      _lastNameController, _firstNameController, _middleNameController,
      _dobController, _addressController, _placeOfBirthController,
      _emailController, _passwordController, _confirmPasswordController,
      _otpController, _phoneController, _usernameController,
      _phoneOtpController, // ← add this
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (var c in [
      _lastNameController, _firstNameController, _middleNameController,
      _dobController, _addressController, _placeOfBirthController,
      _emailController, _passwordController, _confirmPasswordController,
      _otpController, _phoneController, _usernameController,
      _phoneOtpController, // ← add this
      _pageController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _getStepTitle() {
    switch (_currentPage) {
      case 0: return 'Step 1 of 4 — Personal Info';
      case 1: return 'Step 2 of 4 — Email';         // email only now
      case 2: return 'Step 2 of 4 — Verify Email';
      case 3: return 'Step 3 of 4 — Phone Number';
      case 4: return 'Step 4 of 4 — Username & Password'; // password moved here
      default: return '';
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _goNext() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goPrev() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
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
        _dobController.text = '${picked.month}/${picked.day}/${picked.year}';
      });
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
    );
    if (result != null && result is IdInformation) {
      setState(() {
        _firstNameController.text  = result.firstName;
        _middleNameController.text = result.middleName;
        _lastNameController.text   = result.lastName;
        _dobController.text        = result.dateOfBirth;
      });
    }
  }

  // ── Validation ────────────────────────────────────────────
  bool _isPageValid() {
    switch (_currentPage) {
      case 0:
        return _lastNameController.text.isNotEmpty &&
            _firstNameController.text.isNotEmpty &&
            _dobController.text.isNotEmpty &&
            _addressController.text.isNotEmpty &&
            _placeOfBirthController.text.isNotEmpty &&
            _sex.isNotEmpty &&
            _maritalStatus.isNotEmpty;
      case 1:
        return _emailController.text.contains('@');  // email only
      case 2:
        return _otpController.text.length == 8;
      case 3:
        return _phoneSent
            ? _phoneOtpController.text.length == 6
            : _phoneController.text.isNotEmpty;
      case 4:
        return _usernameController.text.isNotEmpty &&
            _passwordController.text.length >= 6 &&
            _passwordController.text == _confirmPasswordController.text;
      default:
        return false;
    }
  }

  // ── Page action dispatcher ────────────────────────────────────────────────

  void _onNext() {
    switch (_currentPage) {
      case 0: _goNext(); break;
      case 1: _handleSendOtp(); break;
      case 2: _handleVerifyOtp(); break;
      case 3:
      if (!_phoneSent) {
        _handleSendPhoneOtp();
      } else {
        _handleVerifyPhoneOtp();
      }
      break;
      case 4: _handleCreateAccount(); break;
    }
  }

  Future<void> _handleSendOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.signUpWithEmail(
      email: _emailController.text.trim(),
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

  Future<void> _handleVerifyOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyEmailOtp(
      email: _emailController.text.trim(),
      otp: _otpController.text.trim(),
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

  Future<void> _handleResendOtp() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code resent! Check your email.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to resend: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPhoneOtp() async {
  setState(() => _isLoading = true);
  final result = await _supabaseService.sendPhoneOtp(
    _phoneController.text.trim(),
  );
  setState(() => _isLoading = false);
  if (!mounted) return;

  if (result['success']) {
    setState(() => _phoneSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code sent to your phone!'),
        backgroundColor: Colors.green,
      ),
    );
  } else {
    _showError(result['message']);
  }
}

  Future<void> _handleVerifyPhoneOtp() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.verifyPhoneOtp(
      phone: _phoneController.text.trim(),
      otp: _phoneOtpController.text.trim(),
    );
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (result['success']) {
      _goNext();
    } else {
      _showError(result['message']);
    }
  }

Future<void> _handleCreateAccount() async {
  if (_verifiedUserId == null) {
    _showError('Session expired. Please start over.');
    _pageController.animateToPage(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    return;
  }

    setState(() => _isLoading = true);
    final result = await _supabaseService.saveProfileAfterVerification(
      userId: _verifiedUserId!,
      username: _usernameController.text.trim(),
      password: _passwordController.text,   // ← pass password here now
      email: _emailController.text.trim(),
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dobController.text,
      phoneNumber: _phoneController.text.trim(),
      birthplace: _placeOfBirthController.text.trim(),
      gender: _sex == 'Male' ? 'M' : _sex == 'Female' ? 'F' : _sex,
      civilStatus: _maritalStatus == 'Single' ? 'S'
          : _maritalStatus == 'Married' ? 'M'
          : _maritalStatus == 'Widowed' ? 'W'
          : _maritalStatus == 'Separated' ? 'Sep'
          : _maritalStatus == 'Annulled' ? 'A'
          : _maritalStatus,
      addressLine: _addressController.text.trim(),
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentPage > 0) {
              _goPrev();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(_getStepTitle(),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton:
          (_currentPage == 0 && MediaQuery.of(context).viewInsets.bottom == 0)
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 120.0, left: 10.0),
                  child: InfoScannerButton(onTap: _handleInfoScan),
                )
              : null,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
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
                  _buildOtpPage(),
                  _buildPhonePage(),
                  _buildUsernamePasswordPage(), 
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Pages ─────────────────────────────────────────────────────────────────

  Widget _buildPersonalInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Personal Information',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('This info will be used for form autofill.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 20),

          CustomTextField(hintText: 'Last Name', controller: _lastNameController),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'First Name / Given Name', controller: _firstNameController),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Middle Name', controller: _middleNameController),
          const SizedBox(height: 10),

          // Date of Birth picker
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    _dobController.text.isEmpty ? 'Date of Birth' : _dobController.text,
                    style: TextStyle(
                      color: _dobController.text.isEmpty
                          ? Colors.white60
                          : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          CustomTextField(hintText: 'Address', controller: _addressController),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Place of Birth', controller: _placeOfBirthController),
          const SizedBox(height: 16),

          // Sex dropdown
          _buildDropdownField(
            label: 'Sex',
            value: _sex.isEmpty ? null : _sex,
            items: const ['Male', 'Female'],
            onChanged: (v) => setState(() => _sex = v ?? ''),
          ),
          const SizedBox(height: 10),

          // Marital Status dropdown
          _buildDropdownField(
            label: 'Marital Status',
            value: _maritalStatus.isEmpty ? null : _maritalStatus,
            items: const ['Single', 'Married', 'Widowed', 'Separated', 'Annulled'],
            onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
          ),
        ],
      ),
    );
  }

Widget _buildEmailPage() {
  return SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Email Address',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('A verification code will be sent to your email.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),
        CustomTextField(
          hintText: 'Email Address',
          controller: _emailController,
        ),
      ],
    ),
  );
}

  Widget _buildOtpPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_read, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          const Text('Check Your Email',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'A 8-digit code was sent to\n${_emailController.text}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 30),
          CustomTextField(
            hintText: 'Enter 8-digit code',
            controller: _otpController,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _isLoading ? null : _handleResendOtp,
                child: const Text('Resend Code',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
              ),
              const SizedBox(width: 16),
              // TESTING ONLY: Skip OTP verification
              TextButton(
                onPressed: _isLoading ? null : () {
                  // Skip OTP verification for testing
                  setState(() {
                    if (_verifiedUserId == null) {
                      // Generate a test user ID if not set
                      _verifiedUserId = Supabase.instance.client.auth.currentUser?.id;
                    }
                  });
                  _goNext();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Skip (Testing)',
                    style: TextStyle(color: Colors.orange, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text('Phone Number',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'A verification code will be sent via SMS.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 30),
          CustomTextField(
            hintText: '09XXXXXXXXX',
            controller: _phoneController,
          ),
          if (_phoneSent) ...[
            const SizedBox(height: 16),
            const Text('Enter the 6-digit code sent to your number',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 8),
            CustomTextField(
              hintText: 'Enter 6-digit code',
              controller: _phoneOtpController,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _handleSendPhoneOtp,
                  child: const Text('Resend Code',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ),
                const SizedBox(width: 16),
                // TESTING ONLY: Skip phone OTP verification
                TextButton(
                  onPressed: _isLoading ? null : () {
                    _goNext();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Skip (Testing)',
                      style: TextStyle(color: Colors.orange, fontSize: 13)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

Widget _buildUsernamePasswordPage() {
  final passwordsMatch = _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmPasswordController.text;
  final tooShort = _passwordController.text.isNotEmpty &&
      _passwordController.text.length < 6;

  return SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Username & Password',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('This is how you will log in to SapPIIre.',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),
        CustomTextField(
          hintText: 'Username',
          controller: _usernameController,
          prefixIcon: const Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(height: 10),
        CustomTextField(
          hintText: 'Password (min. 6 characters)',
          controller: _passwordController,
          obscureText: true,
          prefixIcon: const Icon(Icons.lock, color: Colors.white),
        ),
        if (tooShort) ...[
          const SizedBox(height: 4),
          const Text('Password must be at least 6 characters.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        CustomTextField(
          hintText: 'Confirm Password',
          controller: _confirmPasswordController,
          obscureText: true,
          prefixIcon: const Icon(Icons.lock, color: Colors.white),
        ),
        if (_confirmPasswordController.text.isNotEmpty && !passwordsMatch) ...[
          const SizedBox(height: 4),
          const Text('Passwords do not match.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ],
      ],
    ),
  );
}

  // ── Reusable dropdown ─────────────────────────────────────────────────────

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
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
          items: items
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final bool valid = _isPageValid();
    final String label = _currentPage == 4 ? 'Create Account' : 'Next';

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
                  style: TextStyle(
                      color: AppColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Welcome to SapPIIre Autofill App',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white, fontSize: 16)),
              const SizedBox(height: 30),
              CustomButton(
                text: 'Proceed',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ManageInfoScreen(userId: userId)),
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