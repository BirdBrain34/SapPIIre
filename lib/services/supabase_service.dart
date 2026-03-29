import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // Legacy column definitions removed - no longer needed with user_field_values architecture

  // ================================================================
  // AUTHENTICATION
  // ================================================================

  /// Step 1 of signup: register with Supabase Auth.
  /// Supabase sends an OTP to the email automatically.
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    String? password, // Optional: if provided, use it; otherwise generate temp
  }) async {
    try {
      // Check user_accounts for this email
      final existing = await _supabase
          .from('user_accounts')
          .select('email, user_id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        final userId = existing['user_id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          // Check if they finished signup (have field values)
          final fieldValues = await _supabase
              .from('user_field_values')
              .select('id')
              .eq('user_id', userId)
              .limit(1)
              .maybeSingle();

          if (fieldValues != null) {
            // Fully registered — block
            return {
              'success': false,
              'message': 'This email is already registered. Please log in instead.',
            };
          } else {
            // Verified email but never finished — send OTP via signInWithOtp
            // and treat it as continuing their signup
            await _supabase.auth.signInWithOtp(
              email: email,
              shouldCreateUser: false, // don't create, just send OTP to existing
            );
            return {
              'success': true,
              'message': 'OTP sent! Check your email.',
              'user_id': userId,
            };
          }
        }
      }

      // Brand new email — create user and send OTP
      final signupPassword = password ?? DateTime.now().millisecondsSinceEpoch.toString();
      final res = await _supabase.auth.signUp(
        email: email,
        password: signupPassword,
        emailRedirectTo: null, // Disable email confirmation link
      );

      if (res.user == null) {
        return {'success': false, 'message': 'Sign-up failed. Try again.'};
      }

      // Explicitly send OTP after signup
      try {
        await _supabase.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
        );
      } catch (e) {
        debugPrint('⚠️ OTP send failed: $e');
        // Continue anyway - user can use resend button
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

  /// Step 2 of signup: verify the OTP sent to email.
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

      return {
        'success': true,
        'user_id': response.user!.id,  // ← this is now reliable since OTP confirmed
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Verification error: ${e.toString()}'};
    }
  }

    /// Step 3 of signup: Phone OTP.
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      
      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/otp'),
        body: {
          'apikey': 'fc4874818b2f98480dbba9e862b90334',
          'number': phone,
          'message': 'Your SapPIIre verification code is {otp}. Do not share this with anyone.',
          'code': otp,
          //'sendername': 'SEMAPHORE',
          'sendername': 'SapPIIre',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Store OTP in Supabase directly
        await _supabase.from('phone_otp').delete().eq('phone', phone);
        await _supabase.from('phone_otp').insert({
          'phone': phone,
          'otp': otp,
          'expires_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
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
      final data = await _supabase
          .from('phone_otp')
          .select()
          .eq('phone', phone)
          .eq('otp', otp)
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

  /// Step 4 of signup: save profile data after OTP is verified.
  /// Writes all PII to user_field_values by dynamically matching field_name from GIS v2.
  Future<Map<String, dynamic>> saveProfileAfterVerification({
    required String userId,
    required String username,
    required String password,
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
  }) async {
    try {
      // 1. Set password in Supabase Auth (user should be authenticated after OTP verification)
      try {
        await _supabase.auth.updateUser(UserAttributes(password: password));
        debugPrint('✅ Password set successfully');
      } catch (e) {
        debugPrint('⚠️ Password update failed: $e');
        // Continue anyway - user can reset password later
      }

      // 2. Ensure user_accounts row exists (upsert username and email)
      await _supabase
          .from('user_accounts')
          .upsert({
            'user_id': userId,
            'username': username,
            'email': email,
            'is_active': true,
          }, onConflict: 'user_id');
      
      debugPrint('✅ user_accounts row created/updated');

      // 3. Parse birthdate M/D/YYYY → YYYY-MM-DD
      final dateParts = dateOfBirth.split('/');
      final formattedDate = dateParts.length == 3
          ? '${dateParts[2]}-'
            '${dateParts[0].padLeft(2, '0')}-'
            '${dateParts[1].padLeft(2, '0')}'
          : dateOfBirth;
      final birthYear = dateParts.length == 3 ? int.tryParse(dateParts[2]) : null;
      final age = birthYear != null ? DateTime.now().year - birthYear : null;

      // 4. Fetch ALL templates to save data across all matching canonical keys
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();
      
      if (templates.isEmpty) {
        debugPrint('❌ No templates found - check RLS policies on form_templates table');
        return {
          'success': false,
          'message': 'System error: No form templates available. Contact administrator.',
        };
      }
      
      debugPrint('✅ Found ${templates.length} active templates');
      
      // Collect ALL fields across ALL templates
      final allFields = templates.expand((t) => t.allFields).toList();
      debugPrint('📋 Total fields across all templates: ${allFields.length}');

      // 5. Build canonical_field_key → value map
      final piiData = {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'date_of_birth': formattedDate,
        if (age != null) 'age': age.toString(),
        'kasarian_sex': gender, // Already converted in signup (M/F or Male/Female)
        'estadong_sibil_civil_status': civilStatus, // Already converted in signup
        'lugar_ng_kapanganakan_place_of_birth': birthplace,
        'cp_number': phoneNumber,
        'email_address': email,
        'house_number_street_name_phase_purok': addressLine,
      };

      // 6. Match canonical_field_key → field_id across ALL templates and save
      final now = DateTime.now().toIso8601String();
      final rows = <Map<String, dynamic>>[];
      
      debugPrint('🔍 Attempting to match ${piiData.length} signup fields...');
      
      for (final entry in piiData.entries) {
        if (entry.value.toString().isEmpty) {
          debugPrint('⏭️ Skipping empty field: ${entry.key}');
          continue;
        }
        
        debugPrint('🔎 Looking for canonical_field_key: ${entry.key}');
        
        // Find ALL fields with this canonical key across ALL templates
        final matchingFields = allFields.where(
          (f) => f.canonicalFieldKey == entry.key
        ).toList();
        
        if (matchingFields.isEmpty) {
          debugPrint('❌ No fields found with canonical_field_key: ${entry.key}');
          continue;
        }

        debugPrint('✅ Found ${matchingFields.length} field(s) with canonical_field_key: ${entry.key}');
        
        // Save to ALL matching fields (across all templates)
        for (final field in matchingFields) {
          debugPrint('   → Saving to template: ${templates.firstWhere((t) => t.templateId == field.templateId).formName}');
          rows.add({
            'user_id': userId,
            'field_id': field.fieldId,
            'field_value': entry.value.toString(),
            'updated_at': now,
          });
        }
      }

      debugPrint('💾 Saving ${rows.length} rows to user_field_values...');
      
      if (rows.isNotEmpty) {
        await _supabase
            .from('user_field_values')
            .upsert(rows, onConflict: 'user_id,field_id');
        debugPrint('✅ Successfully saved ${rows.length} field values across all templates');
      } else {
        debugPrint('⚠️ No rows to save - all fields were empty or not matched');
      }

      return {
        'success': true,
        'message': 'Account created successfully',
        'user_id': userId,
      };
    } catch (e) {
      debugPrint('saveProfileAfterVerification error: $e');
      return {
        'success': false,
        'message': 'Error saving profile: ${e.toString()}',
      };
    }
  }



  /// Login using Supabase Auth
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      // Resolve email from username
      final account = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, is_active')
          .eq('username', username)
          .maybeSingle();

      if (account == null) {
        return {'success': false, 'message': 'Account does not exist'};
      }

      if (account['is_active'] == false) {
        return {'success': false, 'message': 'Account is deactivated'};
      }

      final response = await _supabase.auth.signInWithPassword(
        email: account['email'],
        password: password,
      );

      if (response.user == null) {
        return {'success': false, 'message': 'Invalid username or password'};
      }

      return {
        'success': true,
        'message': 'Login successful',
        'user_id': account['user_id'],
        'username': account['username'],
        'email': account['email'],
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Error during login: ${e.toString()}'};
    }
  }

  // ================================================================
  // USER PROFILE  (all original methods below — unchanged)
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

  /// Load all PII for a user from user_field_values.
  /// Returns a Map<String, dynamic> keyed by field_name.
  /// Loads from ALL templates and uses canonical_field_key for deduplication.
  Future<Map<String, dynamic>> loadPiiFromFieldValues(String userId) async {
    try {
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();
      
      if (templates.isEmpty) {
        debugPrint('❌ No templates found');
        return {};
      }
      
      debugPrint('✅ Loading from ${templates.length} templates');
      
      // Collect all fields across all templates
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
          .inFilter('field_id', fieldIds);

      // Map field_id → canonical_field_key (for deduplication)
      // If multiple templates have same canonical key, use first value found
      final idToCanonicalKey = {for (final f in allFields) f.fieldId: f.canonicalFieldKey};
      final result = <String, dynamic>{};
      
      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null || fval == null) continue;
        
        final canonicalKey = idToCanonicalKey[fid];
        if (canonicalKey != null && canonicalKey.isNotEmpty) {
          // Use canonical_field_key as the key (deduplicates across templates)
          if (!result.containsKey(canonicalKey)) {
            result[canonicalKey] = fval;
          }
        }
      }
      
      debugPrint('✅ Loaded ${result.length} unique fields via canonical keys');
      return result;
    } catch (e) {
      debugPrint('loadPiiFromFieldValues error: $e');
      return {};
    }
  }

  // Legacy PII save methods removed - all PII now saved to user_field_values via FieldValueService

  @Deprecated('Legacy method - use FieldValueService.pushToSubmission instead')
  Future<bool> pushProfileToSession({required String sessionId, required String userId}) async {
    debugPrint('⚠️ pushProfileToSession is deprecated - use FieldValueService.pushToSubmission');
    return false;
  }
  /// Sends the specific filtered data selected by the user to the web session.
  /// This allows the user to choose exactly which fields to transmit via checkboxes.
Future<bool> sendDataToWebSession(String sessionId, Map<String, dynamic> data, {String? userId}) async {
  try {
    final response = await _supabase
        .from('form_submission')
        .update({
          'form_data': data,
          'status': 'scanned',
          'scanned_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .select()
        .maybeSingle();

    // Intentionally do not write to client_submissions here.
    // client_submissions must only be written during staff finalize on web.

    return response != null;
  } catch (e) {
    debugPrint('Supabase Update Error: $e');
    return false;
  }
}

  // ================================================================
  // SUBMISSION INTERCEPTOR - REMOVED
  // ================================================================
  // Legacy methods removed - all data now flows through user_field_values
  // and submission_field_values. No more writes to family_composition or
  // other legacy tables.
}