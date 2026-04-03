import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:sappiire/services/form_template_service.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> signOutCurrentUser() {
    return _supabase.auth.signOut();
  }

  Future<Map<String, dynamic>?> fetchTemplatePopupConfig(
    String templateId,
  ) async {
    try {
      final row = await _supabase
          .from('form_templates')
          .select('popup_enabled, popup_subtitle, popup_description, form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('fetchTemplatePopupConfig error: $e');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> saveScannedIdFieldValues({
    required String userId,
    required Map<String, String> canonicalValues,
  }) async {
    try {
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();
      if (templates.isEmpty) {
        return {'success': false, 'message': 'No form templates found.'};
      }

      final allFields = templates.expand((t) => t.allFields).toList();
      final now = DateTime.now().toIso8601String();
      final aesKey = HybridCryptoService.deriveUserAesKey(userId);
      final rows = <Map<String, dynamic>>[];

      for (final entry in canonicalValues.entries) {
        final entryKey = _normalizeToken(entry.key);
        final value = entry.value.trim();
        if (entryKey.isEmpty || value.isEmpty) continue;

        final isCivilStatusKey =
            entryKey == 'estadong_sibil_civil_status' ||
            entryKey == 'civil_status' ||
            entryKey == 'marital_status';

        final matchingFields = allFields
            .where(
              (f) => _normalizeToken(f.canonicalFieldKey ?? '') == entryKey,
            )
            .toList();

        for (final field in matchingFields) {
          var mappedValue = value;
          if (isCivilStatusKey) {
            mappedValue = _resolveCivilStatusForField(field, mappedValue);
          }
          if (mappedValue.isEmpty) continue;

          final encrypted = await HybridCryptoService.encryptField(
            mappedValue,
            aesKey,
          );

          rows.add({
            'user_id': userId,
            'field_id': field.fieldId,
            'field_value': encrypted.ciphertext,
            'iv': encrypted.iv,
            'encryption_version': 1,
            'updated_at': now,
          });
        }
      }

      if (rows.isNotEmpty) {
        await _supabase
            .from('user_field_values')
            .upsert(rows, onConflict: 'user_id,field_id');
      }

      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Save failed: ${e.toString()}'};
    }
  }

  // Legacy column definitions removed - no longer needed with user_field_values architecture

  // ================================================================
  // AUTHENTICATION
  // ================================================================
  Future<Map<String, dynamic>> getAccountInfo(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, is_active, created_at, last_login')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return {'success': false, 'message': 'Account not found.'};
      }

      return {'success': true, 'data': response};
    } catch (e) {
      return {
        'success': false,
        'message': 'Error fetching profile: ${e.toString()}',
      };
    }
  }

  Future<void> updateAccountInfo(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    try {
      // We only send username and email to match your new SQL schema
      await _supabase
          .from('user_accounts')
          .update({'username': updates['username'], 'email': updates['email']})
          .eq('user_id', userId);
    } catch (e) {
      throw Exception('Failed to update account: $e');
    }
  }

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
              'message':
                  'This email is already registered. Please log in instead.',
            };
          } else {
            // Verified email but never finished — send OTP via signInWithOtp
            // and treat it as continuing their signup
            await _supabase.auth.signInWithOtp(
              email: email,
              shouldCreateUser:
                  false, // don't create, just send OTP to existing
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
      final signupPassword =
          password ?? DateTime.now().millisecondsSinceEpoch.toString();
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
        if (kDebugMode) {
          debugPrint('OTP send failed: $e');
        }
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
        'user_id':
            response.user!.id, // ← this is now reliable since OTP confirmed
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': 'Verification error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> resendEmailOtp(String email) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: false,
      );
      return {'success': true, 'message': 'Code resent! Check your email.'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Failed to resend: ${e.toString()}'};
    }
  }

  /// Step 3 of signup: Phone OTP.
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString();

      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/otp'),
        body: {
          'apikey': 'fc4874818b2f98480dbba9e862b90334',
          'number': phone,
          'message':
              'Your SapPIIre verification code is {otp}. Do not share this with anyone.',
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
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        });
        return {'success': true, 'message': 'OTP sent!'};
      } else {
        return {
          'success': false,
          'message': 'Semaphore error: ${response.body}',
        };
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
        return {
          'success': false,
          'message': 'Code has expired. Please request a new one.',
        };
      }

      await _supabase.from('phone_otp').delete().eq('id', data['id']);
      return {'success': true, 'message': 'Phone verified!'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  String _normalizeToken(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _civilStatusBucket(String raw) {
    final t = _normalizeToken(raw);
    if (t.isEmpty) return '';

    if (t == 's' || t.contains('single')) return 'single';
    if (t == 'm' || t.contains('married') || t.contains('kasal')) {
      return 'married';
    }
    if (t == 'w' || t.contains('widow') || t.contains('balo')) {
      return 'widowed';
    }
    if (t == 'sep' ||
        t.contains('separated') ||
        t.contains('hiwalay') ||
        t.contains('live_in') ||
        t.contains('livein')) {
      return 'separated';
    }
    if (t == 'a' || t.contains('annul')) return 'annulled';
    return '';
  }

  String _civilStatusDisplayValue(String raw) {
    switch (_civilStatusBucket(raw)) {
      case 'single':
        return 'Single';
      case 'married':
        return 'Married';
      case 'widowed':
        return 'Widowed';
      case 'separated':
        return 'Separated';
      case 'annulled':
        return 'Annulled';
      default:
        return raw;
    }
  }

  String _resolveCivilStatusForField(FormFieldModel field, String rawValue) {
    final input = rawValue.trim();
    if (input.isEmpty) return input;

    final bucket = _civilStatusBucket(input);
    if (bucket.isEmpty) return input;

    if (field.options.isNotEmpty) {
      for (final option in field.options) {
        final byValue = _civilStatusBucket(option.value);
        final byLabel = _civilStatusBucket(option.label);
        if (byValue == bucket || byLabel == bucket) {
          return option.value;
        }
      }
    }

    return _civilStatusDisplayValue(input);
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
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Password update failed: $e');
        }
        // Continue anyway - user can reset password later
      }

      // 2. Ensure user_accounts row exists (upsert username and email)
      await _supabase.from('user_accounts').upsert({
        'user_id': userId,
        'username': username,
        'email': email,
        'is_active': true,
      }, onConflict: 'user_id');

      // 3. Parse birthdate M/D/YYYY → YYYY-MM-DD
      final dateParts = dateOfBirth.split('/');
      final formattedDate = dateParts.length == 3
          ? '${dateParts[2]}-'
                '${dateParts[0].padLeft(2, '0')}-'
                '${dateParts[1].padLeft(2, '0')}'
          : dateOfBirth;
      final birthYear = dateParts.length == 3
          ? int.tryParse(dateParts[2])
          : null;
      final age = birthYear != null ? DateTime.now().year - birthYear : null;

      // 4. Fetch ALL templates to save data across all matching canonical keys
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();

      if (templates.isEmpty) {
        return {
          'success': false,
          'message':
              'System error: No form templates available. Contact administrator.',
        };
      }

      // Collect ALL fields across ALL templates
      final allFields = templates.expand((t) => t.allFields).toList();

      // 5. Build canonical_field_key → value map
      final piiData = {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'date_of_birth': formattedDate,
        if (age != null) 'age': age.toString(),
        'kasarian_sex':
            gender, // Already converted in signup (M/F or Male/Female)
        'estadong_sibil_civil_status':
            civilStatus, // Already converted in signup
        'civil_status': civilStatus,
        'marital_status': civilStatus,
        // Keep both legacy and new canonical aliases for compatibility.
        'place_of_birth': birthplace,
        'lugar_ng_kapanganakan_place_of_birth': birthplace,
        'cp_number': phoneNumber,
        'phone_number': phoneNumber,
        'contact_number': phoneNumber,
        'email_address': email,
        'house_number_street_name_phase_purok': addressLine,
      };

      // 6. Match canonical_field_key → field_id across ALL templates and save
      final now = DateTime.now().toIso8601String();
      final rows = <Map<String, dynamic>>[];

      for (final entry in piiData.entries) {
        if (entry.value.toString().isEmpty) {
          continue;
        }

        // Find ALL fields with this canonical key across ALL templates
        final matchingFields = allFields
            .where((f) => f.canonicalFieldKey == entry.key)
            .toList();

        if (matchingFields.isEmpty) {
          continue;
        }

        // Save to ALL matching fields (across all templates)
        for (final field in matchingFields) {
          var mappedValue = entry.value.toString();
          if (entry.key == 'estadong_sibil_civil_status' ||
              entry.key == 'civil_status' ||
              entry.key == 'marital_status') {
            mappedValue = _resolveCivilStatusForField(field, mappedValue);
          }

          rows.add({
            'user_id': userId,
            'field_id': field.fieldId,
            'field_value': mappedValue,
            'updated_at': now,
          });
        }
      }

      if (rows.isNotEmpty) {
        await _supabase
            .from('user_field_values')
            .upsert(rows, onConflict: 'user_id,field_id');
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
      return {
        'success': false,
        'message': 'Error during login: ${e.toString()}',
      };
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

  Future<List<Map<String, dynamic>>> fetchClientSubmissionHistoryByUser(
    String userId,
  ) async {
    try {
      final sessionRows = await _supabase
          .from('form_submission')
          .select('id')
          .eq('user_id', userId);

      final sessionIds = (sessionRows as List)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      if (sessionIds.isEmpty) {
        return [];
      }

      const fields =
          'id, form_type, intake_reference, created_at, session_id, data';

      final byColumn = await _supabase
          .from('client_submissions')
          .select(fields)
          .inFilter('session_id', sessionIds)
          .order('created_at', ascending: false);

      final submissions = List<Map<String, dynamic>>.from(byColumn as List);

      try {
        final byJsonb = await _supabase
            .from('client_submissions')
            .select(fields)
            .inFilter('data->>__session_id', sessionIds)
            .order('created_at', ascending: false);

        final seenIds = <dynamic>{for (final item in submissions) item['id']};
        for (final row in byJsonb as List) {
          if (!seenIds.contains(row['id'])) {
            submissions.add(Map<String, dynamic>.from(row as Map));
            seenIds.add(row['id']);
          }
        }
      } catch (_) {
        // JSONB filter is optional across environments.
      }

      return submissions;
    } catch (e) {
      debugPrint('fetchClientSubmissionHistoryByUser error: $e');
      return [];
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
        return {};
      }

      // Collect all fields across all templates
      final allFields = templates.expand((t) => t.allFields).toList();
      final fieldIds = allFields
          .where((f) => f.parentFieldId == null)
          .map((f) => f.fieldId)
          .toList();

      if (fieldIds.isEmpty) return {};

      final aesKey = HybridCryptoService.deriveUserAesKey(userId);

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, iv, encryption_version')
          .eq('user_id', userId)
          .inFilter('field_id', fieldIds)
          .order('updated_at', ascending: false);

      // Map field_id → canonical_field_key (for deduplication)
      // If multiple templates have same canonical key, use first value found
      final idToCanonicalKey = {
        for (final f in allFields) f.fieldId: f.canonicalFieldKey,
      };
      final result = <String, dynamic>{};

      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null ||
            fval == null ||
            fval.isEmpty ||
            fval == '__CLEARED__') {
          continue;
        }

        final rawVersion = row['encryption_version'];
        final version = rawVersion is int
            ? rawVersion
            : int.tryParse(rawVersion?.toString() ?? '') ?? 0;

        String resolvedValue = fval;
        if (version == 1) {
          final iv = row['iv'] as String? ?? '';
          if (iv.trim().isEmpty) {
            if (kDebugMode) {
              debugPrint(
                'loadPiiFromFieldValues warning: missing iv for encrypted field_id=$fid',
              );
            }
            continue;
          }

          resolvedValue = await HybridCryptoService.decryptField(
            fval,
            iv,
            aesKey,
          );

          if (resolvedValue.isEmpty) {
            if (kDebugMode) {
              debugPrint(
                'loadPiiFromFieldValues warning: decryption failed for field_id=$fid',
              );
            }
            continue;
          }
        }

        if (resolvedValue == '__CLEARED__' || resolvedValue.trim().isEmpty) {
          continue;
        }

        final canonicalKey = idToCanonicalKey[fid];
        if (canonicalKey != null && canonicalKey.isNotEmpty) {
          // Use canonical_field_key as the key (deduplicates across templates)
          if (!result.containsKey(canonicalKey)) {
            result[canonicalKey] = resolvedValue;
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('loadPiiFromFieldValues error: $e');
      return {};
    }
  }

  // Legacy PII save methods removed - all PII now saved to user_field_values via FieldValueService

  @Deprecated('Legacy method - use FieldValueService.pushToSubmission instead')
  Future<bool> pushProfileToSession({
    required String sessionId,
    required String userId,
  }) async {
    return false;
  }

  /// Sends the specific filtered data selected by the user to the web session.
  /// This allows the user to choose exactly which fields to transmit via checkboxes.
  Future<bool> sendDataToWebSession(
    String sessionId,
    Map<String, dynamic> data, {
    String? userId,
  }) async {
    try {
      final publicKey = await HybridCryptoService.fetchAndCacheRsaPublicKey(
        forceRefresh: true,
      );

      if (publicKey.trim().isEmpty) {
        final fallbackResponse = await _supabase
            .from('form_submission')
            .update({
              'form_data': data,
              'transmission_version': 0,
              'status': 'scanned',
              'scanned_at': DateTime.now().toUtc().toIso8601String(),
              if (userId != null) 'user_id': userId,
            })
            .eq('id', sessionId)
            .select()
            .maybeSingle();
        return fallbackResponse != null;
      }

      final envelope = await HybridCryptoService.encryptForTransmission(
        data,
        publicKey,
      );

      final response = await _supabase
          .from('form_submission')
          .update({
            'encrypted_payload': envelope.encryptedPayload,
            'payload_iv': envelope.payloadIv,
            'encrypted_aes_key': envelope.encryptedAesKey,
            'transmission_version': 1,
            'status': 'scanned',
            'scanned_at': DateTime.now().toUtc().toIso8601String(),
            if (userId != null) 'user_id': userId,
          })
          .eq('id', sessionId)
          .eq('status', 'active')
          .select()
          .maybeSingle();

      if (response == null) {
        return false;
      }

      await _invokeDecryptQrPayloadWithRetry(sessionId);

      // Intentionally do not write to client_submissions here.
      // client_submissions must only be written during staff finalize on web.

      return response != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sendDataToWebSession error for session $sessionId: $e');
      }
      return false;
    }
  }

  // ================================================================
  // SUBMISSION INTERCEPTOR - REMOVED
  // ================================================================
  // Legacy methods removed - all data now flows through user_field_values
  // and submission_field_values. No more writes to family_composition or
  // other legacy tables.

  Future<void> _invokeDecryptQrPayloadWithRetry(
    String sessionId, {
    int attempt = 1,
  }) async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'sendDataToWebSession decrypt-qr-payload session=$sessionId: missing access token, skipping invoke',
          );
        }
        return;
      }

      final response = await _supabase.functions.invoke(
        'decrypt-qr-payload',
        body: {'sessionId': sessionId},
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final data = response.data;
      final reason = data is Map ? data['reason']?.toString() : null;
      final success = data is Map ? data['success'] == true : false;

      if (!success && kDebugMode) {
        debugPrint(
          'sendDataToWebSession decrypt-qr-payload session=$sessionId attempt=$attempt returned: $data',
        );
      }

      // Retry only for transient timing/readiness failures.
      if (!success &&
          attempt < 4 &&
          (reason == 'session_not_found_or_fetch_failed' ||
              reason == 'missing_encrypted_columns')) {
        final delayMs = attempt == 1
            ? 400
            : attempt == 2
            ? 900
            : 1600;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        await _invokeDecryptQrPayloadWithRetry(sessionId, attempt: attempt + 1);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'sendDataToWebSession decrypt-qr-payload session=$sessionId warning attempt=$attempt: $e',
        );
      }
    }
  }
}
