import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

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
      final hashedPassword = _hashPassword(password);

      // Query staff_accounts — NOT user_accounts
      final accountResponse = await _supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, is_active, role, account_status')
          .eq('username', username)
          .eq('password_hash', hashedPassword)   // column is password_hash
          .maybeSingle();

      if (accountResponse == null) {
        return {
          'success': false,
          'message': 'Invalid username or password',
        };
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

      return {
        'success': true,
        'message': 'Login successful',
        'cswd_id': cswdId,
        'username': accountResponse['username'],
        'email': accountResponse['email'],
        'role': accountResponse['role'] ?? 'viewer',
        'profile': profileResponse,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Login error: ${e.toString()}',
      };
    }
  }
}
