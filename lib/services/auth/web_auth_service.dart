import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';

class WebAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Send the raw password to the Edge Function which performs
  /// bcrypt verification server-side. This avoids client-side hashing
  /// and ensures bcrypt's random salt works correctly.
  Future<Map<String, dynamic>> login({
    required String loginIdentifier,
    required String password,
  }) async {
    try {
      final normalizedIdentifier = loginIdentifier.trim().toLowerCase();

      final loginResult = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'login',
        'login_identifier': normalizedIdentifier,
        'password': password, // Send raw password — server does bcrypt verify
      });
      final accountResponse = (loginResult.data as Map<String, dynamic>?)?['account'] as Map<String, dynamic>?;

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

      if (accountResponse['is_valid'] == false) {
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

      await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'update_last_login',
        'cswd_id': cswdId,
      });

      final profileResult = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'fetch_profile',
        'cswd_id': cswdId,
      });
      final profileResponse = (profileResult.data as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?;

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
    required String cswdId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'New password must be at least 8 characters.',
        };
      }

      if (currentPassword == newPassword) {
        return {
          'success': false,
          'message': 'New password must be different from your current password.',
        };
      }

      // Server-side bcrypt verification and update
      final result = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'change_password',
        'cswd_id': cswdId,
        'current_password': currentPassword,
        'new_password': newPassword,
      });

      final data = result.data as Map<String, dynamic>? ?? {};
      if (data['success'] == true) {
        await AuditLogService().log(
          actionType: kAuditPasswordChanged,
          category: kCategoryAuth,
          severity: kSeverityWarning,
          actorId: cswdId,
          targetType: 'staff_account',
          targetId: cswdId,
          details: {'initiated_by': 'self'},
        );
        return {'success': true, 'message': 'Password changed successfully.'};
      }

      return {'success': false, 'message': data['message'] ?? 'Current password is incorrect.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<void> clearFirstLoginFlag(String cswdId) async {
    try {
      await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'update_account',
        'cswd_id': cswdId,
        'updates': {'is_first_login': false},
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebAuthService/clearFirstLoginFlag] Error: $e');
      }
    }
  }

  Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String cswdId,
    required String newPassword,
  }) async {
    try {
      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'Password must be at least 8 characters.',
        };
      }

      // Server-side bcrypt hashing
      final result = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'update_password',
        'cswd_id': cswdId,
        'new_password': newPassword,
        'is_first_login': false,
        'account_status': 'active',
      });

      final data = result.data as Map<String, dynamic>? ?? {};
      if (data['success'] == true) {
        return {'success': true, 'message': 'Password reset successfully.'};
      }

      return {'success': false, 'message': data['message'] ?? 'Password reset failed.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> deactivateStaffAccount(String cswdId) async {
    try {
      await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'update_account',
        'cswd_id': cswdId,
        'updates': {'is_active': false, 'account_status': 'deactivated'},
      });
      return {'success': true, 'message': 'Account deactivated.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> reactivateStaffAccount(String cswdId) async {
    try {
      await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'update_account',
        'cswd_id': cswdId,
        'updates': {'is_active': true, 'account_status': 'active'},
      });
      return {'success': true, 'message': 'Account reactivated.'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<void> signOut() {
    HybridCryptoService.clearFieldKeyCache();
    return _supabase.auth.signOut();
  }
}
