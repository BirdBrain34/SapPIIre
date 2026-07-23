import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/auth/password_reset_service.dart';
import 'package:sappiire/services/supabase_service.dart';

enum OtpChannel { email, phone }

enum OtpStep {
  loadingAccount,
  selectChannel,
  sending,
  awaitingCode,
  verifying,
  verified,
  error,
}

/// Pre-transmission "confirm it's you" OTP gate for the QR handshake.
///
/// Mirrors the e-wallet transaction-OTP pattern: after a QR scan (and after
/// any existing template-match validation) passes, this controller challenges
/// the signed-in user to prove fresh possession of their REGISTERED email or
/// phone before transmission is allowed to proceed. It never touches the
/// AES-256-GCM/RSA envelope pipeline — it is a precondition gate that sits
/// strictly upstream of it.
///
/// Reuses existing, already-proven OTP rails instead of introducing new
/// tables or Edge Functions:
///   - Email channel -> Supabase Auth signInWithOtp + verifyOTP, via
///     [PasswordResetService] (the same calls ChangePasswordController
///     already uses for a logged-in user).
///   - Phone channel -> send-phone-otp / verify-phone-otp Edge Functions.
///     Send goes through [SupabaseService.sendPhoneOtp] (already correct).
///     Verify calls the Edge Function directly rather than
///     [SupabaseService.verifyPhoneOtp], because that helper calls the
///     verify_and_consume_phone_otp RPC directly and bypasses the Edge
///     Function's 10-attempts/15-min rate limit. This new, sensitive gate
///     should get the full rate limit.
///
/// The destination address is ALWAYS resolved server-side from the caller's
/// own `user_accounts` row. It is never accepted from the UI.
class QrTransmissionOtpController extends ChangeNotifier {
  QrTransmissionOtpController({
    required this.userId,
    required this.sessionId,
    SupabaseService? supabaseService,
    PasswordResetService? passwordResetService,
    SupabaseClient? supabaseClient,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _passwordResetService = passwordResetService ?? PasswordResetService(),
        _supabase = supabaseClient ?? Supabase.instance.client;

  final String userId;
  final String sessionId;
  final SupabaseService _supabaseService;
  final PasswordResetService _passwordResetService;
  final SupabaseClient _supabase;

  static const int _maxVerifyAttempts = 5;
  static const int _resendCooldownSeconds = 60;

  OtpStep step = OtpStep.loadingAccount;
  String? registeredEmail;
  String? registeredPhone;
  OtpChannel? channel;
  String? errorMessage;
  int resendCountdown = 0;
  int _attempts = 0;

  Timer? _resendTimer;

  Future<void> loadAccountChannels() async {
    step = OtpStep.loadingAccount;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _supabaseService.getAccountInfo(userId);
      if (result['success'] != true) {
        errorMessage = 'Could not load your account. Please try again.';
        step = OtpStep.error;
        notifyListeners();
        return;
      }

      final data = result['data'] as Map<String, dynamic>? ?? {};
      registeredEmail = (data['email'] as String?)?.trim();
      registeredPhone = (data['phone_number'] as String?)?.trim();

      final hasEmail = registeredEmail != null && registeredEmail!.isNotEmpty;
      final hasPhone = registeredPhone != null && registeredPhone!.isNotEmpty;

      if (!hasEmail && !hasPhone) {
        errorMessage =
            'No verified email or phone number on file. Please update '
            'your profile before sending data.';
        step = OtpStep.error;
        notifyListeners();
        return;
      }

      // Skip the picker when only one channel is actually available.
      if (hasEmail && !hasPhone) {
        channel = OtpChannel.email;
        await sendOtp();
        return;
      }
      if (hasPhone && !hasEmail) {
        channel = OtpChannel.phone;
        await sendOtp();
        return;
      }

      step = OtpStep.selectChannel;
      notifyListeners();
    } catch (e) {
      errorMessage = 'Could not load your account. Please try again.';
      step = OtpStep.error;
      notifyListeners();
    }
  }

  Future<void> selectChannel(OtpChannel value) async {
    channel = value;
    await sendOtp();
  }

  /// Masked destination for display (never show the raw address).
  String get maskedDestination {
    if (channel == OtpChannel.email) {
      final email = registeredEmail ?? '';
      final at = email.indexOf('@');
      if (at <= 1) return email;
      return '${email.substring(0, 1)}***${email.substring(at)}';
    }
    final phone = registeredPhone ?? '';
    if (phone.length <= 4) return phone;
    final maskedLength = phone.length - 4;
    final masked = List.filled(maskedLength, '*').join();
    final visible = phone.substring(phone.length - 4);
    return '$masked$visible';
  }

  Future<void> sendOtp() async {
    if (channel == null) return;
    step = OtpStep.sending;
    errorMessage = null;
    _attempts = 0;
    notifyListeners();

    try {
      Map<String, dynamic> result;
      if (channel == OtpChannel.email) {
        result = await _passwordResetService.sendEmailOtp(registeredEmail!);
      } else {
        result = await _supabaseService.sendPhoneOtp(registeredPhone!);
      }

      if (result['success'] != true) {
        errorMessage = result['message']?.toString() ?? 'Failed to send code.';
        step = OtpStep.error;
        notifyListeners();
        return;
      }

      step = OtpStep.awaitingCode;
      _startResendCountdown();
      notifyListeners();
    } catch (e) {
      errorMessage = 'Connection error. Please try again.';
      step = OtpStep.error;
      notifyListeners();
    }
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
    if (channel == null) return false;
    final trimmedCode = code.trim();
    step = OtpStep.verifying;
    errorMessage = null;
    notifyListeners();

    try {
      bool verified;
      String? failureMessage;

      if (channel == OtpChannel.email) {
        final result = await _passwordResetService.verifyEmailOtp(
          email: registeredEmail!,
          otp: trimmedCode,
        );
        verified = result['success'] == true;
        failureMessage = result['message']?.toString();
      } else {
        // Direct Edge Function call — see class doc for why this bypasses
        // SupabaseService.verifyPhoneOtp.
        final invokeResult = await _supabase.functions.invoke(
          'verify-phone-otp',
          body: {'phone': registeredPhone, 'otp': trimmedCode},
        );
        final data = invokeResult.data;
        verified = data is Map && data['success'] == true;
        failureMessage = data is Map ? data['message']?.toString() : null;
      }

      if (verified) {
        step = OtpStep.verified;
        _resendTimer?.cancel();
        notifyListeners();

        unawaited(AuditLogService().log(
          actionType: kAuditQrTransmissionOtpVerified,
          category: kCategorySession,
          severity: kSeverityInfo,
          actorId: userId,
          targetType: 'form_submission',
          targetId: sessionId,
          details: {'channel': channel!.name},
        ));

        return true;
      }

      _attempts++;
      errorMessage = failureMessage ?? 'Incorrect code. Please try again.';

      if (_attempts >= _maxVerifyAttempts) {
        errorMessage = 'Too many incorrect attempts. Request a new code.';

        unawaited(AuditLogService().log(
          actionType: kAuditQrTransmissionOtpFailed,
          category: kCategorySession,
          severity: kSeverityWarning,
          actorId: userId,
          targetType: 'form_submission',
          targetId: sessionId,
          details: {'channel': channel!.name, 'attempts': _attempts},
        ));
      }

      step = OtpStep.awaitingCode;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Verification error. Please try again.';
      step = OtpStep.awaitingCode;
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