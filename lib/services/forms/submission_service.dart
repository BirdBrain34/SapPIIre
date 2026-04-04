import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';

class SubmissionService {
  SubmissionService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Stream<List<Map<String, dynamic>>> streamSession(String sessionId) {
    return _supabase
        .from('form_submission')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId);
  }

  Future<void> updateSessionStatus(String sessionId, String status) async {
    await _supabase
        .from('form_submission')
        .update({'status': status})
        .eq('id', sessionId);
  }

  Future<Map<String, dynamic>> createSession(String formType) async {
    return await _supabase
        .from('form_submission')
        .insert({'status': 'active', 'form_type': formType, 'form_data': {}})
        .select()
        .single();
  }

  Future<Map<String, dynamic>?> fetchSessionSnapshot(String sessionId) async {
    final row = await _supabase
        .from('form_submission')
        .select('id, status, form_data')
        .eq('id', sessionId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<String?> fetchSessionUserId(String sessionId) async {
    final session = await _supabase
        .from('form_submission')
        .select('user_id')
        .eq('id', sessionId)
        .maybeSingle();
    return session?['user_id']?.toString();
  }

  Future<Map<String, dynamic>> upsertClientSubmission({
    required String sessionId,
    required String templateId,
    required String? formCode,
    required String formType,
    required Map<String, dynamic> data,
    required String createdBy,
  }) async {
    return await _supabase
        .from('client_submissions')
        .upsert({
          'session_id': sessionId,
          'template_id': templateId,
          'form_code': formCode,
          'form_type': formType,
          'data': data,
          'created_by': createdBy,
        }, onConflict: 'session_id')
        .select('id, intake_reference')
        .single();
  }

  Future<List<Map<String, dynamic>>> fetchRecentClientSubmissions({
    int limit = 100,
  }) async {
    final response = await _supabase
        .from('client_submissions')
        .select('*')
        .order('created_at', ascending: false)
        .range(0, limit - 1);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, String>> fetchSessionUserMap(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return {};
    final sessions = await _supabase
        .from('form_submission')
        .select('id, user_id')
        .inFilter('id', sessionIds);

    final sessionToUserId = <String, String>{};
    for (final row in sessions) {
      final uid = row['user_id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        sessionToUserId[row['id'].toString()] = uid;
      }
    }
    return sessionToUserId;
  }

  Future<Map<String, Map<String, String>>> fetchCanonicalNamesByUserIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    try {
      return await _fetchCanonicalNamesFromFieldValues(userIds);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('fetchCanonicalNamesByUserIds error: $e');
      }
      return {};
    }
  }

  Future<Map<String, String>?> fetchCanonicalNameByUserId(String userId) async {
    final names = await fetchCanonicalNamesByUserIds([userId]);
    return names[userId];
  }

  Future<Map<String, Map<String, String>>> _fetchCanonicalNamesFromFieldValues(
    List<String> userIds,
  ) async {
    final desiredCanonicalToBucket = <String, String>{
      'first_name': 'first',
      'middle_name': 'middle',
      'last_name': 'last',
    };

    final fieldRows = await _supabase
        .from('form_fields')
        .select('field_id, canonical_field_key')
        .inFilter(
          'canonical_field_key',
          desiredCanonicalToBucket.keys.toList(),
        );

    final fieldIdToBucket = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(fieldRows)) {
      final fieldId = row['field_id']?.toString();
      final canonical = row['canonical_field_key']?.toString();
      if (fieldId == null || canonical == null) continue;

      final bucket = desiredCanonicalToBucket[canonical.trim().toLowerCase()];
      if (bucket == null) continue;
      fieldIdToBucket[fieldId] = bucket;
    }

    if (fieldIdToBucket.isEmpty) {
      return {};
    }

    final valueRows = await _supabase
        .from('user_field_values')
        .select(
          'user_id, field_id, field_value, iv, encryption_version, updated_at',
        )
        .inFilter('user_id', userIds)
        .inFilter('field_id', fieldIdToBucket.keys.toList())
        .order('updated_at', ascending: false);

    final namesByUser = <String, Map<String, String>>{};
    final keyCache = <String, dynamic>{};

    for (final row in List<Map<String, dynamic>>.from(valueRows)) {
      final userId = row['user_id']?.toString();
      final fieldId = row['field_id']?.toString();
      final rawValue = row['field_value']?.toString() ?? '';

      if (userId == null || fieldId == null || rawValue.trim().isEmpty) {
        continue;
      }
      if (rawValue == '__CLEARED__') {
        continue;
      }

      final bucket = fieldIdToBucket[fieldId];
      if (bucket == null) {
        continue;
      }

      final target = namesByUser.putIfAbsent(
        userId,
        () => {'last': '', 'first': '', 'middle': ''},
      );

      if ((target[bucket] ?? '').trim().isNotEmpty) {
        continue;
      }

      final rawVersion = row['encryption_version'];
      final version = rawVersion is int
          ? rawVersion
          : int.tryParse(rawVersion?.toString() ?? '') ?? 0;

      String resolved = rawValue;
      if (version == 1) {
        final iv = row['iv']?.toString() ?? '';
        if (iv.isEmpty) {
          continue;
        }

        final key = keyCache.putIfAbsent(
          userId,
          () => HybridCryptoService.deriveUserAesKey(userId),
        );

        resolved = await HybridCryptoService.decryptField(rawValue, iv, key);
      }

      final clean = resolved.trim();
      if (clean.isEmpty || clean == '__CLEARED__') {
        continue;
      }

      target[bucket] = clean;
    }

    return namesByUser;
  }

  Future<void> updateClientSubmission({
    required dynamic submissionId,
    required Map<String, dynamic> data,
    required String? intakeReference,
    required String editorId,
  }) async {
    await _supabase
        .from('client_submissions')
        .update({
          'data': data,
          'intake_reference': intakeReference,
          'last_edited_by': editorId,
          'last_edited_at': DateTime.now().toIso8601String(),
        })
        .eq('id', submissionId);
  }

  Future<void> deleteClientSubmission(dynamic submissionId) async {
    await _supabase.from('client_submissions').delete().eq('id', submissionId);
  }

  Future<void> deleteClientSubmissions(List<dynamic> submissionIds) async {
    if (submissionIds.isEmpty) return;
    await _supabase
        .from('client_submissions')
        .delete()
        .inFilter('id', submissionIds);
  }

  Future<void> signOut() {
    return _supabase.auth.signOut();
  }
}
