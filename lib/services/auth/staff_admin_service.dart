import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffAdminService {
  StaffAdminService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAccounts() async {
    final pending = await _supabase
        .from('staff_accounts')
        .select('cswd_id, username, email, requested_role, created_at')
        .eq('account_status', 'pending')
        .order('created_at');

    final active = await _supabase
        .from('staff_accounts')
        .select(
          'cswd_id, username, email, role, account_status, is_active, is_first_login',
        )
        .neq('account_status', 'pending')
        .order('username');

    return {
      'pending': List<Map<String, dynamic>>.from(pending),
      'active': List<Map<String, dynamic>>.from(active),
    };
  }

  Future<void> approveAccount(String cswdId, String requestedRole) async {
    await _supabase
        .from('staff_accounts')
        .update({
          'role': requestedRole,
          'account_status': 'active',
          'is_active': true,
        })
        .eq('cswd_id', cswdId);
  }

  Future<void> rejectAccount(String cswdId) async {
    await _supabase
        .from('staff_accounts')
        .update({'account_status': 'deactivated', 'is_active': false})
        .eq('cswd_id', cswdId);
  }

  Future<void> updateRole(String cswdId, String newRole) async {
    await _supabase
        .from('staff_accounts')
        .update({'role': newRole})
        .eq('cswd_id', cswdId);
  }

  Future<Map<String, dynamic>> createAdminStaffAccount({
    required String email,
    required String username,
    required String firstName,
    required String lastName,
    String? position,
    String? department,
    String? phoneNumber,
  }) async {
    final existing = await _supabase
        .from('staff_accounts')
        .select('username')
        .eq('username', username.trim())
        .maybeSingle();

    if (existing != null) {
      return {'success': false, 'message': 'Username already exists.'};
    }

    final placeholderPassword = _hashPassword(
      'pending_setup_${DateTime.now().millisecondsSinceEpoch}',
    );

    final accountResponse = await _supabase
        .from('staff_accounts')
        .insert({
          'email': email.trim().toLowerCase(),
          'username': username.trim(),
          'password_hash': placeholderPassword,
          'role': 'admin',
          'requested_role': 'admin',
          'account_status': 'active',
          'is_active': true,
          'is_first_login': true,
        })
        .select('cswd_id')
        .single();

    final cswdId = accountResponse['cswd_id']?.toString();
    if (cswdId == null || cswdId.isEmpty) {
      return {
        'success': false,
        'message': 'Account created but failed to get ID. Contact developer.',
      };
    }

    await _supabase.from('staff_profiles').insert({
      'cswd_id': cswdId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'position': position?.trim().isEmpty == true ? null : position?.trim(),
      'department': department?.trim().isEmpty == true
          ? null
          : department?.trim(),
      'phone_number': phoneNumber?.trim().isEmpty == true
          ? null
          : phoneNumber?.trim(),
    });

    return {'success': true, 'cswd_id': cswdId};
  }
}