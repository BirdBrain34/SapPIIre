import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebSignupService {
  WebSignupService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>> createPendingStaffAccount({
    required String employeeId,
    required String firstName,
    required String middleName,
    required String lastName,
    required String nameSuffix,
    required String position,
    required String department,
    required String phoneNumber,
    required String email,
    required String username,
    required String password,
    required String requestedRole,
  }) async {
    try {
      final existing = await _supabase
          .from('staff_accounts')
          .select('username')
          .eq('username', username.trim())
          .maybeSingle();

      if (existing != null) {
        return {'success': false, 'message': 'Username already exists.'};
      }

      final accountResponse = await _supabase
          .from('staff_accounts')
          .insert({
            'employee_id': employeeId.trim().isEmpty ? null : employeeId.trim(),
            'email': email.trim(),
            'username': username.trim(),
            'password_hash': _hashPassword(password),
            'role': 'viewer',
            'requested_role': requestedRole,
            'account_status': 'pending',
            'is_active': false,
          })
          .select('cswd_id')
          .single();

      final String? cswdId = accountResponse['cswd_id']?.toString();
      if (cswdId == null || cswdId.isEmpty) {
        return {
          'success': false,
          'message': 'Account created but failed to get ID. Contact developer.',
        };
      }

      await _supabase.from('staff_profiles').insert({
        'cswd_id': cswdId,
        'first_name': firstName.trim(),
        'middle_name': middleName.trim().isEmpty ? null : middleName.trim(),
        'last_name': lastName.trim(),
        'name_suffix': nameSuffix.trim().isEmpty ? null : nameSuffix.trim(),
        'position': position.trim(),
        'department': department.trim(),
        'phone_number': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
      });

      return {
        'success': true,
        'message': 'Account created successfully!',
        'cswd_id': cswdId,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
