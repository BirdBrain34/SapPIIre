import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffEmailService {
  static final StaffEmailService _instance = StaffEmailService._internal();
  factory StaffEmailService() => _instance;
  StaffEmailService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  String _normalizedEmail(String email) => email.trim().toLowerCase();

  Future<Map<String, dynamic>> sendAccountCreationOtp({
    required String email,
  }) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: _normalizedEmail(email),
        shouldCreateUser: true,
      );
      return {
        'success': true,
        'message': 'OTP sent. Ask the staff member to check their email.',
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send OTP: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> validatePendingSetupEmail({
    required String email,
  }) async {
    try {
      final normalizedEmail = _normalizedEmail(email);
      final account = await _supabase
          .from('staff_accounts')
          .select('cswd_id, is_active, account_status, is_first_login')
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'message': 'No pending setup account found for this email.',
        };
      }

      if (account['is_active'] == false ||
          account['account_status'] == 'deactivated') {
        return {
          'success': false,
          'message':
              'This account has been deactivated. Contact your administrator.',
        };
      }

      if (account['is_first_login'] != true) {
        return {
          'success': false,
          'message':
              'This account is already set up. Use Forgot password instead.',
        };
      }

      return {
        'success': true,
        'cswd_id': account['cswd_id'] as String,
        'message': 'Account found. Enter the OTP sent during account creation.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> sendPasswordResetOtp({
    required String email,
  }) async {
    try {
      final normalizedEmail = _normalizedEmail(email);

      final account = await _supabase
          .from('staff_accounts')
          .select('cswd_id, is_active, account_status, is_first_login')
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (account == null) {
        return {
          'success': true,
          'message': 'If this email is registered, a reset code has been sent.',
        };
      }

      if (account['is_active'] == false ||
          account['account_status'] == 'deactivated') {
        return {
          'success': false,
          'message':
              'This account has been deactivated. Contact your administrator.',
        };
      }

      if (account['is_first_login'] == true) {
        return {
          'success': false,
          'message':
              'This account is still in initial setup. Use New staff setup instead.',
        };
      }

      await _supabase.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: false,
      );

      if (kDebugMode) {
        debugPrint(
          'StaffEmailService.sendPasswordResetOtp sent for $normalizedEmail',
        );
      }

      return {
        'success': true,
        'message': 'If this email is registered, a reset code has been sent.',
      };
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'StaffEmailService.sendPasswordResetOtp auth error: ${e.message}',
        );
      }
      return {'success': false, 'message': e.message};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StaffEmailService.sendPasswordResetOtp error: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final normalizedEmail = _normalizedEmail(email);

      final verifyRes = await _supabase.auth.verifyOTP(
        email: normalizedEmail,
        token: otp.trim(),
        type: OtpType.email,
      );

      if (verifyRes.user == null) {
        return {'success': false, 'message': 'Invalid or expired reset code.'};
      }

      final account = await _supabase
          .from('staff_accounts')
          .select('cswd_id, is_active, account_status, is_first_login')
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'message': 'Staff account not found for this email.',
        };
      }

      if (account['is_active'] == false ||
          account['account_status'] == 'deactivated') {
        return {
          'success': false,
          'message':
              'This account has been deactivated. Contact your administrator.',
        };
      }

      return {
        'success': true,
        'cswd_id': account['cswd_id'] as String,
        'message': 'Code verified.',
      };
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'StaffEmailService.verifyPasswordResetOtp auth error: ${e.message}',
        );
      }
      return {'success': false, 'message': e.message};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StaffEmailService.verifyPasswordResetOtp error: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> verifyPendingSetupOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final normalizedEmail = _normalizedEmail(email);

      final account = await _supabase
          .from('staff_accounts')
          .select('cswd_id, is_active, account_status, is_first_login')
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'message': 'No pending setup account found for this email.',
        };
      }

      if (account['is_active'] == false ||
          account['account_status'] == 'deactivated') {
        return {
          'success': false,
          'message':
              'This account has been deactivated. Contact your administrator.',
        };
      }

      if (account['is_first_login'] != true) {
        return {
          'success': false,
          'message':
              'This account is already set up. Use Forgot password instead.',
        };
      }

      final verifyRes = await _supabase.auth.verifyOTP(
        email: normalizedEmail,
        token: otp.trim(),
        type: OtpType.email,
      );

      if (verifyRes.user == null) {
        return {'success': false, 'message': 'Invalid or expired setup code.'};
      }

      return {
        'success': true,
        'cswd_id': account['cswd_id'] as String,
        'message': 'Code verified.',
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
