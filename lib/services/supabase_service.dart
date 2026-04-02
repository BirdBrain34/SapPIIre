import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sappiire/services/form_template_service.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // ================================================================
  // PRIVATE HELPERS
  // ================================================================

  String _sha256Hash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  String _hashPin(String pin, String userId) {
    return _sha256Hash('$userId:sappiire_pin:$pin');
  }

Future<void> updateAccountInfo(String userId, Map<String, dynamic> updates) async {
  await _supabase
      .from('user_accounts')
      .update(updates)
      .eq('user_id', userId);
}

  // ================================================================
  // AUTHENTICATION — SIGNUP
  // ================================================================



Future<Map<String, dynamic>> sendEmailOtp(String email) async {
  try {
    // Fixed variable name to _supabase
    await _supabase.auth.signInWithOtp(email: email);
    return {'success': true};
  } catch (e) {
    return {'success': false, 'message': e.toString()};
  }
}



  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
  }) async {
    try {
      final existing = await _supabase
          .from('user_accounts')
          .select('email, user_id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        final userId = existing['user_id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          final fieldValues = await _supabase
              .from('user_field_values')
              .select('id')
              .eq('user_id', userId)
              .limit(1)
              .maybeSingle();

          if (fieldValues != null) {
            return {
              'success': false,
              'message': 'This email is already registered. Please log in instead.',
            };
          } else {
            await _supabase.auth.signInWithOtp(
              email: email,
              shouldCreateUser: false,
            );
            return {
              'success': true,
              'message': 'OTP sent! Check your email.',
              'user_id': userId,
            };
          }
        }
      }

      final signupPassword = DateTime.now().millisecondsSinceEpoch.toString();
      final res = await _supabase.auth.signUp(
        email: email,
        password: signupPassword,
        emailRedirectTo: null,
      );

      if (res.user == null) {
        return {'success': false, 'message': 'Sign-up failed. Try again.'};
      }

      try {
        await _supabase.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
        );
      } catch (e) {
        debugPrint('⚠️ OTP send failed: $e');
      }

      return {
        'success': true,
        'message': 'OTP sent! Check your email.',
        'user_id': res.user!.id,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }


  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );

      if (response.user == null) {
        return {'success': false, 'message': 'Invalid or expired code.'};
      }

      return {'success': true, 'user_id': response.user!.id};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Verification error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString();

      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/otp'),
        body: {
          'apikey': 'fc4874818b2f98480dbba9e862b90334',
          'number': phone,
          'message': 'Your SapPIIre verification code is {otp}. Do not share this with anyone.',
          'code': otp,
          'sendername': 'SapPIIre',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final otpHash = _sha256Hash(otp);
        await _supabase.from('phone_otp').delete().eq('phone', phone);
        await _supabase.from('phone_otp').insert({
          'phone': phone,
          'otp_hash': otpHash,
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        });
        return {'success': true, 'message': 'OTP sent!'};
      } else {
        return {'success': false, 'message': 'Semaphore error: ${response.body}'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final otpHash = _sha256Hash(otp);

      final data = await _supabase
          .from('phone_otp')
          .select()
          .eq('phone', phone)
          .eq('otp_hash', otpHash)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        return {'success': false, 'message': 'Invalid code'};
      }

      if (DateTime.parse(data['expires_at']).isBefore(DateTime.now().toUtc())) {
        await _supabase.from('phone_otp').delete().eq('id', data['id']);
        return {'success': false, 'message': 'Code has expired. Please request a new one.'};
      }

      await _supabase.from('phone_otp').delete().eq('id', data['id']);
      return {'success': true, 'message': 'Phone verified!'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Final step of signup.
  /// [allowDuplicatePhone] — if true, skips the duplicate phone check (signup flow).
  Future<Map<String, dynamic>> saveProfileAfterVerification({
    required String userId,
    required String username,
    required String pin,
    required String email,
    required String firstName,
    required String middleName,
    required String lastName,
    required String dateOfBirth,
    required String phoneNumber,
    required String birthplace,
    required String gender,
    required String civilStatus,
    required String addressLine,
    bool allowDuplicatePhone = true, // signup allows duplicate phone for now
  }) async {
    try {
      // Check username uniqueness (exclude current userId)
      final existingUsername = await _supabase
          .from('user_accounts')
          .select('user_id')
          .eq('username', username)
          .neq('user_id', userId)
          .maybeSingle();

      if (existingUsername != null) {
        return {
          'success': false,
          'message': 'Username is already taken. Please choose another.',
        };
      }

      final pinHash = _hashPin(pin, userId);

      await _supabase.from('user_accounts').upsert({
        'user_id': userId,
        'username': username,
        'email': email,
        'phone_number': phoneNumber.isNotEmpty ? phoneNumber : null,
        'pin_hash': pinHash,
        'is_active': true,
        'pin_attempts': 0,
      }, onConflict: 'user_id');

      debugPrint('✅ user_accounts row created/updated');

      final dateParts = dateOfBirth.split('/');
      final formattedDate = dateParts.length == 3
          ? '${dateParts[2]}-${dateParts[0].padLeft(2, '0')}-${dateParts[1].padLeft(2, '0')}'
          : dateOfBirth;
      final birthYear = dateParts.length == 3 ? int.tryParse(dateParts[2]) : null;
      final age = birthYear != null ? DateTime.now().year - birthYear : null;

      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();

      if (templates.isEmpty) {
        return {
          'success': false,
          'message': 'System error: No form templates available. Contact administrator.',
        };
      }

      final allFields = templates.expand((t) => t.allFields).toList();

      final piiData = {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'date_of_birth': formattedDate,
        if (age != null) 'age': age.toString(),
        'kasarian_sex': gender,
        'estadong_sibil_civil_status': civilStatus,
        'lugar_ng_kapanganakan_place_of_birth': birthplace,
        'cp_number': phoneNumber,
        'email_address': email,
        'house_number_street_name_phase_purok': addressLine,
      };

      final now = DateTime.now().toIso8601String();
      final rows = <Map<String, dynamic>>[];

      for (final entry in piiData.entries) {
        if (entry.value.toString().isEmpty) continue;
        final matchingFields = allFields.where((f) => f.canonicalFieldKey == entry.key).toList();
        if (matchingFields.isEmpty) continue;
        for (final field in matchingFields) {
          rows.add({
            'user_id': userId,
            'field_id': field.fieldId,
            'field_value': entry.value.toString(),
            'updated_at': now,
          });
        }
      }

      if (rows.isNotEmpty) {
        await _supabase.from('user_field_values').upsert(rows, onConflict: 'user_id,field_id');
        debugPrint('✅ Saved ${rows.length} field values');
      }

      return {
        'success': true,
        'message': 'Account created successfully',
        'user_id': userId,
      };
    } catch (e) {
      debugPrint('saveProfileAfterVerification error: $e');
      return {'success': false, 'message': 'Error saving profile: ${e.toString()}'};
    }
  }

  // ================================================================
  // AUTHENTICATION — LOGIN (PIN-based)
  // Accepts: username, email, or phone number
  // ================================================================

  Future<Map<String, dynamic>> loginWithPin({
    required String identifier, // username, email, or phone
    required String pin,
  }) async {
    try {
      final trimmed = identifier.trim();

      // Determine query type
      Map<String, dynamic>? account;

      // Try email
      if (trimmed.contains('@')) {
        account = await _supabase
            .from('user_accounts')
            .select('user_id, username, email, phone_number, is_active, pin_hash, pin_attempts, pin_locked_until')
            .eq('email', trimmed)
            .maybeSingle();
      }
      // Try phone (starts with 0 or +)
      else if (trimmed.startsWith('0') || trimmed.startsWith('+') || RegExp(r'^\d{10,}$').hasMatch(trimmed)) {
        account = await _supabase
            .from('user_accounts')
            .select('user_id, username, email, phone_number, is_active, pin_hash, pin_attempts, pin_locked_until')
            .eq('phone_number', trimmed)
            .maybeSingle();
      }

      // Fallback: try username
      if (account == null) {
        account = await _supabase
            .from('user_accounts')
            .select('user_id, username, email, phone_number, is_active, pin_hash, pin_attempts, pin_locked_until')
            .eq('username', trimmed)
            .maybeSingle();
      }

      if (account == null) {
        return {'success': false, 'message': 'Account does not exist'};
      }

      if (account['is_active'] == false) {
        return {'success': false, 'message': 'Account is deactivated'};
      }

      // Check lockout
      final lockedUntil = account['pin_locked_until'] as String?;
      if (lockedUntil != null) {
        final lockTime = DateTime.parse(lockedUntil);
        if (lockTime.isAfter(DateTime.now().toUtc())) {
          final remaining = lockTime.difference(DateTime.now()).inMinutes + 1;
          return {
            'success': false,
            'message': 'Account locked. Try again in $remaining minute(s).',
          };
        } else {
          await _supabase.from('user_accounts').update({
            'pin_attempts': 0,
            'pin_locked_until': null,
          }).eq('user_id', account['user_id']);
        }
      }

      final storedHash = account['pin_hash'] as String?;
      if (storedHash == null) {
        return {'success': false, 'message': 'No PIN set. Please reset your PIN.'};
      }

      final inputHash = _hashPin(pin, account['user_id'] as String);

      if (inputHash != storedHash) {
        final attempts = (account['pin_attempts'] as int? ?? 0) + 1;
        final Map<String, dynamic> updateData = {'pin_attempts': attempts};

        if (attempts >= 5) {
          updateData['pin_locked_until'] = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String();
          await _supabase.from('user_accounts').update(updateData).eq('user_id', account['user_id']);
          return {'success': false, 'message': 'Too many failed attempts. Account locked for 15 minutes.'};
        }

        await _supabase.from('user_accounts').update(updateData).eq('user_id', account['user_id']);
        final remaining = 5 - attempts;
        return {'success': false, 'message': 'Incorrect PIN. $remaining attempt(s) remaining.'};
      }

      await _supabase.from('user_accounts').update({
        'pin_attempts': 0,
        'pin_locked_until': null,
        'last_login': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', account['user_id']);

      return {
        'success': true,
        'message': 'Login successful',
        'user_id': account['user_id'],
        'username': account['username'],
        'email': account['email'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error during login: ${e.toString()}'};
    }
  }

  // ================================================================
  // PIN RESET — Step 1: Verify identity
  // ================================================================

  /// Verifies first name + last name + DOB from user_field_values.
  /// Uses a direct join via RPC-style query on canonical_field_key.
  Future<Map<String, dynamic>> verifyIdentityForPinReset({
    required String firstName,
    required String lastName,
    required String dateOfBirth, // YYYY-MM-DD
  }) async {
    try {
      // Fetch all active accounts
      final accounts = await _supabase
          .from('user_accounts')
          .select('user_id, email, phone_number')
          .eq('is_active', true);

      if (accounts.isEmpty) {
        return {'success': false, 'message': 'No matching account found.'};
      }

      final firstLower = firstName.toLowerCase().trim();
      final lastLower = lastName.toLowerCase().trim();

      for (final account in accounts) {
        final userId = account['user_id'] as String;

        // Pull field values joined with their canonical keys
        // We query user_field_values and join with form_fields
        List<dynamic> nameFields = [];
        try {
          nameFields = await _supabase
              .from('user_field_values')
              .select('field_value, form_fields!inner(canonical_field_key)')
              .eq('user_id', userId)
              .inFilter('form_fields.canonical_field_key', [
                'first_name',
                'last_name',
                'date_of_birth',
              ]);
        } catch (e) {
          // Fallback: some Supabase configs don't support inline join filter
          // Try fetching raw and matching by known field IDs
          debugPrint('Join query failed, using fallback: $e');
          nameFields = [];
        }

        // If join failed or returned empty, try alternate approach:
        // fetch all field values for user and cross-reference with template
        if (nameFields.isEmpty) {
          final rawValues = await _supabase
              .from('user_field_values')
              .select('field_id, field_value')
              .eq('user_id', userId);

          if (rawValues.isEmpty) continue;

          // Get templates to resolve canonical keys
          final templateSvc = FormTemplateService();
          final templates = await templateSvc.fetchActiveTemplates();
          if (templates.isEmpty) continue;

          final allFields = templates.expand((t) => t.allFields).toList();
          final idToKey = {for (final f in allFields) f.fieldId: f.canonicalFieldKey ?? ''};

          String? storedFirst;
          String? storedLast;
          String? storedDob;

          for (final row in rawValues) {
            final fid = row['field_id'] as String?;
            final fval = row['field_value'] as String?;
            if (fid == null || fval == null) continue;

            final key = idToKey[fid] ?? '';
            if (key == 'first_name') storedFirst = fval.toLowerCase().trim();
            if (key == 'last_name') storedLast = fval.toLowerCase().trim();
            if (key == 'date_of_birth') storedDob = fval.trim();
          }

          if (storedFirst == firstLower &&
              storedLast == lastLower &&
              storedDob == dateOfBirth) {
            return {
              'success': true,
              'user_id': userId,
              'email': account['email'],
              'phone_number': account['phone_number'],
            };
          }
          continue;
        }

        // Parse join results
        String? storedFirst;
        String? storedLast;
        String? storedDob;

        for (final f in nameFields) {
          final key = f['form_fields']?['canonical_field_key'] as String?;
          final val = f['field_value'] as String?;
          if (key == 'first_name') storedFirst = val?.toLowerCase().trim();
          if (key == 'last_name') storedLast = val?.toLowerCase().trim();
          if (key == 'date_of_birth') storedDob = val?.trim();
        }

        if (storedFirst == firstLower &&
            storedLast == lastLower &&
            storedDob == dateOfBirth) {
          return {
            'success': true,
            'user_id': userId,
            'email': account['email'],
            'phone_number': account['phone_number'],
          };
        }
      }

      return {
        'success': false,
        'message': 'No account matched the information provided.',
      };
    } catch (e) {
      debugPrint('verifyIdentityForPinReset error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Step 3 of PIN reset: set new PIN.
  Future<Map<String, dynamic>> setNewPin({
    required String userId,
    required String newPin,
  }) async {
    try {
      final pinHash = _hashPin(newPin, userId);
      await _supabase.from('user_accounts').update({
        'pin_hash': pinHash,
        'pin_attempts': 0,
        'pin_locked_until': null,
      }).eq('user_id', userId);

      return {'success': true, 'message': 'PIN updated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Error setting PIN: ${e.toString()}'};
    }
  }

  // ================================================================
  // USER PROFILE
  // ================================================================

  Future<String?> getUsername(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      return response?['username'] as String?;
    } catch (e) {
      debugPrint('Error fetching username: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> verifyOtpCode({
    String? email,
    String? phone,
    required String token,
  }) async {
    // 1. If it's an email, use Supabase Auth
    if (email != null && email.isNotEmpty) {
      return await verifyEmailOtp(email: email, otp: token);
    } 
    // 2. If it's a phone, use your Custom Table logic
    else if (phone != null && phone.isNotEmpty) {
      return await verifyPhoneOtp(phone: phone, otp: token);
    } 
    
    return {'success': false, 'message': 'No email or phone provided.'};
  }

  /// Loads full account info (username, email, phone) for ProfileScreen.
  Future<Map<String, dynamic>> getAccountInfo(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('username, email, phone_number')
          .eq('user_id', userId)
          .maybeSingle();
      return response ?? {};
    } catch (e) {
      debugPrint('getAccountInfo error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> loadPiiFromFieldValues(String userId) async {
    try {
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();

      if (templates.isEmpty) return {};

      final allFields = templates.expand((t) => t.allFields).toList();
      final fieldIds = allFields
          .where((f) => f.parentFieldId == null)
          .map((f) => f.fieldId)
          .toList();

      if (fieldIds.isEmpty) return {};

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value')
          .eq('user_id', userId)
          .inFilter('field_id', fieldIds)
          .order('updated_at', ascending: false);

      final idToCanonicalKey = {for (final f in allFields) f.fieldId: f.canonicalFieldKey};
      final result = <String, dynamic>{};

      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null || fval == null || fval.isEmpty || fval == '__CLEARED__') continue;
        final canonicalKey = idToCanonicalKey[fid];
        if (canonicalKey != null && canonicalKey.isNotEmpty && !result.containsKey(canonicalKey)) {
          result[canonicalKey] = fval;
        }
      }

      return result;
    } catch (e) {
      debugPrint('loadPiiFromFieldValues error: $e');
      return {};
    }
  }

  Future<bool> sendDataToWebSession(
    String sessionId,
    Map<String, dynamic> data, {
    String? userId,
  }) async {
    try {
      final response = await _supabase
          .from('form_submission')
          .update({
            'form_data': data,
            'status': 'scanned',
            'scanned_at': DateTime.now().toIso8601String(),
            if (userId != null) 'user_id': userId,
          })
          .eq('id', sessionId)
          .select()
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('sendDataToWebSession error: $e');
      return false;
    }
  }

  @Deprecated('Use loginWithPin instead')
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    return {'success': false, 'message': 'Password login is no longer supported. Please use PIN.'};
  }
}

