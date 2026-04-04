import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kAuditLogin = 'login';
const kAuditLoginFailed = 'login_failed';
const kAuditLogout = 'logout';
const kAuditPasswordChanged = 'password_changed';

const kAuditSessionStarted = 'session_started';
const kAuditSessionCompleted = 'session_completed';
const kAuditSessionClosed = 'session_closed';

const kAuditSubmissionCreated = 'submission_created';
const kAuditSubmissionEdited = 'submission_edited';
const kAuditSubmissionDeleted = 'submission_deleted';

const kAuditStaffCreated = 'staff_created';
const kAuditStaffApproved = 'staff_approved';
const kAuditStaffRejected = 'staff_rejected';
const kAuditRoleChanged = 'role_changed';

const kAuditTemplateCreated = 'template_created';
const kAuditTemplatePublished = 'template_published';
const kAuditTemplatePushed = 'template_pushed_to_mobile';
const kAuditTemplateArchived = 'template_archived';
const kAuditTemplateDeleted = 'template_deleted';

const kCategoryAuth = 'auth';
const kCategorySession = 'session';
const kCategorySubmission = 'submission';
const kCategoryStaff = 'staff';
const kCategoryTemplate = 'template';

const kSeverityInfo = 'info';
const kSeverityWarning = 'warning';
const kSeverityCritical = 'critical';

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
        debugPrint('AuditLogService.log failed: $e');
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
        debugPrint('AuditLogService.fetchLogs failed: $e');
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

      final response = await query;
      return (response as List).length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AuditLogService.fetchCount failed: $e');
      }
      return 0;
    }
  }
}
