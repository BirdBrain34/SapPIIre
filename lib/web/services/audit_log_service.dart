import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Auth
const kAuditLogin = 'login';
const kAuditLoginFailed = 'login_failed';
const kAuditLogout = 'logout';
const kAuditPasswordChanged = 'password_changed';

// Session / QR
const kAuditSessionStarted = 'session_started';
const kAuditSessionCompleted = 'session_completed';
const kAuditSessionClosed = 'session_closed';

// Submissions
const kAuditSubmissionCreated = 'submission_created';
const kAuditSubmissionEdited = 'submission_edited';
const kAuditSubmissionDeleted = 'submission_deleted';

// Staff management
const kAuditStaffCreated = 'staff_created';
const kAuditStaffApproved = 'staff_approved';
const kAuditStaffRejected = 'staff_rejected';
const kAuditRoleChanged = 'role_changed';

// Templates
const kAuditTemplateCreated = 'template_created';
const kAuditTemplatePublished = 'template_published';
const kAuditTemplatePushed = 'template_pushed_to_mobile';
const kAuditTemplateArchived = 'template_archived';
const kAuditTemplateDeleted = 'template_deleted';

// Categories
const kCategoryAuth = 'auth';
const kCategorySession = 'session';
const kCategorySubmission = 'submission';
const kCategoryStaff = 'staff';
const kCategoryTemplate = 'template';

// Severity
const kSeverityInfo = 'info';
const kSeverityWarning = 'warning';
const kSeverityCritical = 'critical';

class AuditLogService {
  static final AuditLogService _instance = AuditLogService._internal();
  factory AuditLogService() => _instance;
  AuditLogService._internal();

  final _supabase = Supabase.instance.client;

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
      debugPrint('AuditLogService: failed to write log: $e');
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
      var q = _supabase.from('audit_logs').select('*');

      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        q = q.eq('category', categoryFilter);
      }
      if (actionFilter != null && actionFilter.isNotEmpty) {
        q = q.eq('action_type', actionFilter);
      }
      if (severityFilter != null && severityFilter.isNotEmpty) {
        q = q.eq('severity', severityFilter);
      }
      if (actorFilter != null && actorFilter.isNotEmpty) {
        q = q.ilike('actor_name', '%$actorFilter%');
      }
      if (dateFrom != null) {
        q = q.gte('created_at', dateFrom.toIso8601String());
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
        q = q.lte('created_at', end.toIso8601String());
      }

      final response = await q
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('AuditLogService.fetchLogs error: $e');
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
      var q = _supabase.from('audit_logs').select('id');

      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        q = q.eq('category', categoryFilter);
      }
      if (actionFilter != null && actionFilter.isNotEmpty) {
        q = q.eq('action_type', actionFilter);
      }
      if (severityFilter != null && severityFilter.isNotEmpty) {
        q = q.eq('severity', severityFilter);
      }
      if (actorFilter != null && actorFilter.isNotEmpty) {
        q = q.ilike('actor_name', '%$actorFilter%');
      }
      if (dateFrom != null) {
        q = q.gte('created_at', dateFrom.toIso8601String());
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
        q = q.lte('created_at', end.toIso8601String());
      }

      final response = await q;
      return (response as List).length;
    } catch (e) {
      debugPrint('AuditLogService.fetchCount error: $e');
      return 0;
    }
  }
}
