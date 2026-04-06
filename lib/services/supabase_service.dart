import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/services/form_template_service.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;
  final _fieldValueService = FieldValueService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> signOutCurrentUser() {
    return _supabase.auth.signOut();
  }

  // ================================================================
  // TEMPLATE POPUP CONFIG
  // ================================================================
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
      debugPrint('fetchTemplatePopupConfig error: $e');
      return null;
    }
  }

  // ================================================================
  // PII SAVE — canonical key matching across all templates
  // ================================================================
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
      final formDataByTemplate = <String, Map<String, dynamic>>{};

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

          final templateData = formDataByTemplate.putIfAbsent(
            field.templateId,
            () => <String, dynamic>{},
          );
          templateData[field.fieldName] = mappedValue;
        }
      }

      var savedAny = false;
      for (final template in templates) {
        final formData = formDataByTemplate[template.templateId];
        if (formData == null || formData.isEmpty) continue;

        final saved = await _fieldValueService.saveUserFieldValues(
          userId: userId,
          template: template,
          formData: formData,
        );
        if (saved) savedAny = true;
      }

      if (savedAny) return {'success': true};

      return {
        'success': false,
        'message': 'No template values were saved.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Save failed: ${e.toString()}'};
    }
  }

  // ================================================================
  // AUTHENTICATION — getAccountInfo
  // ================================================================
  Future<Map<String, dynamic>> getAccountInfo(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select(
            'user_id, username, email, phone_number, is_active, created_at, last_login',
          )
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

  // ── updateAccountInfo — only updates username, email/phone not editable ──
  Future<void> updateAccountInfo(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _supabase
          .from('user_accounts')
          .update({'username': updates['username']})
          .eq('user_id', userId);
    } catch (e) {
      throw Exception('Failed to update account: $e');
    }
  }

  // ── checkDuplicateSignup ──────────────────────────────────────────
  Future<Map<String, dynamic>> checkDuplicateSignup({
    String? email,
    String? phone,
    String? username,
  }) async {
    try {
      if (email != null && email.isNotEmpty) {
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id')
            .eq('email', email.trim().toLowerCase())
            .maybeSingle();
        if (existing != null) {
          return {
            'success': false,
            'field': 'email',
            'message':
                'This email is already registered. Please log in instead.',
          };
        }
      }

      if (phone != null && phone.isNotEmpty) {
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id')
            .eq('phone_number', phone.trim())
            .maybeSingle();
        if (existing != null) {
          return {
            'success': false,
            'field': 'phone',
            'message': 'This phone number is already registered.',
          };
        }
      }

      if (username != null && username.isNotEmpty) {
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id')
            .eq('username', username.trim())
            .maybeSingle();
        if (existing != null) {
          return {
            'success': false,
            'field': 'username',
            'message': 'This username is already taken. Please choose another.',
          };
        }
      }

      return {'success': true};
    } catch (e) {
      return {
        'success': false,
        'message': 'Validation error: ${e.toString()}',
      };
    }
  }

  // ── signUpWithEmail ───────────────────────────────────────────────
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    String? password,
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
              'message':
                  'This email is already registered. Please log in instead.',
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

      final signupPassword =
          password ?? DateTime.now().millisecondsSinceEpoch.toString();
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
        debugPrint('OTP send failed: $e');
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

  // ── verifyEmailOtp ────────────────────────────────────────────────
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
      return {
        'success': false,
        'message': 'Verification error: ${e.toString()}',
      };
    }
  }

  // ── resendEmailOtp ────────────────────────────────────────────────
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
      return {
        'success': false,
        'message': 'Failed to resend: ${e.toString()}',
      };
    }
  }

  // ── sendPhoneOtp ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final otp =
          (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();

      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/otp'),
        body: {
          'apikey': 'fc4874818b2f98480dbba9e862b90334',
          'number': phone,
          'message':
              'Your SapPIIre verification code is {otp}. Do not share this with anyone.',
          'code': otp,
          'sendername': 'SapPIIre',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
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

  // ── verifyPhoneOtp ────────────────────────────────────────────────
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

  // ── LOGIN — supports username, email, or phone ────────────────────
  // Track failed attempts per identifier in memory
  static final Map<String, int> _failedAttempts = {};
  static final Map<String, DateTime> _lockoutUntil = {};
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final identifier = username.trim().toLowerCase();

    // Check lockout
    final lockout = _lockoutUntil[identifier];
    if (lockout != null && DateTime.now().isBefore(lockout)) {
      final remaining = lockout.difference(DateTime.now()).inMinutes + 1;
      return {
        'success': false,
        'message':
            'Too many failed attempts. Try again in $remaining minute(s).',
      };
    }

    try {
      // Resolve account by username, email, or phone
      final account = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, phone_number, is_active')
          .or(
            'username.ilike.$identifier,'
            'email.ilike.$identifier,'
            'phone_number.eq.$identifier',
          )
          .maybeSingle();

      if (account == null) {
        _recordFailedAttempt(identifier);
        return {'success': false, 'message': 'Account does not exist.'};
      }

      if (account['is_active'] == false) {
        return {'success': false, 'message': 'Account is deactivated.'};
      }

      final response = await _supabase.auth.signInWithPassword(
        email: account['email'],
        password: password,
      );

      if (response.user == null) {
        _recordFailedAttempt(identifier);
        final attempts = _failedAttempts[identifier] ?? 0;
        final remaining = _maxAttempts - attempts;
        return {
          'success': false,
          'message': remaining > 0
              ? 'Invalid password. $remaining attempt(s) remaining.'
              : 'Account locked for ${_lockoutDuration.inMinutes} minutes.',
        };
      }

      // Clear failed attempts on success
      _failedAttempts.remove(identifier);
      _lockoutUntil.remove(identifier);

      // Save last_login timestamp
      try {
        await _supabase
            .from('user_accounts')
            .update({'last_login': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', account['user_id']);
      } catch (e) {
        debugPrint('last_login update failed: $e');
      }

      return {
        'success': true,
        'message': 'Login successful',
        'user_id': account['user_id'],
        'username': account['username'],
        'email': account['email'],
      };
    } on AuthException catch (e) {
      _recordFailedAttempt(identifier);
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {
        'success': false,
        'message': 'Error during login: ${e.toString()}',
      };
    }
  }

  void _recordFailedAttempt(String identifier) {
    _failedAttempts[identifier] = (_failedAttempts[identifier] ?? 0) + 1;
    if ((_failedAttempts[identifier] ?? 0) >= _maxAttempts) {
      _lockoutUntil[identifier] = DateTime.now().add(_lockoutDuration);
      _failedAttempts.remove(identifier);
    }
  }

  // ── saveProfileAfterVerification — Step 4 of signup ──────────────
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
      // 1. Set password in Supabase Auth
      try {
        await _supabase.auth.updateUser(UserAttributes(password: password));
      } catch (e) {
        debugPrint('Password update failed: $e');
      }

      // 2. Upsert user_accounts — includes phone_number
      await _supabase.from('user_accounts').upsert({
        'user_id': userId,
        'username': username,
        'email': email,
        'phone_number': phoneNumber,
        'is_active': true,
      }, onConflict: 'user_id');

      // 3. Parse birthdate M/D/YYYY → YYYY-MM-DD
      final dateParts = dateOfBirth.split('/');
      final formattedDate = dateParts.length == 3
          ? '${dateParts[2]}-'
                '${dateParts[0].padLeft(2, '0')}-'
                '${dateParts[1].padLeft(2, '0')}'
          : dateOfBirth;
      final birthYear =
          dateParts.length == 3 ? int.tryParse(dateParts[2]) : null;
      final age =
          birthYear != null ? DateTime.now().year - birthYear : null;

      // 4. Fetch ALL templates
      final templateSvc = FormTemplateService();
      final templates = await templateSvc.fetchActiveTemplates();

      if (templates.isEmpty) {
        return {
          'success': false,
          'message':
              'System error: No form templates available. Contact administrator.',
        };
      }

      final allFields = templates.expand((t) => t.allFields).toList();

      // 5. Build canonical_field_key → value map
      final piiData = {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'date_of_birth': formattedDate,
        if (age != null) 'age': age.toString(),
        'kasarian_sex': gender,
        'estadong_sibil_civil_status': civilStatus,
        'civil_status': civilStatus,
        'marital_status': civilStatus,
        // Keep both canonical aliases for compatibility.
        'place_of_birth': birthplace,
        'lugar_ng_kapanganakan_place_of_birth': birthplace,
        'cp_number': phoneNumber,
        'phone_number': phoneNumber,
        'contact_number': phoneNumber,
        'email_address': email,
        'house_number_street_name_phase_purok': addressLine,
      };

      // 6. Match canonical_field_key → field_id across ALL templates and save
      final formDataByTemplate = <String, Map<String, dynamic>>{};

      for (final entry in piiData.entries) {
        if (entry.value.toString().isEmpty) continue;

        final matchingFields = allFields
            .where((f) => f.canonicalFieldKey == entry.key)
            .toList();

        if (matchingFields.isEmpty) continue;

        for (final field in matchingFields) {
          var mappedValue = entry.value.toString();
          if (entry.key == 'estadong_sibil_civil_status' ||
              entry.key == 'civil_status' ||
              entry.key == 'marital_status') {
            mappedValue = _resolveCivilStatusForField(field, mappedValue);
          }

          final templateData = formDataByTemplate.putIfAbsent(
            field.templateId,
            () => <String, dynamic>{},
          );
          templateData[field.fieldName] = mappedValue;
        }
      }

      for (final template in templates) {
        final formData = formDataByTemplate[template.templateId];
        if (formData == null || formData.isEmpty) continue;

        final saved = await _fieldValueService.saveUserFieldValues(
          userId: userId,
          template: template,
          formData: formData,
        );

        if (!saved) {
          throw Exception(
            'Failed to save profile fields for template ${template.templateId}',
          );
        }
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

  // ================================================================
  // HISTORY — fetchClientSubmissionHistoryByUser
  // Reads form_submission to get session IDs for this user,
  // then reads client_submissions for display data.
  // Resolves worker UUIDs to names via staff_profiles.
  // ================================================================
  Future<List<Map<String, dynamic>>> fetchClientSubmissionHistoryByUser(
    String userId,
  ) async {
    try {
      // Step 1: Get all form_submission IDs for this user
      final sessionRows = await _supabase
          .from('form_submission')
          .select('id, created_at, scanned_at')
          .eq('user_id', userId);

      final sessionIds = (sessionRows as List)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      // Build a map of session_id -> scanned_at for scan time lookup
      final scanTimeMap = <String, String>{};
      for (final row in sessionRows as List) {
        final id = row['id']?.toString() ?? '';
        final scannedAt = row['scanned_at']?.toString() ?? '';
        final createdAt = row['created_at']?.toString() ?? '';
        if (id.isNotEmpty) {
          scanTimeMap[id] = scannedAt.isNotEmpty ? scannedAt : createdAt;
        }
      }

      if (sessionIds.isEmpty) return [];

      const fields =
          'id, form_type, intake_reference, created_at, session_id, data, last_edited_by, last_edited_at';

      // Step 2: Match client_submissions by session_id column
      final byColumn = await _supabase
          .from('client_submissions')
          .select(fields)
          .inFilter('session_id', sessionIds)
          .order('created_at', ascending: false);

      final submissions = List<Map<String, dynamic>>.from(byColumn as List);

      // Step 3: Also try JSONB match (fallback for older records)
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
        // JSONB filter is optional
      }

      // Step 4: Inject scan time from form_submission into each record
      for (final s in submissions) {
        final sid = s['session_id']?.toString() ?? '';
        if (sid.isNotEmpty && scanTimeMap.containsKey(sid)) {
          s['scanned_at'] = scanTimeMap[sid];
        }
        // If scanned_at not set, fall back to created_at
        s['scanned_at'] ??= s['created_at'];
      }

      // Step 5: Resolve worker UUIDs to names via staff_profiles
      // last_edited_by may store a UUID (cswd_id) or a plain name string
      final workerIds = submissions
          .map((s) => s['last_edited_by']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty && _looksLikeUuid(id))
          .toSet()
          .toList();

      if (workerIds.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('staff_profiles')
              .select('cswd_id, first_name, last_name')
              .inFilter('cswd_id', workerIds);

          final nameMap = <String, String>{};
          for (final p in profiles as List) {
            final id = p['cswd_id']?.toString() ?? '';
            final name = [
              p['first_name']?.toString() ?? '',
              p['last_name']?.toString() ?? '',
            ].where((s) => s.isNotEmpty).join(' ');
            if (id.isNotEmpty && name.isNotEmpty) nameMap[id] = name;
          }

          // Replace UUID with display name in-place
          for (final s in submissions) {
            final editorId = s['last_edited_by']?.toString().trim() ?? '';
            if (nameMap.containsKey(editorId)) {
              s['last_edited_by'] = nameMap[editorId];
            }
          }
        } catch (e) {
          debugPrint('Worker name resolution error: $e');
        }
      }

      return submissions;
    } catch (e) {
      debugPrint('fetchClientSubmissionHistoryByUser error: $e');
      return [];
    }
  }

  // ── Helper: detect UUID string ──────────────────────────────────
  bool _looksLikeUuid(String s) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(s);
  }

  // ================================================================
  // PII LOAD — loadPiiFromFieldValues
  // ================================================================
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

      final aesKey = HybridCryptoService.deriveUserAesKey(userId);

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, iv, encryption_version')
          .eq('user_id', userId)
          .inFilter('field_id', fieldIds)
          .order('updated_at', ascending: false);

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
            debugPrint(
              'loadPiiFromFieldValues warning: missing iv for field_id=$fid',
            );
            continue;
          }

          resolvedValue = await HybridCryptoService.decryptField(
            fval,
            iv,
            aesKey,
          );

          if (resolvedValue.isEmpty) {
            debugPrint(
              'loadPiiFromFieldValues warning: decryption failed for field_id=$fid',
            );
            continue;
          }
        }

        if (resolvedValue == '__CLEARED__' || resolvedValue.trim().isEmpty) {
          continue;
        }

        final canonicalKey = idToCanonicalKey[fid];
        if (canonicalKey != null && canonicalKey.isNotEmpty) {
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

  /// Sends the specific filtered data selected by the user to the web session.
  /// This allows the user to choose exactly which fields to transmit via checkboxes.
  Future<bool> sendDataToWebSession(
    String sessionId,
    Map<String, dynamic> data, {
    String? userId,
  }) async {
    try {
      // Attempt hybrid encryption
      String publicKey = '';
      try {
        publicKey = await HybridCryptoService.fetchAndCacheRsaPublicKey(
          forceRefresh: true,
        );
      } catch (e) {
        debugPrint('RSA public key fetch failed: $e');
      }

      if (publicKey.trim().isEmpty) {
        // Fallback: transmit unencrypted (transmission_version = 0)
        debugPrint(
          'sendDataToWebSession: no RSA key, falling back to unencrypted',
        );
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
        // Session may not be 'active' anymore — try without status filter
        debugPrint(
          'sendDataToWebSession: status=active filter returned null, retrying without filter',
        );
        final retryResponse = await _supabase
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
            .select()
            .maybeSingle();

        if (retryResponse == null) return false;
      }

      // Invoke edge function to decrypt on server side
      await _invokeDecryptQrPayloadWithRetry(sessionId);

      return true;
    } catch (e) {
      debugPrint('sendDataToWebSession error for session $sessionId: $e');
      return false;
    }
  }

  Future<void> _invokeDecryptQrPayloadWithRetry(
    String sessionId, {
    int attempt = 1,
  }) async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint(
          'decrypt-qr-payload session=$sessionId: missing access token, skipping',
        );
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
          'decrypt-qr-payload session=$sessionId attempt=$attempt returned: $data',
        );
      }

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
      debugPrint(
        'decrypt-qr-payload session=$sessionId warning attempt=$attempt: $e',
      );
    }
  }

  // ================================================================
  // HELPERS
  // ================================================================
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

}
