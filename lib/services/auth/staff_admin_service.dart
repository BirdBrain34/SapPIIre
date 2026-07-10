import 'package:supabase_flutter/supabase_flutter.dart';

class StaffAdminService {
  StaffAdminService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String _sanitizeUsernamePart(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _buildBaseUsername(String firstName, String lastName) {
    final first = _sanitizeUsernamePart(firstName.trim());
    final last = _sanitizeUsernamePart(lastName.trim());
    final parts = <String>[
      if (first.isNotEmpty) first,
      if (last.isNotEmpty) last,
    ];

    if (parts.isEmpty) {
      return 'staff';
    }

    return parts.join('.');
  }

  Future<String> _generateUniqueUsername(
    String firstName,
    String lastName,
  ) async {
    final baseUsername = _buildBaseUsername(firstName, lastName);
    var candidate = baseUsername;
    var suffix = 1;

    while (true) {
      final result = await _supabase.functions.invoke('manage-staff-account', body: {
        'action': 'check_username_unique',
        'candidate': candidate,
      });
      final data = result.data as Map<String, dynamic>?;
      if (data?['exists'] != true) return candidate;
      candidate = '$baseUsername$suffix';
      suffix += 1;
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAccounts() async {
    final result = await _supabase.functions.invoke('manage-staff-account', body: {'action': 'fetch_accounts'});
    final data = result.data as Map<String, dynamic>;
    return {
      'pending': List<Map<String, dynamic>>.from(data['pending'] as List),
      'active': List<Map<String, dynamic>>.from(data['active'] as List),
    };
  }

  Future<void> approveAccount(String cswdId, String requestedRole) async {
    await _supabase.functions.invoke('manage-staff-account', body: {
      'action': 'update_account',
      'cswd_id': cswdId,
      'updates': {'role': requestedRole, 'account_status': 'active', 'is_active': true},
    });
  }

  Future<void> rejectAccount(String cswdId) async {
    await _supabase.functions.invoke('manage-staff-account', body: {
      'action': 'update_account',
      'cswd_id': cswdId,
      'updates': {'account_status': 'deactivated', 'is_active': false},
    });
  }

  Future<void> updateRole(String cswdId, String newRole) async {
    await _supabase.functions.invoke('manage-staff-account', body: {
      'action': 'update_account',
      'cswd_id': cswdId,
      'updates': {'role': newRole},
    });
  }

  Future<Map<String, dynamic>> createAdminStaffAccount({
    required String email,
    required String firstName,
    required String lastName,
    String? middleName,
    String? nameSuffix,
    String? position,
    String? department,
    String? phoneNumber,
  }) async {
    final generatedUsername = await _generateUniqueUsername(
      firstName,
      lastName,
    );

    // Generate a random placeholder password — server will bcrypt hash it
    final placeholderPassword = 'pending_setup_${DateTime.now().millisecondsSinceEpoch}';

    final result = await _supabase.functions.invoke('manage-staff-account', body: {
      'action': 'create_admin',
      'email': email.trim().toLowerCase(),
      'username': generatedUsername,
      'password': placeholderPassword, // Send raw password — server does bcrypt hash
      'first_name': firstName.trim(),
      'middle_name': middleName?.trim().isEmpty == true ? null : middleName?.trim(),
      'last_name': lastName.trim(),
      'name_suffix': nameSuffix?.trim().isEmpty == true ? null : nameSuffix?.trim(),
      'position': position?.trim().isEmpty == true ? null : position?.trim(),
      'department': department?.trim().isEmpty == true ? null : department?.trim(),
      'phone_number': phoneNumber?.trim().isEmpty == true ? null : phoneNumber?.trim(),
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

    return {'success': true, 'cswd_id': cswdId, 'username': generatedUsername};
  }
}
