import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for staff to review, approve, or deny client submissions.
///
/// This writes review decisions to `client_submissions` (review_status,
/// reviewed_by, reviewed_at, review_notes). Notifications to the citizen
/// are handled automatically by the DB trigger `trg_client_submissions_review_notify`.
class SubmissionReviewService {
  final SupabaseClient _supabase;

  SubmissionReviewService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Approve a pending submission.
  Future<void> approve({
    required dynamic submissionId,
    required String staffId,
    String? notes,
  }) async {
    await _updateReviewStatus(
      submissionId: submissionId,
      status: 'approved',
      staffId: staffId,
      notes: notes,
    );
  }

  /// Deny a pending submission with a reason.
  Future<void> deny({
    required dynamic submissionId,
    required String staffId,
    required String reason,
  }) async {
    await _updateReviewStatus(
      submissionId: submissionId,
      status: 'denied',
      staffId: staffId,
      notes: reason,
    );
  }

  /// Revert an approved/denied submission back to pending.
  Future<void> revertToPending({
    required dynamic submissionId,
    required String staffId,
  }) async {
    await _updateReviewStatus(
      submissionId: submissionId,
      status: 'pending',
      staffId: staffId,
      notes: null,
    );
  }

  Future<void> _updateReviewStatus({
    required dynamic submissionId,
    required String status,
    required String staffId,
    String? notes,
  }) async {
    try {
      await _supabase.from('client_submissions').update({
        'review_status': status,
        'reviewed_by': staffId,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        if (notes != null) 'review_notes': notes,
      }).eq('id', submissionId);
    } catch (e) {
      debugPrint('[SubmissionReviewService/_updateReviewStatus] Error: $e');
      rethrow;
    }
  }

  /// Fetch the current review status for a single submission.
  Future<Map<String, dynamic>?> fetchReviewStatus(dynamic submissionId) async {
    try {
      final row = await _supabase
          .from('client_submissions')
          .select('id, review_status, reviewed_by, reviewed_at, review_notes')
          .eq('id', submissionId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('[SubmissionReviewService/fetchReviewStatus] Error: $e');
      return null;
    }
  }
}