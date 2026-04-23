import 'package:flutter/material.dart';
import 'package:sappiire/mobile/utils/snackbar_utils.dart';
import 'package:sappiire/services/auth/password_reset_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordController extends ChangeNotifier {
  final _passwordResetService = PasswordResetService();

  int currentPage = 0;
  bool isLoading = false;
  bool useEmail = true;

  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();
  bool showNewPassword = false;
  bool showConfirmPassword = false;

  String? resolvedEmail;

  String get stepTitle => switch (currentPage) {
    0 => 'Step 1 of 3 — Identify Account',
    1 => 'Step 2 of 3 — Verify Identity',
    _ => 'Step 3 of 3 — New Password',
  };

  bool get pageValid => switch (currentPage) {
    0 => useEmail
        ? emailCtrl.text.contains('@')
        : phoneCtrl.text.length >= 10,
    1 => useEmail
        ? otpCtrl.text.length == 8
        : otpCtrl.text.length == 6,
    _ => newPasswordCtrl.text.length >= 6 &&
        newPasswordCtrl.text == confirmPasswordCtrl.text,
  };

  void goNext(PageController pageController) => pageController.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  void goPrev(PageController pageController) => pageController.previousPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  void setPage(int p) {
    currentPage = p;
    notifyListeners();
  }

  void togglePasswordVisibility({required bool isNew}) {
    if (isNew) {
      showNewPassword = !showNewPassword;
    } else {
      showConfirmPassword = !showConfirmPassword;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    phoneCtrl.dispose();
    otpCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────

  Future<bool> handleSendEmailOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.sendEmailOtp(emailCtrl.text);
      if (result['success'] != true) {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Failed to send OTP.');
        return false;
      }
      resolvedEmail = result['email']?.toString();
      return true;
    } catch (e) {
      SnackbarUtils.showError(context, 'Failed to send OTP: ${e.toString()}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleResendEmailOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.resendEmailOtp(emailCtrl.text);
      if (result['success'] == true) {
        SnackbarUtils.showSuccess(context, result['message']?.toString() ?? 'Code resent! Check your email.');
      } else {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Failed to resend OTP.');
      }
      return result['success'] == true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleVerifyEmailOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.verifyEmailOtp(
        email: emailCtrl.text,
        otp: otpCtrl.text,
      );
      if (result['success'] != true) {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Invalid or expired code.');
        return false;
      }
      return true;
    } catch (e) {
      SnackbarUtils.showError(context, 'Verification error: ${e.toString()}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleSendPhoneOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.sendPhoneOtp(phoneCtrl.text);
      if (result['success'] == true) {
        resolvedEmail = result['email']?.toString();
        return true;
      } else {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Failed to send OTP.');
        return false;
      }
    } catch (e) {
      SnackbarUtils.showError(context, 'Error: ${e.toString()}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleResendPhoneOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.resendPhoneOtp(phoneCtrl.text);
      if (result['success'] == true) {
        SnackbarUtils.showSuccess(context, result['message']?.toString() ?? 'Code resent!');
      } else {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Failed to resend OTP.');
      }
      return result['success'] == true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleVerifyPhoneOtp(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.verifyPhoneOtp(
        phone: phoneCtrl.text,
        otp: otpCtrl.text,
      );
      if (result['success'] == true) {
        if (resolvedEmail != null) {
          try {
            await _passwordResetService.bootstrapEmailOtpForResolvedEmail(resolvedEmail);
          } catch (_) {}
        }
        return true;
      } else {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Invalid or expired code.');
        return false;
      }
    } catch (e) {
      SnackbarUtils.showError(context, 'Verification error: ${e.toString()}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> handleChangePassword(BuildContext context, {required bool fromProfile}) async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await _passwordResetService.updateCurrentUserPassword(
        newPasswordCtrl.text,
      );

      if (result['success'] != true) {
        SnackbarUtils.showError(context, result['message']?.toString() ?? 'Failed to update password. Please try again.');
        return false;
      }

      if (fromProfile) {
        SnackbarUtils.showSuccess(context, 'Password updated successfully!');
      } else {
        await Supabase.instance.client.auth.signOut();
      }
      return true;
    } catch (e) {
      SnackbarUtils.showError(context, 'Error: ${e.toString()}');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
