import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

/// PIN reset screen — replaces ChangePasswordScreen.
///
/// Flow:
///   Step 1 — Verify identity: first name + last name + date of birth
///   Step 2 — OTP (email or phone — user chooses)
///   Step 3 — Enter + confirm new 6-digit PIN
///
/// The knowledge-factor step (name + DOB) ensures that physical
/// possession of the phone alone cannot bypass PIN recovery.
class ChangePinScreen extends StatefulWidget {
  /// fromProfile = true → came from settings, pops back on success.
  /// fromProfile = false (default) → came from login, goes to LoginScreen.
  final bool fromProfile;

  const ChangePinScreen({super.key, this.fromProfile = false});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final PageController _pageController = PageController();
  final SupabaseService _supabaseService = SupabaseService();

  int _currentPage = 0;
  bool _isLoading = false;
  bool _useEmail = true;

  // Step 1 — Identity verification
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String? _dobValue; // date string YYYY-MM-DD

  // Step 2 — OTP
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  // Step 3 — New PIN
  String _newPin = '';
  String _confirmPin = '';
  bool _pinConfirmStep = false;

  // Resolved after identity check
  String? _resolvedUserId;

  @override
  void initState() {
    super.initState();
    for (var c in [
      _firstNameController, _lastNameController,
      _emailController, _phoneController, _otpController,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (var c in [
      _firstNameController, _lastNameController,
      _emailController, _phoneController, _otpController,
      _pageController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _stepTitle() {
    switch (_currentPage) {
      case 0: return 'Step 1 of 3 — Verify Identity';
      case 1: return 'Step 2 of 3 — Verify Code';
      case 2: return 'Step 3 of 3 — New PIN';
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
        return _firstNameController.text.isNotEmpty &&
            _lastNameController.text.isNotEmpty &&
            _dobValue != null;
      case 1:
        return _useEmail
            ? (_emailController.text.contains('@') &&
                _otpController.text.length == 8)
            : (_phoneController.text.length >= 10 &&
                _otpController.text.length == 6);
      case 2:
        return _newPin.length == 6 &&
            _confirmPin.length == 6 &&
            _newPin == _confirmPin;
      default:
        return false;
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
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
        // Store as YYYY-MM-DD for database comparison
        _dobValue =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _onNext() {
    switch (_currentPage) {
      case 0: _handleVerifyIdentity(); break;
      case 1: _handleVerifyOtp(); break;
      case 2: _handleSetNewPin(); break;
    }
  }

  Future<void> _handleVerifyIdentity() async {
    if (_dobValue == null) {
      _showError('Please select your date of birth.');
      return;
    }
    setState(() => _isLoading = true);

    final result = await _supabaseService.verifyIdentityForPinReset(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dobValue!,
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (!result['success']) {
      _showError(result['message']);
      return;
    }

    _resolvedUserId = result['user_id'];

    // Pre-fill contact fields from resolved account
    final email = result['email'] as String?;
    final phone = result['phone_number'] as String?;
    if (email != null) _emailController.text = email;
    if (phone != null) _phoneController.text = phone;

    _goNext();
  }

  Future<void> _handleSendOtp() async {
    setState(() => _isLoading = true);
    try {
      if (_useEmail) {
        if (!_emailController.text.contains('@')) {
          _showError('Please enter a valid email.');
          return;
        }
        // Trigger email OTP via Supabase
        await _supabaseService.signUpWithEmail(
          email: _emailController.text.trim(),
        );
        _showSuccess('Code sent to ${_emailController.text}');
      } else {
        if (_phoneController.text.length < 10) {
          _showError('Please enter a valid phone number.');
          return;
        }
        final res = await _supabaseService.sendPhoneOtp(
          _phoneController.text.trim(),
        );
        if (res['success']) {
          _showSuccess('Code sent to ${_phoneController.text}');
        } else {
          _showError(res['message']);
        }
      }
    } catch (e) {
      _showError('Failed to send code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

Future<void> _handleVerifyOtp() async {
  if (_otpController.text.isEmpty) {
    _showError('Please enter the verification code.');
    return;
  }

  setState(() => _isLoading = true);
  try {
    // You need to create this method in SupabaseService.dart
    final res = await _supabaseService.verifyOtpCode(
      email: _useEmail ? _emailController.text.trim() : null,
      phone: !_useEmail ? _phoneController.text.trim() : null,
      token: _otpController.text.trim(),
    );

    if (res['success']) {
      _goNext(); // Move to Step 3: New PIN
    } else {
      _showError(res['message'] ?? 'Invalid or expired code.');
    }
  } catch (e) {
    _showError('Verification error: $e');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _handleSetNewPin() async {
    if (_resolvedUserId == null) {
      _showError('Session expired. Please start over.');
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
      return;
    }
    if (_newPin != _confirmPin) {
      _showError('PINs do not match.');
      setState(() { _newPin = ''; _confirmPin = ''; _pinConfirmStep = false; });
      return;
    }

    setState(() => _isLoading = true);
    final result = await _supabaseService.setNewPin(
      userId: _resolvedUserId!,
      newPin: _newPin,
    );
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (result['success']) {
      if (widget.fromProfile) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _PinChangedDialog(),
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
    } else {
      _showError(result['message']);
    }
  }

  // ── PIN input ──────────────────────────────────────────────────────────────

  void _onPinKey(String key) {
    if (_pinConfirmStep) {
      if (_confirmPin.length >= 6) return;
      setState(() => _confirmPin += key);
      if (_confirmPin.length == 6 && _isPageValid()) {
        _handleSetNewPin();
      }
    } else {
      if (_newPin.length >= 6) return;
      setState(() => _newPin += key);
      if (_newPin.length == 6) {
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
      if (_newPin.isEmpty) return;
      setState(() => _newPin = _newPin.substring(0, _newPin.length - 1));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
          title: Text(_stepTitle(),
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                  onPageChanged: (p) =>
                      setState(() => _currentPage = p),
                  children: [
                    _buildIdentityPage(),
                    _buildOtpPage(),
                    _buildNewPinPage(),
                  ],
                ),
              ),
              if (_currentPage != 2) _buildFooter(),
              if (_currentPage == 2) _buildPinKeypadFooter(),
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
        title: const Text('Cancel PIN reset?'),
        content: const Text('Going back will cancel the process.'),
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

  // ── Pages ──────────────────────────────────────────────────────────────────

  Widget _buildIdentityPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify Your Identity',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Enter the information you registered with. '
            'This ensures only you can reset your PIN.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            hintText: 'First Name',
            controller: _firstNameController,
            prefixIcon:
                const Icon(Icons.person_outline, color: Colors.white),
          ),
          const SizedBox(height: 12),
          CustomTextField(
            hintText: 'Last Name',
            controller: _lastNameController,
            prefixIcon:
                const Icon(Icons.person_outline, color: Colors.white),
          ),
          const SizedBox(height: 12),

          // Date of birth picker
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.buttonOutlineBlue, width: 2),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    _dobValue == null
                        ? 'Date of Birth'
                        : _dobValue!,
                    style: TextStyle(
                      color: _dobValue == null
                          ? Colors.white60
                          : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify with a Code',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Choose how you want to receive your verification code.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Toggle email / phone
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.buttonOutlineBlue, width: 2),
            ),
            child: Row(
              children: [
                _buildToggleTab(
                  label: 'Email',
                  icon: Icons.email_outlined,
                  selected: _useEmail,
                  onTap: () => setState(() {
                    _useEmail = true;
                    _otpController.clear();
                  }),
                ),
                _buildToggleTab(
                  label: 'Phone',
                  icon: Icons.phone_android_outlined,
                  selected: !_useEmail,
                  onTap: () => setState(() {
                    _useEmail = false;
                    _otpController.clear();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_useEmail) ...[
            const Text('Your registered email',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            CustomTextField(
              hintText: 'Email Address',
              controller: _emailController,
              prefixIcon: const Icon(Icons.email_outlined,
                  color: Colors.white),
            ),
          ] else ...[
            const Text('Your registered phone number',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            CustomTextField(
              hintText: '09XXXXXXXXX',
              controller: _phoneController,
              prefixIcon: const Icon(Icons.phone_android_outlined,
                  color: Colors.white),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleSendOtp,
              icon: const Icon(Icons.send_outlined,
                  color: Colors.white70, size: 18),
              label: const Text('Send Code',
                  style: TextStyle(color: Colors.white70)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Enter verification code',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          CustomTextField(
            hintText: _useEmail
                ? 'Enter 8-digit code'
                : 'Enter 6-digit code',
            controller: _otpController,
            prefixIcon:
                const Icon(Icons.lock_outline, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPinPage() {
    final currentDisplay =
        _pinConfirmStep ? _confirmPin : _newPin;
    final title =
        _pinConfirmStep ? 'Confirm your new PIN' : 'Create new PIN';
    final subtitle = _pinConfirmStep
        ? 'Re-enter your new PIN'
        : 'Enter a 6-digit PIN';
    final showMismatch = _pinConfirmStep &&
        _confirmPin.length == 6 &&
        _confirmPin != _newPin;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_reset, size: 60, color: Colors.white70),
        const SizedBox(height: 20),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle,
            style:
                const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 28),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < currentDisplay.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: filled ? 16 : 14,
              height: filled ? 16 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: showMismatch
                    ? Colors.redAccent
                    : filled
                        ? Colors.white
                        : Colors.white.withOpacity(0.25),
                border: Border.all(
                  color: showMismatch
                      ? Colors.redAccent
                      : Colors.white.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
            );
          }),
        ),

        if (showMismatch) ...[
          const SizedBox(height: 10),
          const Text('PINs do not match. Try again.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],

        if (_pinConfirmStep) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _pinConfirmStep = false;
              _newPin = '';
              _confirmPin = '';
            }),
            child: const Text('Re-enter PIN',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
      ],
    );
  }

  // ── Keypad footer for PIN page ─────────────────────────────────────────────

  Widget _buildPinKeypadFooter() {
    // Auto-reset mismatched confirm PIN
    if (_confirmPin.length == 6 && _confirmPin != _newPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _confirmPin = '');
        });
      });
    }

    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (!_isLoading)
            ...keys.map((row) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((key) {
                  if (key.isEmpty) {
                    return const SizedBox(width: 72, height: 72);
                  }
                  return _buildPinKey(key);
                }).toList(),
              );
            }),
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

  Widget _buildPinKey(String key) {
    final isDelete = key == '⌫';
    return GestureDetector(
      onTap: () => isDelete ? _onPinDelete() : _onPinKey(key),
      child: Container(
        width: 72,
        height: 72,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDelete
              ? Colors.transparent
              : Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
          border: isDelete
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Center(
          child: isDelete
              ? const Icon(Icons.backspace_outlined,
                  color: Colors.white70, size: 22)
              : Text(key,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  )),
        ),
      ),
    );
  }

  // ── Standard footer ────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final bool valid = _isPageValid();
    final String label = switch (_currentPage) {
      0 => 'Continue',
      1 => 'Verify Code',
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
              child: const Text('Back',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  // ── Toggle tab ─────────────────────────────────────────────────────────────

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
}

// ── Success Dialog ─────────────────────────────────────────────────────────

class _PinChangedDialog extends StatelessWidget {
  const _PinChangedDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.primaryBlue,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.check_circle_outline,
              color: Colors.white, size: 70),
          const SizedBox(height: 16),
          const Text('PIN Updated!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Your PIN has been updated. Please log in with your new PIN.',
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