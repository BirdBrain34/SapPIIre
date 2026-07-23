import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kAuditLogin = 'login';
const kAuditLoginFailed = 'login_failed';
const kAuditLogout = 'logout';
const kAuditPasswordChanged = 'password_changed';

/// Emitted server-side by the `manage-user-account` Edge Function when a mobile
/// applicant self-deletes their account (Data Privacy Act erasure).
const kAuditUserAccountDeleted = 'user_account_deleted';

const kAuditSessionStarted = 'session_started';
const kAuditSessionCompleted = 'session_completed';
const kAuditSessionClosed = 'session_closed';

/// Emitted by the mobile client when a user completes the pre-transmission
/// "confirm it's you" OTP challenge (see QrTransmissionOtpController).
const kAuditQrTransmissionOtpVerified = 'qr_transmission_otp_verified';

/// Emitted when a user exhausts verification attempts on the pre-transmission
/// OTP challenge — a possible session-hijack or shared-device signal.
const kAuditQrTransmissionOtpFailed = 'qr_transmission_otp_failed';

const kAuditSubmissionCreated = 'submission_created';
const kAuditSubmissionEdited = 'submission_edited';
const kAuditSubmissionDeleted = 'submission_deleted';
const kAuditSubmissionDecrypted = 'submission_decrypted';
const kAuditSubmissionPreviewDecrypted = 'submission_preview_decrypted';
const kAuditApplicantNamesResolved = 'applicant_names_resolved';

/// Emitted by the `search-applicants` Edge Function. If the live `audit_logs`
/// table has a CHECK constraint that rejects this value, the function falls
/// back to [kAuditApplicantNamesResolved] with `details.purpose == 'search'`.
const kAuditApplicantSearch = 'applicant_search';

const kAuditStaffCreated = 'staff_created';
const kAuditStaffApproved = 'staff_approved';
const kAuditStaffRejected = 'staff_rejected';
const kAuditRoleChanged = 'role_changed';

const kAuditTemplateCreated = 'template_created';
const kAuditTemplatePublished = 'template_published';
const kAuditTemplatePushed = 'template_pushed_to_mobile';
const kAuditTemplateArchived = 'template_archived';
const kAuditTemplateDeleted = 'template_deleted';
const kAuditTemplateSubmittedForApproval = 'template_submitted_for_approval';
const kAuditTemplateApproved = 'template_approved';
const kAuditTemplateRejected = 'template_rejected';

const kAuditCanonicalKeyCreated = 'canonical_key_created';
const kAuditCanonicalKeyDeactivated = 'canonical_key_deactivated';

const kCategoryAuth = 'auth';
const kCategorySession = 'session';
const kCategorySubmission = 'submission';
const kCategoryStaff = 'staff';
const kCategoryTemplate = 'template';

const kSeverityInfo = 'info';
const kSeverityWarning = 'warning';
const kSeverityCritical = 'critical';

/// Records audit events and queries the audit log table.
class AuditLogService {
  static final AuditLogService _instance = AuditLogService._internal();
  factory AuditLogService() => _instance;
  AuditLogService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> log({
    required String actionType,
    required String category,
    String severity = kSeverityInfo,
    String? actorId,
    String? actorName,
    String? actorRole,
    String? targetType,
    String? targetId,
    String? targetLabel,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _supabase.from('audit_logs').insert({
        'actor_id': actorId,
        'actor_name': actorName,
        'actor_role': actorRole,
        'action_type': actionType,
        'category': category,
        'severity': severity,
        'target_type': targetType,
        'target_id': targetId,
        'target_label': targetLabel,
        'details': details ?? {},
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuditLogService/log] Error: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchLogs({
    int limit = 50,
    int offset = 0,
    String? categoryFilter,
    String? actionFilter,
    String? severityFilter,
    String? actorFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      var query = _supabase.from('audit_logs').select('*');

      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        query = query.eq('category', categoryFilter);
      }
      if (actionFilter != null && actionFilter.isNotEmpty) {
        query = query.eq('action_type', actionFilter);
      }
      if (severityFilter != null && severityFilter.isNotEmpty) {
        query = query.eq('severity', severityFilter);
      }
      if (actorFilter != null && actorFilter.isNotEmpty) {
        query = query.ilike('actor_name', '%$actorFilter%');
      }
      if (dateFrom != null) {
        query = query.gte('created_at', dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        final end = DateTime(
          dateTo.year,
          dateTo.month,
          dateTo.day,
          23,
          59,
          59,
        ).toUtc();
        query = query.lte('created_at', end.toIso8601String());
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuditLogService/fetchLogs] Error: $e');
      }
      return [];
    }
  }

  Future<int> fetchCount({
    String? categoryFilter,
    String? actionFilter,
    String? severityFilter,
    String? actorFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      var query = _supabase.from('audit_logs').select('id');

      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        query = query.eq('category', categoryFilter);
      }
      if (actionFilter != null && actionFilter.isNotEmpty) {
        query = query.eq('action_type', actionFilter);
      }
      if (severityFilter != null && severityFilter.isNotEmpty) {
        query = query.eq('severity', severityFilter);
      }
      if (actorFilter != null && actorFilter.isNotEmpty) {
        query = query.ilike('actor_name', '%$actorFilter%');
      }
      if (dateFrom != null) {
        query = query.gte('created_at', dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        final end = DateTime(
          dateTo.year,
          dateTo.month,
          dateTo.day,
          23,
          59,
          59,
        ).toUtc();
        query = query.lte('created_at', end.toIso8601String());
      }

      final response = await query.count(CountOption.exact);
      return response.count;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuditLogService/fetchCount] Error: $e');
      }
      return 0;
    }
  }
}
