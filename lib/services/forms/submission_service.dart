// ignore_for_file: use_null_aware_elements
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';

/// Thrown when a submission carries answers identical to one the same applicant
/// already has on file.
///
/// This is a *warning*, not a rejection. The caller is expected to ask the staff
/// member whether to continue, and retry with `acknowledgeDuplicate: true` if
/// they say yes.
///
/// Modelled as an exception rather than a sentinel return value so the caller's
/// success path is skipped by construction — nothing was written, so the audit
/// log, the "Entry saved" snackbar, and the session reset must not run.
///
/// See docs/15_Submission_Deduplication.md.
class DuplicateSubmissionException implements Exception {
  DuplicateSubmissionException({
    this.existingId,
    this.intakeReference,
    this.createdAt,
  });

  /// `client_submissions.id` of the matching submission already on file.
  final Object? existingId;

  /// Intake reference of that submission, so the message can name it.
  final String? intakeReference;

  /// ISO-8601 timestamp of that submission. The most recent match wins when
  /// several past submissions carry the same answers, so this is the date the
  /// confirm dialog shows the staff member.
  final String? createdAt;

  @override
  String toString() =>
      'DuplicateSubmissionException(existingId: $existingId, '
      'intakeReference: $intakeReference, createdAt: $createdAt)';
}

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
  
  /// Fetches only the encrypted envelope columns for a staging session.
  /// Used to check if a session has encrypted payload before triggering decryption.
  Future<Map<String, dynamic>?> fetchEncryptedEnvelope(String sessionId) async {
    final row = await _supabase
        .from('form_submission')
        .select('id, status, transmission_version, encrypted_payload, payload_iv, encrypted_aes_key')
        .eq('id', sessionId)
        .eq('transmission_version', 1)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
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
        .insert({'status': 'active', 'form_type': formType})
        .select()
        .single();
  }

  /// Superseded by `ApplicantSearchService.search`, which groups submissions
  /// into distinct applicants server-side and pages properly. This returns
  /// raw, ungrouped submission rows and cannot search encrypted PII.
  @Deprecated('Use ApplicantSearchService.search() for applicant browsing.')
  Future<List<Map<String, dynamic>>> fetchApplicantIndex({
    int limit = 100,
    int offset = 0,
    String? formType,
  }) async {
    final response = await _supabase.rpc(
      'get_applicant_index',
      params: {
        'p_limit': limit,
        'p_offset': offset,
        if (formType != null) 'p_form_type': formType,
      },
    );

    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<Map<String, dynamic>?> fetchSessionSnapshot(String sessionId) async {
    final row = await _supabase
        .from('form_submission')
        .select('id, status, transmission_version, expires_at')
        .eq('id', sessionId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<DateTime?> fetchSessionExpiresAt(String sessionId) async {
    final row = await _supabase
        .from('form_submission')
        .select('expires_at')
        .eq('id', sessionId)
        .maybeSingle();
    final raw = row?['expires_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
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

  Future<Map<String, dynamic>> upsertClientSubmissionSecure({
    required String sessionId,
    required String templateId,
    required String? formCode,
    required String formType,
    required Map<String, dynamic> data,
    required String createdBy,
    String? intakeReference,
    bool acknowledgeDuplicate = false,
    int? templateVersion,
  }) async {
    const supabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

    final url = Uri.parse(
      '$supabaseUrl/functions/v1/encrypt-and-save-submission',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $anonKey',
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sessionId': sessionId,
        'templateId': templateId,
        'formCode': formCode,
        'formType': formType,
        'data': data,
        'intakeReference': intakeReference,
        'createdBy': createdBy,
        'acknowledgeDuplicate': acknowledgeDuplicate,
        if (templateVersion != null) 'templateVersion': templateVersion,
      }),
    );

    // The Edge Function flags a submission identical to one this applicant
    // already has on file, without writing anything. Translate that into a
    // typed exception before the generic non-200 throw below, so the UI can
    // ask the staff member whether to save it anyway rather than surfacing a
    // raw error body.
    if (response.statusCode == 409) {
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }
      if (body?['duplicate'] == true) {
        final existing = body?['existing'];
        final existingMap = existing is Map ? existing : const {};
        throw DuplicateSubmissionException(
          existingId: existingMap['id'],
          intakeReference: existingMap['intake_reference']?.toString(),
          createdAt: existingMap['created_at']?.toString(),
        );
      }
    }

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;

    // Stamp the structural version this record was filled against, so a later
    // template edit can be detected when the record is reopened. Written from
    // here rather than inside the Edge Function because the deployed function
    // carries duplicate-detection logic that is not in this repository — see
    // docs/16_Form_Template_Versioning.md. A failure here leaves the column
    // NULL, which reads as version 1.
    if (templateVersion != null && result['id'] != null) {
      try {
        await _supabase
            .from('client_submissions')
            .update({'template_version': templateVersion})
            .eq('id', result['id']);
      } catch (e) {
        debugPrint(
          '[SubmissionService/upsertClientSubmissionSecure] '
          'Version stamp failed: $e',
        );
      }
    }

    return result;
  }

  @Deprecated('Use ApplicantSearchService.search() for list rendering.')
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

  Future<Map<String, dynamic>?> fetchClientSubmissionById(
    dynamic submissionId,
  ) async {
    final row = await _supabase
        .from('client_submissions')
        .select('*')
        .eq('id', submissionId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
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

  /// Resolves applicant names for staff-facing screens using the
  /// resolve-applicant-names Edge Function (server-side decryption).
  Future<Map<String, Map<String, String>>> resolveNamesViaEdgeFunction({
    required List<String> userIds,
    required String staffId,
  }) async {
    if (userIds.isEmpty) {
      return {};
    }

    const supabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

    final url = Uri.parse('$supabaseUrl/functions/v1/resolve-applicant-names');

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $anonKey',
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userIds': userIds,
          'staffId': staffId,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[SubmissionService/resolveNamesViaEdgeFunction] Error: ${response.body}',
        );
        return {};
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final namesByUser = <String, Map<String, String>>{};
      for (final entry in result.entries) {
        final userNames = entry.value as Map<String, dynamic>;
        namesByUser[entry.key] = {
          'last': (userNames['last'] as String?) ?? '',
          'first': (userNames['first'] as String?) ?? '',
          'middle': (userNames['middle'] as String?) ?? '',
        };
      }
      return namesByUser;
    } catch (e) {
      debugPrint(
        '[SubmissionService/resolveNamesViaEdgeFunction] Error: $e',
      );
      return {};
    }
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

  Future<Map<String, dynamic>?> decryptSubmissionData({
    required dynamic submissionId,
    required String staffId,
    bool logAccess = true,
  }) async {
    const supabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

    final url = Uri.parse('$supabaseUrl/functions/v1/decrypt-submission-data');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $anonKey',
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'submissionId': submissionId,
        'staffId': staffId,
        'logAccess': logAccess,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint(
        '[SubmissionService/decryptSubmissionData] Error response: ${response.body}',
      );
      return null;
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    return result['data'] as Map<String, dynamic>?;
  }

  /// Fetches and decrypts a form_submission staging record for staff review.
  ///
  /// Calls the serve-submission-for-review Edge Function which uses the
  /// server's RSA private key to unwrap the AES key and decrypt the payload.
  /// The plaintext is returned ephemerally in the HTTP response — it is never
  /// written back to the database by this call.
  ///
  /// Returns null if the session is not found, not encrypted, or the staff
  /// member lacks permission. Throws on network errors.
  Future<Map<String, dynamic>?> fetchDecryptedStagingSubmission({
    required String sessionId,
    required String staffId,
  }) async {
    const supabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

    final url = Uri.parse(
      '$supabaseUrl/functions/v1/serve-submission-for-review',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $anonKey',
        'apikey': anonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sessionId': sessionId,
        'staffId': staffId,
        'hashAlgo': 'SHA-1', // must match Flutter encrypt package RSA-OAEP default
      }),
    );

    if (response.statusCode == 410) {
      throw Exception('session_expired');
    }
    if (response.statusCode != 200) {
      debugPrint(
        '[SubmissionService/fetchDecryptedStagingSubmission] Error '
        'status=${response.statusCode} body=${response.body}',
      );
      return null;
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (result['success'] != true) {
      debugPrint(
        '[SubmissionService/fetchDecryptedStagingSubmission] '
        'reason=${result['reason']}',
      );
      return null;
    }

    return result['data'] as Map<String, dynamic>?;
  }

  Future<Map<int, Map<String, dynamic>>> batchDecryptSubmissions(
    List<int> submissionIds,
    String staffId, {
    bool logAccess = false,
  }) async {
    if (submissionIds.isEmpty) {
      return {};
    }

    const supabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

    final uniqueSubmissionIds = submissionIds.toSet().toList();
    final allResults = <int, Map<String, dynamic>>{};

    // Process in batches of 20 (function limit)
    for (var i = 0; i < uniqueSubmissionIds.length; i += 20) {
      final batch = uniqueSubmissionIds.skip(i).take(20).toList();

      try {
        final url = Uri.parse('$supabaseUrl/functions/v1/decrypt-submission-batch');
        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $anonKey',
            'apikey': anonKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'submissionIds': batch,
            'staffId': staffId,
          }),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          final results = result['results'] as List;

          for (final item in results) {
            final id = item['id'] as int;
            final data = item['data'];
            final decrypted = item['decrypted'] as bool;

            if (decrypted && data is Map<String, dynamic>) {
              allResults[id] = data;
            }
          }
        } else {
          debugPrint(
            '[SubmissionService/batchDecryptSubmissions] Batch error: ${response.body}',
          );
        }
      } catch (e) {
        debugPrint(
          '[SubmissionService/batchDecryptSubmissions] Error processing batch: $e',
        );
      }
    }

    return allResults;
  }

  /// Stream form_submission rows for a given user (used by citizen app).
  Stream<List<Map<String, dynamic>>> streamUserSubmissions(String userId) {
    return _supabase
        .from('form_submission')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Fetch review status for a submission (citizen-facing).
  Future<Map<String, dynamic>?> fetchReviewStatus(dynamic submissionId) async {
    try {
      final row = await _supabase
          .from('client_submissions')
          .select('id, review_status, reviewed_by, reviewed_at, review_notes')
          .eq('id', submissionId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('[SubmissionService/fetchReviewStatus] Error: $e');
      return null;
    }
  }

  /// Fetch all reviewable submissions for a set of session IDs.
  Future<List<Map<String, dynamic>>> fetchSubmissionsBySessions(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return [];
    try {
      final rows = await _supabase
          .from('client_submissions')
          .select('id, session_id, review_status, reviewed_by, reviewed_at, review_notes, intake_reference')
          .inFilter('session_id', sessionIds);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SubmissionService/fetchSubmissionsBySessions] Error: $e');
      return [];
    }
  }

  Future<void> signOut() {
    HybridCryptoService.clearFieldKeyCache();
    return _supabase.auth.signOut();
  }
}
