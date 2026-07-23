import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/services/supabase_service.dart';

enum EmailChangeStep {
  enterEmail,
  sending,
  awaitingCode,
  verifying,
  verified,
  error,
}

/// Drives the "change my email" flow for an existing, signed-in user.
///
/// Uses Supabase Auth's email-change mechanism:
///   - [SupabaseClient.auth.updateUser] with the new email sends a
///     confirmation code (OtpType.emailChange) to the NEW address.
///   - [SupabaseClient.auth.verifyOTP] with type emailChange finalizes it.
///
/// A duplicate pre-check via [SupabaseService.checkDuplicateSignup] surfaces
/// "email already in use" before the auth call. Persisting the verified email
/// to user_accounts / user_field_values is the caller's job
/// (ProfileController.persistVerifiedEmail).
///
/// NOTE: assumes the project's "Secure email change" (dual-confirmation) auth
/// setting is disabled; otherwise the change also requires confirming from the
/// old address and this single-code flow will not finalize.
class EmailChangeController extends ChangeNotifier {
  EmailChangeController({
    required this.currentEmail,
    SupabaseService? supabaseService,
    SupabaseClient? supabaseClient,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _supabase = supabaseClient ?? Supabase.instance.client;

  final String currentEmail;
  final SupabaseService _supabaseService;
  final SupabaseClient _supabase;

  static const int _maxVerifyAttempts = 5;
  static const int _resendCooldownSeconds = 60;

  EmailChangeStep step = EmailChangeStep.enterEmail;
  String? errorMessage;
  int resendCountdown = 0;
  int _attempts = 0;

  // The email currently being verified (already validated + trimmed).
  String pendingEmail = '';

  Timer? _resendTimer;

  static final RegExp _emailRegExp =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Returns null when valid, else an error string.
  static String? validateFormat(String raw) {
    final email = raw.trim();
    if (email.isEmpty) return 'Enter an email address.';
    if (!_emailRegExp.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  Future<void> submitEmail(String rawEmail) async {
    final email = rawEmail.trim();
    final validationError = validateFormat(email);
    if (validationError != null) {
      errorMessage = validationError;
      step = EmailChangeStep.enterEmail;
      notifyListeners();
      return;
    }

    if (email.toLowerCase() == currentEmail.trim().toLowerCase()) {
      errorMessage = 'This is already your current email.';
      step = EmailChangeStep.enterEmail;
      notifyListeners();
      return;
    }

    pendingEmail = email;
    await _sendChange();
  }

  Future<void> _sendChange() async {
    step = EmailChangeStep.sending;
    errorMessage = null;
    _attempts = 0;
    notifyListeners();

    try {
      // Reject an email already registered to another account before we touch
      // the auth identity.
      final dup = await _supabaseService.checkDuplicateSignup(
        email: pendingEmail,
      );
      if (dup['success'] != true && dup['field'] == 'email') {
        errorMessage = 'Email already in use.';
        step = EmailChangeStep.enterEmail;
        notifyListeners();
        return;
      }

      await _supabase.auth.updateUser(
        UserAttributes(email: pendingEmail),
      );

      step = EmailChangeStep.awaitingCode;
      _startResendCountdown();
      notifyListeners();
    } on AuthException catch (e) {
      errorMessage = e.message;
      step = EmailChangeStep.error;
      notifyListeners();
    } catch (e) {
      errorMessage = 'Connection error. Please try again.';
      step = EmailChangeStep.error;
      notifyListeners();
    }
  }

  Future<void> resend() async {
    if (resendCountdown > 0 || pendingEmail.isEmpty) return;
    await _sendChange();
  }

  void _startResendCountdown() {
    resendCountdown = _resendCooldownSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (resendCountdown > 0) {
        resendCountdown--;
        notifyListeners();
      } else {
        t.cancel();
      }
    });
  }

  Future<bool> verifyOtp(String code) async {
    final trimmedCode = code.trim();
    step = EmailChangeStep.verifying;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.auth.verifyOTP(
        email: pendingEmail,
        token: trimmedCode,
        type: OtpType.emailChange,
      );

      if (response.user != null) {
        step = EmailChangeStep.verified;
        _resendTimer?.cancel();
        notifyListeners();
        return true;
      }

      _attempts++;
      errorMessage = 'Incorrect code. Please try again.';
      if (_attempts >= _maxVerifyAttempts) {
        errorMessage = 'Too many incorrect attempts. Request a new code.';
      }
      step = EmailChangeStep.awaitingCode;
      notifyListeners();
      return false;
    } on AuthException catch (e) {
      _attempts++;
      errorMessage = e.message;
      step = EmailChangeStep.awaitingCode;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Verification error. Please try again.';
      step = EmailChangeStep.awaitingCode;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}
