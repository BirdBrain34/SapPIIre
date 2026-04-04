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
      final account = await _supabase
          .from('user_accounts')
          .select('user_id, email, is_active')
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'message': 'No account found with that email.',
        };
      }
      if (account['is_active'] == false) {
        return {'success': false, 'message': 'This account is deactivated.'};
      }

      await _supabase.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: false,
      );

      return {
        'success': true,
        'user_id': account['user_id'],
        'email': account['email'],
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
      final phoneRows = await _supabase
          .from('user_field_values')
          .select('user_id, field_value')
          .eq('field_value', phone.trim())
          .limit(1)
          .maybeSingle();

      if (phoneRows == null) {
        return {
          'success': false,
          'message': 'No account found with that phone number.',
        };
      }

      final resolvedUserId = phoneRows['user_id']?.toString();
      if (resolvedUserId == null || resolvedUserId.isEmpty) {
        return {
          'success': false,
          'message': 'No account found with that phone number.',
        };
      }

      final account = await _supabase
          .from('user_accounts')
          .select('email')
          .eq('user_id', resolvedUserId)
          .maybeSingle();

      final sendResult = await _supabaseService.sendPhoneOtp(phone.trim());
      if (sendResult['success'] != true) {
        return sendResult;
      }

      return {
        'success': true,
        'user_id': resolvedUserId,
        'email': account?['email'],
      };
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
