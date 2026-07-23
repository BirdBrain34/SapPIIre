// ignore_for_file: use_null_aware_elements
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/log_util.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;
  final _fieldValueService = FieldValueService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> signOutCurrentUser() {
    HybridCryptoService.clearFieldKeyCache();
    return _supabase.auth.signOut();
  }

  /// Permanently erases the signed-in user's account and PII (Data Privacy Act
  /// of 2012 right to erasure). Runs server-side in the `manage-user-account`
  /// Edge Function using the service-role key — the caller's JWT is attached
  /// automatically, and the function derives the target user from it, so a user
  /// can only ever delete their own account. Finalized submissions and the
  /// audit trail are retained by the office.
  ///
  /// On success the local session is cleared. Returns `{'success', 'message'}`.
  Future<Map<String, dynamic>> deleteMyAccount() async {
    try {
      final response = await _supabase.functions.invoke(
        'manage-user-account',
        body: {'action': 'delete_account'},
      );

      final data = response.data;
      final ok = data is Map && data['success'] == true;
      if (!ok) {
        final message = data is Map && data['message'] is String
            ? data['message'] as String
            : 'Account deletion failed. Please try again.';
        return {'success': false, 'message': message};
      }

      await signOutCurrentUser();
      return {'success': true};
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/deleteMyAccount] Error: $e');
      return {
        'success': false,
        'message': 'Account deletion failed. Please try again.',
      };
    }
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
      LogUtil.debugPrint('[SupabaseService/fetchTemplatePopupConfig] Error: $e');
      return null;
    }
  }

  /// Fetch all notifications ordered newest-first, plus which ones the
  /// current user has already read (from user_notification_reads).
  Future<Map<String, dynamic>> fetchAppNotifications(String userId) async {
    try {
      // Fetch all notifications, newest first.
      final rows = await _supabase
          .from('form_template_notifications')
          .select('id, template_id, template_name, change_type, change_summary, created_at, details')
          .order('created_at', ascending: false)
          .limit(100);
 
      final notifications = List<Map<String, dynamic>>.from(rows as List);
 
      // Fetch which ones this user has read.
      final readRows = await _supabase
          .from('user_notification_reads')
          .select('notification_id')
          .eq('user_id', userId);
 
      final readIds = (readRows as List)
          .map((r) => r['notification_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
 
      return {
        'notifications': notifications,
        'readIds': readIds,
      };
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/fetchAppNotifications] Error: $e');
      return {'notifications': <Map<String, dynamic>>[], 'readIds': <String>[]};
    }
  }
 
  /// Mark one or more notification IDs as read for the given user.
  Future<void> markNotificationsRead({
    required String userId,
    required List<String> notificationIds,
  }) async {
    if (notificationIds.isEmpty) return;
    try {
      final rows = notificationIds
          .map((id) => {'user_id': userId, 'notification_id': id})
          .toList();
 
      await _supabase
          .from('user_notification_reads')
          .upsert(rows, onConflict: 'user_id,notification_id');
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/markNotificationsRead] Error: $e');
    }
  }
 
  /// Returns the count of unread notifications for the bell badge.
  /// Counts unread template notifications (form_template_notifications) plus
  /// unread submission notifications (user_submission_notifications).
  Future<int> fetchUnreadNotificationCount(String userId) async {
    try {
      // ── Template notification unreads ──
      final allRows = await _supabase
          .from('form_template_notifications')
          .select('id')
          .order('created_at', ascending: false)
          .limit(100);

      final allIds = (allRows as List)
          .map((r) => r['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      int templateUnread = 0;
      if (allIds.isNotEmpty) {
        final readRows = await _supabase
            .from('user_notification_reads')
            .select('notification_id')
            .eq('user_id', userId);

        final readIds = (readRows as List)
            .map((r) => r['notification_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        templateUnread = allIds.difference(readIds).length;
      }

      // ── Submission notification unreads ──
      int submissionUnread = 0;
      try {
        final subRows = await _supabase
            .from('user_submission_notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('is_read', false)
            .limit(100);

        submissionUnread = (subRows as List).length;
      } catch (_) {
        // user_submission_notifications may not exist yet; treat as 0.
      }

      return templateUnread + submissionUnread;
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/fetchUnreadNotificationCount] Error: $e');
      return 0;
    }
  }

  /// Saves PII from OCR scanning (ID scanner) using canonical key matching.
  ///
  /// This intentionally uses a fixed set of keys (OCR cannot produce arbitrary
  /// custom data). That fixed set now has a durable, protected home in the
  /// canonical_key_registry table as is_system = true rows. Do NOT generalize
  /// this to read from the registry — OCR/signup only populate the identity
  /// fields they can actually extract (first_name, last_name, etc.).
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
          // Strip stray square brackets that may have been introduced
          // during address formatting or other legacy data flows.
          mappedValue = mappedValue.replaceAll(RegExp(r'[\[\]]'), '').trim();
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
        final updates = formDataByTemplate[template.templateId];
        if (updates == null || updates.isEmpty) continue;

        final existing = await _fieldValueService.loadUserFieldValues(
          userId: userId,
          template: template,
        );
        final merged = <String, dynamic>{...existing, ...updates};

        final saved = await _fieldValueService.saveUserFieldValues(
          userId: userId,
          template: template,
          formData: merged,
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

  Future<bool> isSessionFinalized(String sessionId) async {
    try {
      final result = await _supabase
          .from('form_submission')
          .select('status')
          .eq('id', sessionId)
          .maybeSingle();

      if (result == null) return false;

      final status = result['status'] as String? ?? '';
      return status == 'completed';
    } catch (_) {
      return false;
    }
  }

  // Fetch account information for a user.
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

  // Update the username stored in user_accounts.
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

  // Check whether email, phone, or username already exists.
  // If a record exists but has no user_field_values, it's an incomplete
  // signup — we allow retrying by returning success with the existing user_id.
  Future<Map<String, dynamic>> checkDuplicateSignup({
    String? email,
    String? phone,
    String? username,
  }) async {
    try {
      if (email != null && email.isNotEmpty) {
        final normalizedEmail = email.trim().toLowerCase();
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id, email')
            .ilike('email', normalizedEmail)
            .maybeSingle();
        if (existing != null) {
          final userId = existing['user_id'] as String?;
          if (userId != null && userId.isNotEmpty) {
            // Check if this is a completed signup (has field values)
            final fieldValues = await _supabase
                .from('user_field_values')
                .select('id')
                .eq('user_id', userId)
                .limit(1)
                .maybeSingle();
            if (fieldValues != null) {
              return {
                'success': false,
                'field': 'email',
                'message':
                    'This email is already registered. Please log in instead.',
              };
            }
            // Incomplete signup — allow retry by returning success with user_id
            return {
              'success': true,
              'user_id': userId,
              'incomplete': true,
            };
          }
        }
      }

      if (phone != null && phone.isNotEmpty) {
        final rawPhone = phone.trim();
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id')
            .eq('phone_number', rawPhone)
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
                'field': 'phone',
                'message': 'This phone number is already registered.',
              };
            }
            // Incomplete signup — allow retry
            return {
              'success': true,
              'user_id': userId,
              'incomplete': true,
            };
          }
        }
      }

      if (username != null && username.isNotEmpty) {
        final existing = await _supabase
            .from('user_accounts')
            .select('user_id')
            .ilike('username', username.trim())
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

  // Sign up with email and send an OTP when needed.
  //
  // [allowOtpRecovery] should be true for the real-email flow (we can
  // legitimately email an OTP to recover an orphaned signup), and false
  // for the phone-only flow's synthetic email (nobody reads
  // digits@sappiire.phone — recovery there must use the password instead).
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    String? password,
    bool allowOtpRecovery = true,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      // Check user_accounts with case-insensitive match
      final existing = await _supabase
          .from('user_accounts')
          .select('email, user_id')
          .ilike('email', normalizedEmail)
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
              email: normalizedEmail,
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

      try {
        final res = await _supabase.auth.signUp(
          email: normalizedEmail,
          password: signupPassword,
          emailRedirectTo: null,
        );

        if (res.user == null) {
          return {'success': false, 'message': 'Sign-up failed. Try again.'};
        }

        if (allowOtpRecovery) {
          try {
            await _supabase.auth.signInWithOtp(
              email: email,
              shouldCreateUser: false,
            );
          } catch (e) {
            LogUtil.debugPrint('[SupabaseService/signUpWithEmail] Warning: OTP send failed: $e');
          }
        }

        return {
          'success': true,
          'message': allowOtpRecovery ? 'OTP sent! Check your email.' : 'Account created.',
          'user_id': res.user!.id,
        };
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        final looksOrphaned =
            msg.contains('already registered') || msg.contains('already exists');

        if (!looksOrphaned) {
          return {'success': false, 'message': e.message};
        }

        // A previous attempt created the Auth user but never finished
        // writing user_accounts (e.g. connection dropped). Try to recover
        // instead of permanently blocking this email/phone.
        if (allowOtpRecovery) {
          try {
            await _supabase.auth.signInWithOtp(
              email: normalizedEmail,
              shouldCreateUser: false,
            );
            return {
              'success': true,
              'message':
                  'We found an incomplete previous signup — code resent, check your email.',
              'user_id': null,
            };
          } catch (_) {
            return {
              'success': false,
              'message':
                  'This email has an incomplete previous signup attempt. Please contact support.',
            };
          }
        } else {
          // Synthetic phone-email flow: try the password just entered, in
          // case this is a retry of the exact same failed attempt.
          try {
            final signInRes = await _supabase.auth.signInWithPassword(
              email: normalizedEmail,
              password: signupPassword,
            );
            if (signInRes.user != null) {
              return {
                'success': true,
                'message': 'Resumed previous signup.',
                'user_id': signInRes.user!.id,
              };
            }
          } catch (_) {
            // Falls through to the error below.
          }
          return {
            'success': false,
            'message':
                'This phone number has an incomplete previous signup attempt. Please contact support to reset it.',
          };
        }
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  // Verify an email OTP.
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

  // Resend an email OTP.
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

  /// Send an OTP to the given email (used for retrying incomplete signups).
  Future<Map<String, dynamic>> signInWithOtp({
    required String email,
  }) async {
    try {
      await _supabase.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: false,
      );
      return {'success': true, 'message': 'OTP sent!'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Send a phone OTP via the Supabase Edge Function (faster — runs on cloud infra).
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-phone-otp',
        body: {'phone': phone},
      );

      if (response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return data;
      } else {
        return {
          'success': false,
          'message': 'Failed to send OTP. No response from server.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Verify a phone OTP.
  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final result = await _supabase.rpc(
        'verify_and_consume_phone_otp',
        params: <String, dynamic>{
          'p_phone': phone.trim(),
          'p_otp':   otp.trim(),
        },
      );

      if (result == true) {
        return {'success': true, 'message': 'Phone verified!'};
      }
      return {
        'success': false,
        'message': 'Invalid or expired code. Please request a new one.',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Log in with username, email, or phone.
  // Track failed attempts by identifier in memory.
  static final Map<String, int> _failedAttempts = {};
  static final Map<String, DateTime> _lockoutUntil = {};
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final identifier = username.trim().toLowerCase();

    // Enforce the lockout window before retrying.
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
      // Resolve the account by username or email using parameterized queries
      // instead of .or() string interpolation to prevent PostgREST filter-grammar
      // injection (CWE-89). Each .ilike() call safely binds the user-supplied
      // value as a query parameter rather than embedding it in a filter string.
      Map<String, dynamic>? account = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, phone_number, is_active')
          .ilike('username', identifier)
          .maybeSingle();

      if (account == null) {
        account = await _supabase
            .from('user_accounts')
            .select('user_id, username, email, phone_number, is_active')
            .ilike('email', identifier)
            .maybeSingle();
      }

      if (account == null) {
        _recordFailedAttempt(identifier);
        return {'success': false, 'message': 'Account does not exist.'};
      }

      if (account['is_active'] == false) {
        return {'success': false, 'message': 'Account is deactivated.'};
      }

      // Determine the email to use for Supabase Auth sign-in.
      // - Email/both accounts: use the real email stored in user_accounts.
      // - Phone-only accounts (email is null): reconstruct the synthetic auth
      //   email from the phone number. This matches what was created during signup.
      final String? storedEmail = account['email'] as String?;
      final String? storedPhone = account['phone_number'] as String?;

      final String authEmail;
      if (storedEmail != null && storedEmail.isNotEmpty) {
        authEmail = storedEmail;
      } else if (storedPhone != null && storedPhone.isNotEmpty) {
        // Phone-only account: synthetic email used in Supabase Auth
        final digits = storedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        authEmail = '$digits@sappiire.phone';
      } else {
        // Should never happen due to DB constraint, but guard anyway
        _recordFailedAttempt(identifier);
        return {
          'success': false,
          'message': 'Account has no valid login method. Contact support.',
        };
      }

      final response = await _supabase.auth.signInWithPassword(
        email: authEmail,
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

      // Clear failed attempts after a successful login.
      _failedAttempts.remove(identifier);
      _lockoutUntil.remove(identifier);

      // Save the latest login timestamp.
      try {
        await _supabase
            .from('user_accounts')
            .update({'last_login': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', account['user_id']);
      } catch (e) {
        LogUtil.debugPrint('[SupabaseService/login] Warning: last_login update failed: $e');
      }

      return {
        'success': true,
        'message': 'Login successful',
        'user_id': account['user_id'],
        'username': account['username'],
        'email': storedEmail, // null for phone-only, that's fine
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

  /// Saves the profile data after verification.
  /// 
  /// This intentionally uses a fixed set of keys (first_name, last_name, etc.)
  /// that align with the `is_system = true` rows in the `canonical_key_registry`.
  /// Do NOT generalize this to read from the registry — the signup flow only 
  /// collects these specific core identity fields.
  Future<Map<String, dynamic>> saveProfileAfterVerification({
    required String userId,
    required String username,
    required String password,
    required String? email,       // null for phone-only accounts
    required String? phoneNumber, // null for email-only accounts
    required String firstName,
    required String middleName,
    required String lastName,
    required String dateOfBirth,
    required String birthplace,
    required String gender,
    required String civilStatus,
    required String addressLine,
  }) async {
    try {
      // Set the password in Supabase Auth.
      try {
        await _supabase.auth.updateUser(UserAttributes(password: password));
      } catch (e) {
        LogUtil.debugPrint('[SupabaseService/saveProfileAfterVerification] Warning: Password update failed: $e');
      }

      // Parse the birthdate into YYYY-MM-DD format.
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

      // Fetch all templates.
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

      // Build the canonical field map used for saving profile data.
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
        // Keep both aliases for compatibility.
        'place_of_birth': birthplace,
        'lugar_ng_kapanganakan_place_of_birth': birthplace,
        'house_number_street_name_phase_purok': addressLine,
        // Email/phone, kept as multiple aliases — see note below.
        if (email != null && email.isNotEmpty) ...{
          'email': email,
          'email_address': email,
        },
        if (phoneNumber != null && phoneNumber.isNotEmpty) ...{
          'phone_number': phoneNumber,
          'contact_number': phoneNumber,
          'numero_ng_telepono_contact_number': phoneNumber,
        },
      };

      // Match canonical keys to field IDs across all templates and save.
      final formDataByTemplate = <String, Map<String, dynamic>>{};

      for (final entry in piiData.entries) {
        if (entry.value.isEmpty) continue;

        final matchingFields = allFields
            .where((f) => f.canonicalFieldKey == entry.key)
            .toList();

        if (matchingFields.isEmpty) continue;

        for (final field in matchingFields) {
          var mappedValue = entry.value;
          if (entry.key == 'estadong_sibil_civil_status' ||
              entry.key == 'civil_status' ||
              entry.key == 'marital_status') {
            mappedValue = _resolveCivilStatusForField(field, mappedValue);
          }
          mappedValue = mappedValue.replaceAll(RegExp(r'[\[\]]'), '').trim();
          if (mappedValue.isEmpty) continue;

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

      // Only upsert user_accounts AFTER field values are saved successfully.
      // This ensures that if something fails above, no orphaned record in
      // user_accounts blocks the user from retrying signup.
      final upsertData = <String, dynamic>{
        'user_id': userId,
        'username': username,
        'is_active': true,
      };

      // Only include email/phone if non-null and non-empty
      if (email != null && email.isNotEmpty) {
        upsertData['email'] = email.toLowerCase().trim();
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        upsertData['phone_number'] = phoneNumber.trim();
      }

      await _supabase.from('user_accounts').upsert(
        upsertData,
        onConflict: 'user_id',
      );

      return {
        'success': true,
        'message': 'Account created successfully',
        'user_id': userId,
      };
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/saveProfileAfterVerification] Error: $e');
      return {
        'success': false,
        'message': 'Error saving profile: ${e.toString()}',
      };
    }
  }

  // Fetch the stored username for a user.
  Future<String?> getUsername(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      return response?['username'] as String?;
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/getUsername] Error: $e');
      return null;
    }
  }

  // Read submission history and resolve worker names for display.
  Future<List<Map<String, dynamic>>> fetchClientSubmissionHistoryByUser(
    String userId,
  ) async {
    try {
      // Get all form_submission IDs for this user.
      final sessionRows = await _supabase
          .from('form_submission')
          .select('id, created_at, scanned_at')
          .eq('user_id', userId);

      final sessionIds = (sessionRows as List)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      // Build a map from session_id to scanned_at for lookup.
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
          'id, form_type, intake_reference, created_at, session_id, data, created_by, last_edited_by, last_edited_at, review_status, reviewed_at, review_notes';

      // Match client_submissions by session_id.
      final byColumn = await _supabase
          .from('client_submissions')
          .select(fields)
          .inFilter('session_id', sessionIds)
          .order('created_at', ascending: false);

      final submissions = List<Map<String, dynamic>>.from(byColumn as List);

      // Try the JSONB fallback for older records.
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
        // JSONB filter is optional.
      }

      // Copy scan time from form_submission into each record.
      for (final s in submissions) {
        final sid = s['session_id']?.toString() ?? '';
        if (sid.isNotEmpty && scanTimeMap.containsKey(sid)) {
          s['scanned_at'] = scanTimeMap[sid];
        }
        // Fall back to created_at when scanned_at is missing.
        s['scanned_at'] ??= s['created_at'];
      }

      // Resolve worker UUIDs to names via staff_profiles.
      // last_edited_by may store a UUID or a plain name.
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

          // Replace UUIDs with display names in place.
          for (final s in submissions) {
            final editorId = s['last_edited_by']?.toString().trim() ?? '';
            if (nameMap.containsKey(editorId)) {
              s['last_edited_by'] = nameMap[editorId];
            }
          }
        } catch (e) {
          LogUtil.debugPrint('[SupabaseService/fetchClientSubmissionHistoryByUser] Error resolving worker name: $e');
        }
      }

      return submissions;
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/fetchClientSubmissionHistoryByUser] Error: $e');
      return [];
    }
  }

  // Helper: detect UUID strings.
  bool _looksLikeUuid(String s) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(s);
  }

  // Load PII from saved field values.
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

      final keys = await HybridCryptoService.fetchUserFieldKeys(userId);

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
        if (version == 2) {
          final iv = row['iv'] as String? ?? '';
          if (iv.trim().isEmpty) {
            LogUtil.debugPrint('[SupabaseService/loadPiiFromFieldValues] Warning: missing iv for field_id=$fid');
            continue;
          }

          resolvedValue = await HybridCryptoService.decryptField(
            fval,
            iv,
            keys,
          );

          if (resolvedValue.isEmpty) {
            LogUtil.debugPrint('[SupabaseService/loadPiiFromFieldValues] Warning: decryption failed for field_id=$fid');
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
      LogUtil.debugPrint('[SupabaseService/loadPiiFromFieldValues] Error: $e');
      return {};
    }
  }

  /// Send the selected fields to the matching web session.
  /// Returns 'ok', 'expired', or 'error'.
  Future<String> sendDataToWebSession(
    String sessionId,
    Map<String, dynamic> data, {
    String? userId,
  }) async {
    try {
      String publicKey = '';
      try {
        publicKey = await HybridCryptoService.fetchAndCacheRsaPublicKey(
          forceRefresh: true,
        );
      } catch (e) {
        LogUtil.debugPrint('[SupabaseService/sendDataToWebSession] Warning: RSA public key fetch failed: $e');
      }

      if (publicKey.trim().isEmpty) {
        LogUtil.debugPrint('[SupabaseService/sendDataToWebSession] Action: No RSA key, falling back to unencrypted');
        return 'error';
      }

      final envelope = await HybridCryptoService.encryptForTransmission(
        data,
        publicKey,
      );

      // Check expiry before writing — avoids a wasted crypto round-trip.
      final sessionRow = await _supabase
          .from('form_submission')
          .select('expires_at, status')
          .eq('id', sessionId)
          .maybeSingle();

      if (sessionRow != null) {
        final expiresRaw = sessionRow['expires_at'];
        if (expiresRaw != null) {
          final expiresAt = DateTime.tryParse(expiresRaw.toString())?.toLocal();
          if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
            LogUtil.debugPrint('[SupabaseService/sendDataToWebSession] Session expired: $sessionId');
            return 'expired';
          }
        }
      }

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
        LogUtil.debugPrint('[SupabaseService/sendDataToWebSession] Action: Status filter returned null, retrying without filter');
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

        if (retryResponse == null) return 'error';
      }

      return 'ok';
    } catch (e) {
      LogUtil.debugPrint('[SupabaseService/sendDataToWebSession] Error for session $sessionId: $e');
      return 'error';
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
    if (t == 'h' ||
        t == 'sep' ||
        t.contains('separated') ||
        t.contains('hiwalay')) {
      return 'separated';
    }
    if (t == 'li' || t.contains('live_in') || t.contains('livein')) {
      return 'live_in';
    }
    if (t == 'c' || t.contains('minor')) {
      return 'minor';
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
      case 'live_in':
        return 'Live-in';
      case 'minor':
        return 'Minor';
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
