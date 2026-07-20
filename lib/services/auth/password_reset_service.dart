import 'package:sappiire/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordResetService {
  PasswordResetService({
    SupabaseClient? supabaseClient,
    SupabaseService? supabaseService,
  }) : _supabase = supabaseClient ?? Supabase.instance.client,
       _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseClient _supabase;
  final SupabaseService _supabaseService;

  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    try {
      final normalizedEmail = email.trim();

      await _supabase.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: false,
      );

      return {
        'success': true,
        'email': normalizedEmail,
      };
    } on AuthException catch (e) {
      return {
        'success': false,
        'message': e.message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send OTP: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> resendEmailOtp(String email) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: false,
      );
      return {'success': true, 'message': 'Code resent! Check your email.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to resend: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email.trim(),
        token: otp.trim(),
        type: OtpType.email,
      );

      if (response.user == null) {
        return {'success': false, 'message': 'Invalid or expired code.'};
      }

      return {'success': true, 'user_id': response.user!.id};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': 'Verification error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      return await _supabaseService.sendPhoneOtp(phone.trim());
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> resendPhoneOtp(String phone) {
    return _supabaseService.sendPhoneOtp(phone.trim());
  }

  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) {
    return _supabaseService.verifyPhoneOtp(
      phone: phone.trim(),
      otp: otp.trim(),
    );
  }

  Future<void> bootstrapEmailOtpForResolvedEmail(String? email) async {
    if (email == null || email.trim().isEmpty) {
      return;
    }
    await _supabase.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: false,
    );
  }

  Future<Map<String, dynamic>> updateCurrentUserPassword(
    String newPassword,
  ) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (response.user == null) {
        return {
          'success': false,
          'message': 'Failed to update password. Please try again.',
        };
      }

      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
