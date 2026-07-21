import 'package:flutter/foundation.dart';
import 'package:sappiire/services/form_builder_service.dart';

class ApprovalsController extends ChangeNotifier {
  final FormBuilderService _service;

  ApprovalsController({FormBuilderService? service})
    : _service = service ?? FormBuilderService();

  List<Map<String, dynamic>> _pendingTemplates = [];
  bool _isLoading = false;
  bool _isApproving = false;
  bool _isRejecting = false;

  List<Map<String, dynamic>> get pendingTemplates => _pendingTemplates;
  bool get isLoading => _isLoading;
  bool get isApproving => _isApproving;
  bool get isRejecting => _isRejecting;

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

  Future<bool> approveTemplate(String templateId, String approverId) async {
    _isApproving = true;
    notifyListeners();

    try {
      final success = await _service.approveTemplate(
        templateId,
        approverId,
      );
      if (success) {
        _pendingTemplates.removeWhere(
          (t) => t['template_id'] == templateId,
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
      final success = await _service.rejectTemplate(templateId, reason.trim());
      if (success) {
        _pendingTemplates.removeWhere(
          (t) => t['template_id'] == templateId,
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