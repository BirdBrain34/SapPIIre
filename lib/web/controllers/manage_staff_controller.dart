import 'package:flutter/foundation.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/auth/staff_admin_service.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';

/// Loads and mutates staff account state for the management screen.
class ManageStaffController extends ChangeNotifier {
  ManageStaffController({
    StaffAdminService? staffAdminService,
    WebAuthService? webAuthService,
    AuditLogService? auditLogService,
  }) : _staffAdminService = staffAdminService ?? StaffAdminService(),
       _webAuthService = webAuthService ?? WebAuthService(),
       _auditLogService = auditLogService ?? AuditLogService();

  final StaffAdminService _staffAdminService;
  final WebAuthService _webAuthService;
  final AuditLogService _auditLogService;

  List<Map<String, dynamic>> pendingAccounts = [];
  List<Map<String, dynamic>> activeAccounts = [];
  bool isLoading = true;

  Future<void> loadAccounts() async {
    isLoading = true;
    notifyListeners();

    try {
      final data = await _staffAdminService.fetchAccounts();
      pendingAccounts = List<Map<String, dynamic>>.from(data['pending'] ?? []);
      activeAccounts = List<Map<String, dynamic>>.from(data['active'] ?? []);
    } catch (e) {
      debugPrint('[ManageStaffController/loadAccounts] Error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> approveAccount({
    required String cswdId,
    required String requestedRole,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    await _staffAdminService.approveAccount(cswdId, requestedRole);

    await _auditLogService.log(
      actionType: kAuditStaffApproved,
      category: kCategoryStaff,
      severity: kSeverityInfo,
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      targetType: 'staff_account',
      targetId: cswdId,
      details: {'approved_role': requestedRole},
    );

    await loadAccounts();
  }

  Future<void> rejectAccount({
    required String cswdId,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    await _staffAdminService.rejectAccount(cswdId);

    await _auditLogService.log(
      actionType: kAuditStaffRejected,
      category: kCategoryStaff,
      severity: kSeverityWarning,
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      targetType: 'staff_account',
      targetId: cswdId,
    );

    await loadAccounts();
  }

  Future<void> deactivateAccount({
    required String cswdId,
    required String username,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    await _webAuthService.deactivateStaffAccount(cswdId);

    await _auditLogService.log(
      actionType: 'staff_deactivated',
      category: kCategoryStaff,
      severity: kSeverityWarning,
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      targetType: 'staff_account',
      targetId: cswdId,
      targetLabel: username,
    );

    await loadAccounts();
  }

  Future<void> reactivateAccount({
    required String cswdId,
    required String username,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    await _webAuthService.reactivateStaffAccount(cswdId);

    await _auditLogService.log(
      actionType: 'staff_reactivated',
      category: kCategoryStaff,
      severity: kSeverityInfo,
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      targetType: 'staff_account',
      targetId: cswdId,
      targetLabel: username,
    );

    await loadAccounts();
  }
}
