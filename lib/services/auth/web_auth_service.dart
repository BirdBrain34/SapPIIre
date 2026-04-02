import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/services/audit/audit_log_service.dart';

class WebAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>> login({
    required String loginIdentifier,
    required String password,
  }) async {
    try {
      final normalizedIdentifier = loginIdentifier.trim().toLowerCase();
      final hashedPassword = _hashPassword(password);

      Map<String, dynamic>? accountResponse = await _supabase
          .from('staff_accounts')
          .select(
            'cswd_id, username, email, is_active, role, '
            'account_status, password_hash, is_first_login',
          )
          .ilike('username', normalizedIdentifier)
          .eq('role', 'superadmin')
          .maybeSingle();

      accountResponse ??= await _supabase
          .from('staff_accounts')
          .select(
            'cswd_id, username, email, is_active, role, '
            'account_status, password_hash, is_first_login',
          )
          .ilike('email', normalizedIdentifier)
          .neq('role', 'superadmin')
          .maybeSingle();

      if (accountResponse == null) {
        await AuditLogService().log(
          actionType: kAuditLoginFailed,
          category: kCategoryAuth,
          severity: kSeverityWarning,
          actorName: loginIdentifier,
          details: {'reason': 'invalid_identifier_or_role_policy'},
        );
        return {'success': false, 'message': 'Invalid credentials'};
      }

      final storedHash = accountResponse['password_hash'];
      if (hashedPassword != storedHash) {
        await AuditLogService().log(
          actionType: kAuditLoginFailed,
          category: kCategoryAuth,
          severity: kSeverityWarning,
          actorName: loginIdentifier,
          details: {'reason': 'invalid_password'},
        );
        return {'success': false, 'message': 'Invalid credentials'};
      }

      if (accountResponse['is_active'] == false) {
        return {
          'success': false,
          'message': 'Account is deactivated. Contact your administrator.',
        };
      }

      final String cswdId = accountResponse['cswd_id'];

      await _supabase
          .from('staff_accounts')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('cswd_id', cswdId);

      final profileResponse = await _supabase
          .from('staff_profiles')
          .select(
            'first_name, middle_name, last_name, '
            'position, department, phone_number',
          )
          .eq('cswd_id', cswdId)
          .maybeSingle();

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
        'is_first_login': accountResponse['is_first_login'] ?? false,
        'display_name': displayName,
        'profile': profileResponse,
      };
    } catch (e) {
      return {'success': false, 'message': 'Login error: ${e.toString()}'};
    }
  }

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
        return {'success': false, 'message': 'Current password is incorrect.'};
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
          'message':
              'New password must be different from your current password.',
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

  Future<void> clearFirstLoginFlag(String cswd_id) async {
    try {
      await _supabase
          .from('staff_accounts')
          .update({'is_first_login': false})
          .eq('cswd_id', cswd_id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WebAuthService.clearFirstLoginFlag error: $e');
      }
    }
  }

  Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String cswd_id,
    required String newPassword,
  }) async {
    try {
      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'Password must be at least 8 characters.',
        };
      }

      await _supabase
          .from('staff_accounts')
          .update({
            'password_hash': _hashPassword(newPassword),
            'is_first_login': false,
            'account_status': 'active',
          })
          .eq('cswd_id', cswd_id);

      return {'success': true, 'message': 'Password reset successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> deactivateStaffAccount(String cswd_id) async {
    try {
      await _supabase
          .from('staff_accounts')
          .update({'is_active': false, 'account_status': 'deactivated'})
          .eq('cswd_id', cswd_id);
      return {'success': true, 'message': 'Account deactivated.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> reactivateStaffAccount(String cswd_id) async {
    try {
      await _supabase
          .from('staff_accounts')
          .update({'is_active': true, 'account_status': 'active'})
          .eq('cswd_id', cswd_id);
      return {'success': true, 'message': 'Account reactivated.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<void> signOut() {
    return _supabase.auth.signOut();
  }
}
