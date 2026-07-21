import 'package:flutter/foundation.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/form_builder_service.dart';

class ApprovalsController extends ChangeNotifier {
  final FormBuilderService _service;

  /// Actor context for the audit trail. Approving or rejecting a form is a
  /// privileged action, so every transition has to name who performed it.
  final String cswdId;
  final String displayName;
  final String role;

  ApprovalsController({
    required this.cswdId,
    this.displayName = '',
    this.role = '',
    FormBuilderService? service,
  }) : _service = service ?? FormBuilderService();

  List<Map<String, dynamic>> _pendingTemplates = [];
  bool _isLoading = false;
  bool _isApproving = false;
  bool _isRejecting = false;

  List<Map<String, dynamic>> get pendingTemplates => _pendingTemplates;
  bool get isLoading => _isLoading;
  bool get isApproving => _isApproving;
  bool get isRejecting => _isRejecting;

  /// Form name for [templateId], read before the row is dropped from the
  /// pending list so the audit entry can carry a human-readable target.
  String? _templateLabel(String templateId) {
    for (final t in _pendingTemplates) {
      if (t['template_id'] == templateId) {
        return t['form_name'] as String?;
      }
    }
    return null;
  }

  Future<void> loadPendingApprovals() async {
    _isLoading = true;
    notifyListeners();

    try {
      _pendingTemplates = await _service.fetchPendingApprovalTemplates();
    } catch (e) {
      debugPrint('[ApprovalsController/loadPendingApprovals] Error: $e');
      _pendingTemplates = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> approveTemplate(String templateId) async {
    _isApproving = true;
    notifyListeners();

    try {
      final label = _templateLabel(templateId);
      final success = await _service.approveTemplate(templateId, cswdId);
      if (success) {
        _pendingTemplates.removeWhere(
          (t) => t['template_id'] == templateId,
        );

        await AuditLogService().log(
          actionType: kAuditTemplateApproved,
          category: kCategoryTemplate,
          severity: kSeverityInfo,
          actorId: cswdId,
          actorName: displayName,
          actorRole: role,
          targetType: 'form_template',
          targetId: templateId,
          targetLabel: label,
        );
      }
      return success;
    } catch (e) {
      debugPrint('[ApprovalsController/approveTemplate] Error: $e');
      return false;
    } finally {
      _isApproving = false;
      notifyListeners();
    }
  }

  Future<bool> rejectTemplate(
    String templateId,
    String reason,
  ) async {
    if (reason.trim().isEmpty) return false;

    _isRejecting = true;
    notifyListeners();

    try {
      final label = _templateLabel(templateId);
      final success = await _service.rejectTemplate(templateId, reason.trim());
      if (success) {
        _pendingTemplates.removeWhere(
          (t) => t['template_id'] == templateId,
        );

        // Denials are warning-level, matching login_failed — an approval that
        // was refused is the case a reviewer needs to find later.
        await AuditLogService().log(
          actionType: kAuditTemplateRejected,
          category: kCategoryTemplate,
          severity: kSeverityWarning,
          actorId: cswdId,
          actorName: displayName,
          actorRole: role,
          targetType: 'form_template',
          targetId: templateId,
          targetLabel: label,
          details: {'reason': reason.trim()},
        );
      }
      return success;
    } catch (e) {
      debugPrint('[ApprovalsController/rejectTemplate] Error: $e');
      return false;
    } finally {
      _isRejecting = false;
      notifyListeners();
    }
  }
}
