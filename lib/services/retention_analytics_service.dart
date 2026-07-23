import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/config/retention_config.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';

/// One stale (or archival-flagged) finalized record, described purely by its
/// non-sensitive metadata.
///
/// This model deliberately carries no decrypted form content — only the
/// identifying fields an admin needs to decide whether a record is worth
/// keeping: its reference number, form type, when it last changed, how old
/// that makes it, and any archival flag already set. The encrypted `data`
/// column is never read here.
@immutable
class StaleRecord {
  const StaleRecord({
    required this.id,
    required this.intakeReference,
    required this.formType,
    required this.lastUpdated,
    required this.ageDays,
    required this.tier,
    required this.usesEditTimestamp,
    required this.retentionStatus,
    this.flaggedAt,
    this.flaggedBy,
  });

  /// Primary key of the `client_submissions` row, kept in its original type so
  /// it can be passed straight back into an `.eq('id', ...)` filter.
  final Object id;

  final String intakeReference;
  final String formType;

  /// Effective last-updated instant: `last_edited_at` when the record has been
  /// edited, otherwise `created_at`.
  final DateTime lastUpdated;

  /// Whole days between [lastUpdated] and the classification moment.
  final int ageDays;

  final RetentionTier tier;

  /// True when [lastUpdated] came from `last_edited_at` (the record was edited),
  /// false when it fell back to `created_at`. Lets the UI say "last edited" vs
  /// "created" honestly.
  final bool usesEditTimestamp;

  /// `retention_status` as stored: null (not reviewed) or 'flagged_for_archival'.
  final String? retentionStatus;
  final DateTime? flaggedAt;
  final String? flaggedBy;

  bool get isFlaggedForArchival => retentionStatus == 'flagged_for_archival';
}

/// Read/act layer for the admin data-retention view.
///
/// Staleness is derived at read time from `COALESCE(last_edited_at, created_at)`
/// against the thresholds in [RetentionConfig]; nothing about age is persisted.
/// The only thing written back is an admin's advisory archival flag.
///
/// Like [DashboardAnalyticsService], this reads `client_submissions` directly
/// with the anon key — but only the plaintext metadata columns
/// (`intake_reference`, `form_type`, timestamps, the retention flag). It never
/// touches `data`/`data_iv`, so there is no decryption path and no PII exposure.
class RetentionAnalyticsService {
  RetentionAnalyticsService({AuditLogService? auditLogService})
    : _audit = auditLogService ?? AuditLogService();

  final SupabaseClient _supabase = Supabase.instance.client;
  final AuditLogService _audit;

  static const String _flagArchival = 'flagged_for_archival';

  /// All records old enough to be archival candidates, newest-stale first.
  ///
  /// [formType] scopes the query server-side ('All' = no filter). [tier], when
  /// given, keeps only that single staleness band. Fresh records (younger than
  /// the smallest configured threshold) are never returned.
  Future<List<StaleRecord>> fetchStaleRecords({
    String formType = 'All',
    RetentionTier? tier,
    DateTime? now,
  }) async {
    try {
      dynamic query = _supabase
          .from('client_submissions')
          .select(
            'id, intake_reference, form_type, created_at, last_edited_at, '
            'retention_status, retention_flagged_at, retention_flagged_by',
          );

      if (formType.trim().isNotEmpty && formType != 'All') {
        query = query.eq('form_type', formType);
      }

      final rows = List<Map<String, dynamic>>.from(await query);
      final reference = now ?? DateTime.now();

      final records = <StaleRecord>[];
      for (final row in rows) {
        final record = _toStaleRecord(row, reference);
        if (record == null) continue;
        if (!RetentionConfig.isStale(record.tier)) continue;
        if (tier != null && record.tier != tier) continue;
        records.add(record);
      }

      records.sort((a, b) => b.ageDays.compareTo(a.ageDays));
      return records;
    } catch (e) {
      debugPrint('[RetentionAnalyticsService/fetchStaleRecords] Error: $e');
      return [];
    }
  }

  /// Count of stale records per tier for the dashboard summary. Keys always
  /// include every stale tier (zero-filled), so the summary renders a stable
  /// set of cards even when a band is empty.
  Future<Map<RetentionTier, int>> fetchStaleSummary({
    String formType = 'All',
    DateTime? now,
  }) async {
    final counts = <RetentionTier, int>{
      for (final t in RetentionConfig.tiersAscending) t.tier: 0,
    };

    final records = await fetchStaleRecords(formType: formType, now: now);
    for (final record in records) {
      counts[record.tier] = (counts[record.tier] ?? 0) + 1;
    }
    return counts;
  }

  /// Flags a single record for archival review. Advisory only — the record is
  /// untouched apart from the marker. Returns true on success.
  Future<bool> flagForArchival({
    required Object submissionId,
    required String staffId,
    String? staffName,
    String? staffRole,
    String? intakeReference,
  }) async {
    return _setFlag(
      submissionId: submissionId,
      status: _flagArchival,
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
      intakeReference: intakeReference,
      auditAction: kAuditSubmissionFlaggedForArchival,
    );
  }

  /// Clears an existing archival flag (admin decided to keep the record).
  Future<bool> clearArchivalFlag({
    required Object submissionId,
    required String staffId,
    String? staffName,
    String? staffRole,
    String? intakeReference,
  }) async {
    return _setFlag(
      submissionId: submissionId,
      status: null,
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
      intakeReference: intakeReference,
      auditAction: kAuditSubmissionArchivalFlagCleared,
    );
  }

  Future<bool> _setFlag({
    required Object submissionId,
    required String? status,
    required String staffId,
    required String auditAction,
    String? staffName,
    String? staffRole,
    String? intakeReference,
  }) async {
    try {
      final flagging = status != null;
      await _supabase
          .from('client_submissions')
          .update({
            'retention_status': status,
            'retention_flagged_at': flagging
                ? DateTime.now().toUtc().toIso8601String()
                : null,
            'retention_flagged_by': flagging ? staffId : null,
          })
          .eq('id', submissionId);

      // Best-effort audit trail — never blocks the action.
      await _audit.log(
        actionType: auditAction,
        category: kCategorySubmission,
        severity: kSeverityInfo,
        actorId: staffId,
        actorName: staffName,
        actorRole: staffRole,
        targetType: 'client_submission',
        targetId: submissionId.toString(),
        targetLabel: intakeReference,
      );

      return true;
    } catch (e) {
      debugPrint('[RetentionAnalyticsService/_setFlag] Error: $e');
      return false;
    }
  }

  StaleRecord? _toStaleRecord(Map<String, dynamic> row, DateTime reference) {
    final id = row['id'];
    if (id == null) return null;

    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final editedAt = DateTime.tryParse(row['last_edited_at']?.toString() ?? '');
    final lastUpdated = editedAt ?? createdAt;
    if (lastUpdated == null) return null;

    final ageDays = reference.difference(lastUpdated).inDays;
    final tier = RetentionConfig.classifyDays(ageDays < 0 ? 0 : ageDays);

    final reference0 = row['intake_reference']?.toString().trim();
    final formType = row['form_type']?.toString().trim();

    return StaleRecord(
      id: id as Object,
      intakeReference: (reference0 == null || reference0.isEmpty)
          ? '—'
          : reference0,
      formType: (formType == null || formType.isEmpty) ? 'Unknown' : formType,
      lastUpdated: lastUpdated,
      ageDays: ageDays < 0 ? 0 : ageDays,
      tier: tier,
      usesEditTimestamp: editedAt != null,
      retentionStatus: row['retention_status']?.toString(),
      flaggedAt: DateTime.tryParse(row['retention_flagged_at']?.toString() ?? ''),
      flaggedBy: row['retention_flagged_by']?.toString(),
    );
  }
}
