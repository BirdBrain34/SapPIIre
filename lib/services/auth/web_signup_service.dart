import 'package:supabase_flutter/supabase_flutter.dart';

class WebSignupService {
  WebSignupService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<Map<String, dynamic>> createPendingStaffAccount({
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
      final checkResult = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'check_username',
        'username': username.trim(),
      });
      final checkData = checkResult.data as Map<String, dynamic>?;
      if (checkData?['exists'] == true) {
        return {'success': false, 'message': 'Username already exists.'};
      }

      final result = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'create_pending',
        'email': email.trim(),
        'username': username.trim(),
        'password': password, // Send raw password — server does bcrypt hash
        'requested_role': requestedRole,
        'first_name': firstName.trim(),
        'middle_name': middleName.trim().isEmpty ? null : middleName.trim(),
        'last_name': lastName.trim(),
        'name_suffix': nameSuffix.trim().isEmpty ? null : nameSuffix.trim(),
        'position': position.trim(),
        'department': department.trim(),
        'phone_number': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
      });

      final data = result.data as Map<String, dynamic>?;

      if (data?['error'] != null) {
        final code = data?['code']?.toString();
        if (code == '42501') {
          return {'success': false, 'message': 'Database policy blocked profile creation. Apply the latest staff_profiles RLS migration, then try again.'};
        }
        if (code == '23502') {
          return {'success': false, 'message': 'Position and department are required by the database. Please fill them in and try again.'};
        }
        return {'success': false, 'message': 'Failed to create staff profile: ${data!['error']}'};
      }

      final cswdId = data?['cswd_id']?.toString();
      if (cswdId == null || cswdId.isEmpty) {
        return {'success': false, 'message': 'Account created but failed to get ID. Contact developer.'};
      }

      return {'success': true, 'message': 'Account created successfully!', 'cswd_id': cswdId};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
