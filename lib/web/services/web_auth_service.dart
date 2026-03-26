import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sappiire/web/services/audit_log_service.dart';

class WebAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final normalizedUsername = username.trim().toLowerCase();
      final hashedPassword = _hashPassword(password);

      // Query staff_accounts — NOT user_accounts
      final accountResponse = await _supabase
          .from('staff_accounts')
          .select(
            'cswd_id, username, email, is_active, role, account_status, password_hash',
          )
          .ilike('username', normalizedUsername)
          .maybeSingle();

      if (accountResponse == null) {
        return {'success': false, 'message': 'Invalid username or password'};
      }

      final storedHash = accountResponse['password_hash'];
      if (hashedPassword != storedHash) {
        await AuditLogService().log(
          actionType: kAuditLoginFailed,
          category: kCategoryAuth,
          severity: kSeverityWarning,
          actorName: username,
          details: {'reason': 'invalid_password'},
        );
        return {'success': false, 'message': 'Invalid username or password'};
      }

      if (accountResponse['is_active'] == false) {
        return {
          'success': false,
          'message': 'Account is deactivated. Contact your administrator.',
        };
      }

      final String cswdId = accountResponse['cswd_id'];

      // Update last_login
      await _supabase
          .from('staff_accounts')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('cswd_id', cswdId);

      // Fetch from staff_profiles — NOT user_profiles
      final profileResponse = await _supabase
          .from('staff_profiles')
          .select(
            'first_name, middle_name, last_name, '
            'position, department, phone_number',
          )
          .eq('cswd_id', cswdId)
          .maybeSingle();

      // Fall back to username when no profile row exists (e.g., seeded superadmin).
      String displayName = accountResponse['username'] as String;
      if (profileResponse != null) {
        final first = (profileResponse['first_name'] ?? '').toString().trim();
        final last = (profileResponse['last_name'] ?? '').toString().trim();
        if (first.isNotEmpty || last.isNotEmpty) {
          displayName = '$first $last'.trim();
        }
      }

      await AuditLogService().log(
        actionType: kAuditLogin,
        category: kCategoryAuth,
        severity: kSeverityInfo,
        actorId: cswdId,
        actorName: displayName,
        actorRole: accountResponse['role'] ?? 'viewer',
        targetType: 'staff_account',
        targetId: cswdId,
        targetLabel: accountResponse['username']?.toString(),
      );

      return {
        'success': true,
        'message': 'Login successful',
        'cswd_id': cswdId,
        'username': accountResponse['username'],
        'email': accountResponse['email'],
        'role': accountResponse['role'] ?? 'viewer',
        'display_name': displayName,
        'profile': profileResponse,
      };
    } catch (e) {
      return {'success': false, 'message': 'Login error: ${e.toString()}'};
    }
  }

  /// Changes the password for a staff account.
  /// Verifies the current password before updating.
  /// Returns { 'success': bool, 'message': String }
  Future<Map<String, dynamic>> changePassword({
    required String cswd_id,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final account = await _supabase
          .from('staff_accounts')
          .select('password_hash')
          .eq('cswd_id', cswd_id)
          .maybeSingle();

      if (account == null) {
        return {'success': false, 'message': 'Account not found.'};
      }

      final currentHash = _hashPassword(currentPassword);
      if (currentHash != account['password_hash']) {
        return {
          'success': false,
          'message': 'Current password is incorrect.',
        };
      }

      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'New password must be at least 8 characters.',
        };
      }

      final newHash = _hashPassword(newPassword);
      if (newHash == account['password_hash']) {
        return {
          'success': false,
          'message': 'New password must be different from your current password.',
        };
      }

      await _supabase
          .from('staff_accounts')
          .update({'password_hash': newHash})
          .eq('cswd_id', cswd_id);

      await AuditLogService().log(
        actionType: kAuditPasswordChanged,
        category: kCategoryAuth,
        severity: kSeverityWarning,
        actorId: cswd_id,
        targetType: 'staff_account',
        targetId: cswd_id,
        details: {'initiated_by': 'self'},
      );

      return {'success': true, 'message': 'Password changed successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
