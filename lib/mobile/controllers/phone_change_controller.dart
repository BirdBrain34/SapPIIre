import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/services/supabase_service.dart';

enum PhoneChangeStep {
  enterPhone,
  sending,
  awaitingCode,
  verifying,
  verified,
  error,
}

/// Drives the "change my phone number" flow for an existing, signed-in user.
///
/// Reuses the same phone OTP rails as signup and the QR transmission gate:
///   - Send: [SupabaseService.sendPhoneOtp] (send-phone-otp Edge Function).
///   - Verify: direct call to the verify-phone-otp Edge Function so the flow
///     keeps the function's 10-attempts / 15-min server-side rate limit
///     (mirrors QrTransmissionOtpController's rationale).
///
/// This controller only proves possession of the NEW number. Persisting the
/// verified value to user_accounts / user_field_values is the caller's job
/// (ProfileController.persistVerifiedPhone).
class PhoneChangeController extends ChangeNotifier {
  PhoneChangeController({
    required this.userId,
    required this.currentPhone,
    SupabaseService? supabaseService,
    SupabaseClient? supabaseClient,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _supabase = supabaseClient ?? Supabase.instance.client;

  final String userId;
  final String currentPhone;
  final SupabaseService _supabaseService;
  final SupabaseClient _supabase;

  static const int _maxVerifyAttempts = 5;
  static const int _resendCooldownSeconds = 60;

  PhoneChangeStep step = PhoneChangeStep.enterPhone;
  String? errorMessage;
  int resendCountdown = 0;
  int _attempts = 0;

  // The phone number currently being verified (already validated + trimmed).
  String pendingPhone = '';

  Timer? _resendTimer;

  /// Validates a Philippine mobile number. Accepts `09XXXXXXXXX` (11 digits)
  /// or `+639XXXXXXXXX`. Returns null when valid, else an error string.
  static String? validatePhFormat(String raw) {
    final phone = raw.trim();
    if (phone.isEmpty) return 'Enter a phone number.';
    final local = RegExp(r'^09\d{9}$');
    final intl = RegExp(r'^\+639\d{9}$');
    if (local.hasMatch(phone) || intl.hasMatch(phone)) return null;
    return 'Enter a valid PH mobile number (09XXXXXXXXX).';
  }

  Future<void> submitPhone(String rawPhone) async {
    final phone = rawPhone.trim();
    final validationError = validatePhFormat(phone);
    if (validationError != null) {
      errorMessage = validationError;
      step = PhoneChangeStep.enterPhone;
      notifyListeners();
      return;
    }

    if (phone == currentPhone.trim()) {
      errorMessage = 'This is already your current number.';
      step = PhoneChangeStep.enterPhone;
      notifyListeners();
      return;
    }

    pendingPhone = phone;
    await _sendOtp();
  }

  Future<void> _sendOtp() async {
    step = PhoneChangeStep.sending;
    errorMessage = null;
    _attempts = 0;
    notifyListeners();

    try {
      final result = await _supabaseService.sendPhoneOtp(pendingPhone);
      if (result['success'] != true) {
        errorMessage = result['message']?.toString() ?? 'Failed to send code.';
        step = PhoneChangeStep.error;
        notifyListeners();
        return;
      }

      step = PhoneChangeStep.awaitingCode;
      _startResendCountdown();
      notifyListeners();
    } catch (e) {
      errorMessage = 'Connection error. Please try again.';
      step = PhoneChangeStep.error;
      notifyListeners();
    }
  }

  Future<void> resendOtp() async {
    if (resendCountdown > 0 || pendingPhone.isEmpty) return;
    await _sendOtp();
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

  /// Verifies the entered code against the pending phone. On success the
  /// masked step becomes [PhoneChangeStep.verified] and the verified number
  /// is available via [pendingPhone].
  Future<bool> verifyOtp(String code) async {
    final trimmedCode = code.trim();
    step = PhoneChangeStep.verifying;
    errorMessage = null;
    notifyListeners();

    try {
      final invokeResult = await _supabase.functions.invoke(
        'verify-phone-otp',
        body: {'phone': pendingPhone, 'otp': trimmedCode},
      );
      final data = invokeResult.data;
      final verified = data is Map && data['success'] == true;
      final failureMessage = data is Map ? data['message']?.toString() : null;

      if (verified) {
        step = PhoneChangeStep.verified;
        _resendTimer?.cancel();
        notifyListeners();
        return true;
      }

      _attempts++;
      errorMessage = failureMessage ?? 'Incorrect code. Please try again.';
      if (_attempts >= _maxVerifyAttempts) {
        errorMessage = 'Too many incorrect attempts. Request a new code.';
      }
      step = PhoneChangeStep.awaitingCode;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Verification error. Please try again.';
      step = PhoneChangeStep.awaitingCode;
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
