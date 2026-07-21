import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sappiire/mobile/utils/snackbar_utils.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/services/password/password_validator.dart';
import 'package:sappiire/services/supabase_service.dart';

enum ContactMethod { email, phone, both }

class SignupController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  // Text editing controllers.
  final lastNameCtrl = TextEditingController();
  final firstNameCtrl = TextEditingController();
  final middleNameCtrl = TextEditingController();
  final dobCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final placeOfBirthCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final emailOtpCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final phoneOtpCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  List<TextEditingController> get allControllers => [
    lastNameCtrl, firstNameCtrl, middleNameCtrl,
    dobCtrl, addressCtrl, placeOfBirthCtrl,
    emailCtrl, emailOtpCtrl,
    phoneCtrl, phoneOtpCtrl,
    usernameCtrl, passwordCtrl, confirmPasswordCtrl,
  ];

  // State.
  ContactMethod contactMethod = ContactMethod.email;
  int currentPage = 0;
  bool isLoading = false;
  String? verifiedUserId;
  String sex = '';
  String maritalStatus = '';
  bool showPassword = false;
  bool showConfirmPassword = false;

  // Email flow state
  bool emailOtpSent = false;
  bool emailVerified = false;

  // Phone flow state
  bool phoneOtpSent = false;
  bool phoneVerified = false;

  // OTP countdown timers
  Timer? emailOtpTimer;
  int emailOtpCountdown = 0;
  Timer? phoneOtpTimer;
  int phoneOtpCountdown = 0;

  // Computed values.
  List<int> get pageSequence {
    switch (contactMethod) {
      case ContactMethod.email:
        return [0, 1, 2, 4];
      case ContactMethod.phone:
        return [0, 1, 3, 4];
      case ContactMethod.both:
        return [0, 1, 2, 3, 4];
    }
  }

  int get totalSteps => pageSequence.length;
  int get currentStepIndex => currentPage;
  int get currentActualPage => pageSequence[currentPage];

  String get stepTitle {
    switch (currentActualPage) {
      case 0: return 'Step 1 of $totalSteps — Personal Info';
      case 1: return 'Step 2 of $totalSteps — Contact Method';
      case 2: return 'Email Verification';
      case 3: return 'Phone Verification';
      case 4: return 'Step $totalSteps of $totalSteps — Credentials';
      default: return 'Sign Up';
    }
  }

  bool get currentPageValid {
    switch (currentActualPage) {
      case 0:
        return lastNameCtrl.text.isNotEmpty &&
            firstNameCtrl.text.isNotEmpty &&
            dobCtrl.text.isNotEmpty &&
            addressCtrl.text.isNotEmpty &&
            placeOfBirthCtrl.text.isNotEmpty &&
            sex.isNotEmpty &&
            maritalStatus.isNotEmpty;
      case 1:
        return true;
      case 2:
        return emailVerified;
      case 3:
        return phoneVerified;
      case 4:
        return usernameCtrl.text.isNotEmpty &&
            validatePassword(passwordCtrl.text).isValid &&
            passwordCtrl.text == confirmPasswordCtrl.text;
      default:
        return false;
    }
  }

  // ── Init / Dispose ────────────────────────────────────────
  void init() {
    for (final c in allControllers) {
      c.addListener(() => notifyListeners());
    }
  }

  @override
  void dispose() {
    emailOtpTimer?.cancel();
    phoneOtpTimer?.cancel();
    for (final c in allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Timers ────────────────────────────────────────────────
  void startEmailCountdown() {
    emailOtpCountdown = 60;
    emailOtpTimer?.cancel();
    emailOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (emailOtpCountdown > 0) {
        emailOtpCountdown--;
        notifyListeners();
      } else {
        t.cancel();
      }
    });
  }

  void startPhoneCountdown() {
    phoneOtpCountdown = 120;
    phoneOtpTimer?.cancel();
    phoneOtpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (phoneOtpCountdown > 0) {
        phoneOtpCountdown--;
        notifyListeners();
      } else {
        t.cancel();
      }
    });
  }

  // ── Navigation ────────────────────────────────────────────
  void goNextPage(PageController pageController) {
    if (currentPage < totalSteps - 1) {
      currentPage++;
      pageController.animateToPage(
        currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      notifyListeners();
    }
  }

  void goPrevPage(PageController pageController) {
    if (currentPage > 0) {
      currentPage--;
      pageController.animateToPage(
        currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      notifyListeners();
    }
  }

  void setPage(int page) {
    currentPage = page;
    notifyListeners();
  }

  // ── Page Actions ──────────────────────────────────────────
  Future<bool> onNext(BuildContext context, PageController pageController) async {
    switch (currentActualPage) {
      case 0:
        goNextPage(pageController);
        return false;
      case 1:
        // Reset verification state when contact method page is passed
        emailVerified = false;
        phoneVerified = false;
        emailOtpSent = false;
        phoneOtpSent = false;
        goNextPage(pageController);
        return false;
      case 2:
        if (!emailOtpSent) {
          await handleSendEmailOtp(context);
        } else if (!emailVerified) {
          await handleVerifyEmailOtp(context, pageController);
        } else {
          goNextPage(pageController);
        }
        return false;
      case 3:
        if (!phoneOtpSent) {
          await handleSendPhoneOtp(context);
        } else if (!phoneVerified) {
          await handleVerifyPhoneOtp(context, pageController);
        } else {
          goNextPage(pageController);
        }
        return false;
      case 4:
        return await handleCreateAccount(context);
      default:
        return false;
    }
  }

  // ── Email actions ─────────────────────────────────────────
  Future<void> handleSendEmailOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      email: emailCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      isLoading = false;
      notifyListeners();
      if (context.mounted) SnackbarUtils.showError(context, dupCheck['message']);
      return;
    }

    // If this is an incomplete signup retry, reuse the existing user_id
    if (dupCheck['incomplete'] == true && dupCheck['user_id'] != null) {
      verifiedUserId = dupCheck['user_id'];
      // Send OTP to the existing incomplete account
      await _supabaseService.signInWithOtp(email: emailCtrl.text.trim());
      isLoading = false;
      notifyListeners();
      emailOtpSent = true;
      startEmailCountdown();
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Code sent to ${emailCtrl.text.trim()}');
      return;
    }

    final result = await _supabaseService.signUpWithEmail(
      email: emailCtrl.text.trim(),
    );
    isLoading = false;
    notifyListeners();
    if (result['success']) {
      verifiedUserId = result['user_id'];
      emailOtpSent = true;
      startEmailCountdown();
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Code sent to ${emailCtrl.text.trim()}');
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
    }
  }

  Future<void> handleVerifyEmailOtp(
    BuildContext context,
    PageController pageController,
  ) async {
    isLoading = true;
    notifyListeners();
    final result = await _supabaseService.verifyEmailOtp(
      email: emailCtrl.text.trim(),
      otp: emailOtpCtrl.text.trim(),
    );
    isLoading = false;
    notifyListeners();
    if (result['success']) {
      verifiedUserId = result['user_id'];
      emailVerified = true;
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Email verified!');
      goNextPage(pageController);
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
    }
  }

  Future<void> handleResendEmailOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();
    final result = await _supabaseService.resendEmailOtp(emailCtrl.text.trim());
    isLoading = false;
    notifyListeners();
    if (result['success'] == true) {
      startEmailCountdown();
      if (context.mounted) {
        SnackbarUtils.showSuccess(context, 'Code resent!');
      }
    } else {
      if (context.mounted) {
        SnackbarUtils.showError(
          context,
          result['message']?.toString() ?? 'Failed to resend.',
        );
      }
    }
  }

  void resetEmailOtp() {
    emailOtpSent = false;
    emailOtpCtrl.clear();
    notifyListeners();
  }

  // ── Phone actions ─────────────────────────────────────────
  Future<void> handleSendPhoneOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      phone: phoneCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      isLoading = false;
      notifyListeners();
      if (context.mounted) SnackbarUtils.showError(context, dupCheck['message']);
      return;
    }
    final result = await _supabaseService.sendPhoneOtp(phoneCtrl.text.trim());
    isLoading = false;
    notifyListeners();
    if (result['success']) {
      phoneOtpSent = true;
      startPhoneCountdown();
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Code sent to your phone!');
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
    }
  }

  Future<void> handleVerifyPhoneOtp(
    BuildContext context,
    PageController pageController,
  ) async {
    isLoading = true;
    notifyListeners();
    final result = await _supabaseService.verifyPhoneOtp(
      phone: phoneCtrl.text.trim(),
      otp: phoneOtpCtrl.text.trim(),
    );
    isLoading = false;
    notifyListeners();
    if (result['success']) {
      // Do NOT create the Supabase Auth user here for phone-only flow.
      // We don't have the real password yet — that's entered on the next page.
      // The Auth user is created in handleCreateAccount with the actual password.
      phoneVerified = true;
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Phone verified!');
      goNextPage(pageController);
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
    }
  }

  Future<void> handleResendPhoneOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();
    final result = await _supabaseService.sendPhoneOtp(phoneCtrl.text.trim());
    isLoading = false;
    notifyListeners();
    if (result['success']) {
      startPhoneCountdown();
      if (context.mounted) SnackbarUtils.showSuccess(context, 'Code resent!');
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
    }
  }

  void resetPhoneOtp() {
    phoneOtpSent = false;
    phoneOtpCtrl.clear();
    notifyListeners();
  }

  // ── Create account ────────────────────────────────────────
  Future<bool> handleCreateAccount(BuildContext context) async {
    final dupCheck = await _supabaseService.checkDuplicateSignup(
      username: usernameCtrl.text.trim(),
    );
    if (!dupCheck['success']) {
      if (context.mounted) SnackbarUtils.showError(context, dupCheck['message']);
      return false;
    }

    // For phone-only flow: Supabase Auth user doesn't exist yet.
    // Create it now with the real password using the synthetic email.
    if (contactMethod == ContactMethod.phone && verifiedUserId == null) {
      isLoading = true;
      notifyListeners();

      final syntheticEmail = _syntheticEmailForPhone(phoneCtrl.text.trim());
      final signupResult = await _supabaseService.signUpWithEmail(
        email: syntheticEmail,
        password: passwordCtrl.text,
        allowOtpRecovery: false,
      );

      isLoading = false;
      notifyListeners();

      if (signupResult['success'] != true) {
      if (context.mounted) {
        SnackbarUtils.showError(
          context,
          signupResult['message'] ?? 'Failed to create account. Try again.',
        );
      }
        return false;
      }
      verifiedUserId = signupResult['user_id'];
    }

    if (verifiedUserId == null) {
      if (context.mounted) SnackbarUtils.showError(context, 'Session expired. Please start over.');
      return false;
    }

    isLoading = true;
    notifyListeners();

    // For phone-only: pass null email so user_accounts.email stays null.
    // For email/both: pass the real email.
    final emailToSave = (contactMethod == ContactMethod.phone)
        ? null
        : emailCtrl.text.trim();

    final phoneToSave = (contactMethod == ContactMethod.email)
        ? null
        : phoneCtrl.text.trim();

    final result = await _supabaseService.saveProfileAfterVerification(
      userId: verifiedUserId!,
      username: usernameCtrl.text.trim(),
      password: passwordCtrl.text,
      email: emailToSave,
      phoneNumber: phoneToSave,
      firstName: firstNameCtrl.text.trim(),
      middleName: middleNameCtrl.text.trim(),
      lastName: lastNameCtrl.text.trim(),
      dateOfBirth: dobCtrl.text,
      birthplace: placeOfBirthCtrl.text.trim(),
      gender: sex == 'Male' ? 'M' : sex == 'Female' ? 'F' : sex,
      civilStatus: switch (maritalStatus) {
        'Single' => 'S',
        'Married' => 'M',
        'Widowed' => 'W',
        'Separated' => 'Sep',
        'Annulled' => 'A',
        _ => maritalStatus,
      },
      addressLine: addressCtrl.text.trim(),
    );

    isLoading = false;
    notifyListeners();

    if (result['success']) {
      verifiedUserId = result['user_id'];
      return true;
    } else {
      if (context.mounted) SnackbarUtils.showError(context, result['message']);
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  /// Generates a deterministic synthetic email for phone-only Supabase Auth users.
  /// This is stored only in Supabase Auth — user_accounts.email stays null.
  String _syntheticEmailForPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digits@sappiire.phone';
  }

  // ── Info scan ─────────────────────────────────────────────
  void applyScannedIdInfo(IdInformation result) {
    firstNameCtrl.text = result.firstName;
    middleNameCtrl.text = result.middleName;
    lastNameCtrl.text = result.lastName;
    dobCtrl.text = result.dateOfBirth;
    if (result.address.isNotEmpty) addressCtrl.text = result.address;
    if (result.placeOfBirth.isNotEmpty) {
      placeOfBirthCtrl.text = result.placeOfBirth;
    }
    if (result.sex.isNotEmpty) {
      sex = result.sex.toLowerCase().startsWith('f') ? 'Female' : 'Male';
    }
    if (result.maritalStatus.isNotEmpty) {
      final l = result.maritalStatus.toLowerCase();
      if (l.contains('single')) {
        maritalStatus = 'Single';
      } else if (l.contains('married')) {
        maritalStatus = 'Married';
      } else if (l.contains('widow')) {
        maritalStatus = 'Widowed';
      } else if (l.contains('separated')) {
        maritalStatus = 'Separated';
      } else if (l.contains('annul')) {
        maritalStatus = 'Annulled';
      }
    }
    notifyListeners();
  }

  // ── Date picker ───────────────────────────────────────────
  Future<void> selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendar,
      keyboardType: TextInputType.text,
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
      dobCtrl.text = '${picked.month}/${picked.day}/${picked.year}';
      notifyListeners();
    }
  }
}