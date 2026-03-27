// Handles email delivery for web staff accounts.
// Uses Semaphore's email API (same key as SMS) for consistency.
// Falls back gracefully - email failure never blocks account creation.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffEmailService {
  static final StaffEmailService _instance = StaffEmailService._internal();
  factory StaffEmailService() => _instance;
  StaffEmailService._internal();

  static const _apiKey = 'fc4874818b2f98480dbba9e862b90334';
  static const _senderName = 'SapPIIre';
  final _supabase = Supabase.instance.client;

  // Welcome Email
  Future<void> sendWelcomeEmail({
    required String toEmail,
    required String displayName,
    required String username,
    required String temporaryPassword,
    required String role,
  }) async {
    final subject = 'Your SapPIIre Staff Account Has Been Created';
    final message = '''
Hello $displayName,

Your SapPIIre CSWD Portal staff account has been created.

Your login credentials:
  Username: $username
  Temporary Password: $temporaryPassword
  Role: $role

IMPORTANT: You will be required to change your password when you first log in.

Please keep these credentials secure and do not share them with anyone.

Access the portal at: https://sappiire.cswd.gov.ph

- SapPIIre System
City Social Welfare and Development Office
Santa Rosa City
''';

    try {
      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/email'),
        body: {
          'apikey': _apiKey,
          'to': toEmail,
          'subject': subject,
          'message': message,
          'sendername': _senderName,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('StaffEmailService: welcome email sent to $toEmail');
      } else {
        debugPrint('StaffEmailService: email failed - ${response.body}');
      }
    } catch (e) {
      debugPrint('StaffEmailService: sendWelcomeEmail error - $e');
    }
  }

  // Password Reset OTP
  Future<Map<String, dynamic>> sendPasswordResetOtp({
    required String email,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      final account = await _supabase
          .from('staff_accounts')
          .select('cswd_id, is_active, account_status')
          .eq('email', normalizedEmail)
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
          'message': 'This account has been deactivated. Contact your administrator.',
        };
      }

      final cswdId = account['cswd_id'] as String;

      await _supabase
          .from('staff_password_reset_otp')
          .update({'used': true})
          .eq('email', normalizedEmail)
          .eq('used', false);

      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString();
      final expiresAt =
          DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String();

      await _supabase.from('staff_password_reset_otp').insert({
        'cswd_id': cswdId,
        'email': normalizedEmail,
        'otp': otp,
        'expires_at': expiresAt,
        'used': false,
      });

      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/email'),
        body: {
          'apikey': _apiKey,
          'to': email.trim(),
          'subject': 'SapPIIre Password Reset Code',
          'message': '''
You requested a password reset for your SapPIIre staff account.

Your reset code: $otp

This code expires in 15 minutes.

If you did not request this, please contact your system administrator immediately.

- SapPIIre System
''',
          'sendername': _senderName,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': 'If this email is registered, a reset code has been sent.',
        };
      }

      debugPrint('StaffEmailService OTP email failed: ${response.body}');
      return {
        'success': false,
        'message': 'Failed to send reset code. Please try again.',
      };
    } catch (e) {
      debugPrint('StaffEmailService.sendPasswordResetOtp error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  // Verify OTP
  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final row = await _supabase
          .from('staff_password_reset_otp')
          .select('id, cswd_id, expires_at, used')
          .eq('email', email.trim().toLowerCase())
          .eq('otp', otp.trim())
          .eq('used', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) {
        return {'success': false, 'message': 'Invalid or expired reset code.'};
      }

      final expiresAt = DateTime.parse(row['expires_at'] as String).toUtc();
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        await _supabase
            .from('staff_password_reset_otp')
            .update({'used': true})
            .eq('id', row['id']);
        return {
          'success': false,
          'message': 'Reset code has expired. Please request a new one.',
        };
      }

      await _supabase
          .from('staff_password_reset_otp')
          .update({'used': true})
          .eq('id', row['id']);

      return {
        'success': true,
        'cswd_id': row['cswd_id'] as String,
        'message': 'Code verified.',
      };
    } catch (e) {
      debugPrint('StaffEmailService.verifyPasswordResetOtp error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
