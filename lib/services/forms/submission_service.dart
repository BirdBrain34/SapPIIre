import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<Map<String, String>> fetchSessionUserMap(List<String> sessionIds) async {
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

    final rpcResult = await _supabase.rpc(
      'get_user_names_by_canonical',
      params: {'p_user_ids': userIds},
    ) as List<dynamic>;

    final userIdToName = <String, Map<String, String>>{};
    for (final row in rpcResult.cast<Map<String, dynamic>>()) {
      final uid = row['user_id']?.toString();
      if (uid == null || uid.isEmpty) continue;
      userIdToName[uid] = {
        'last': (row['last_name'] as String?)?.trim() ?? '',
        'first': (row['first_name'] as String?)?.trim() ?? '',
        'middle': (row['middle_name'] as String?)?.trim() ?? '',
      };
    }
    return userIdToName;
  }

  Future<Map<String, String>?> fetchCanonicalNameByUserId(String userId) async {
    final names = await fetchCanonicalNamesByUserIds([userId]);
    return names[userId];
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
    await _supabase
        .from('client_submissions')
        .delete()
        .eq('id', submissionId);
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