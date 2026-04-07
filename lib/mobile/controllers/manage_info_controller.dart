import 'package:flutter/material.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/supabase_service.dart';

class ManageInfoController extends ChangeNotifier {
  final String userId;
  final FormTemplateService _templateService = FormTemplateService();
  final SupabaseService _supabaseService = SupabaseService();
  final FieldValueService _fieldValueService = FieldValueService();

  List<FormTemplate> templates = [];
  FormTemplate? selectedTemplate;
  FormStateController? formController;
  String username = '';
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  ManageInfoController({required this.userId});

  Future<bool> _waitForSignatureReady(FormStateController ctrl) async {
    const timeout = Duration(seconds: 12);
    final start = DateTime.now();
    while (ctrl.signatureIsProcessing) {
      if (DateTime.now().difference(start) >= timeout) {
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 75));
    }
    return true;
  }

  // Parallel fetch saves initial load time.
  Future<void> loadAll({bool forceRefresh = false}) async {
    final previousTemplateId = selectedTemplate?.templateId;
    final isFirstLoad = templates.isEmpty && selectedTemplate == null;
    if (isFirstLoad) {
      isLoading = true;
      notifyListeners();
    }

    try {
      errorMessage = null;
      final results = await Future.wait([
        _templateService.fetchActiveTemplates(forceRefresh: forceRefresh),
        _supabaseService.getUsername(userId),
      ]);

      final fetchedTemplates = results[0] as List<FormTemplate>;
      final fetchedUsername = results[1] as String?;

      templates = fetchedTemplates;
      username = fetchedUsername ?? '';

      if (templates.isEmpty) {
        selectedTemplate = null;
      } else if (previousTemplateId != null &&
          templates.any((t) => t.templateId == previousTemplateId)) {
        selectedTemplate = templates.firstWhere(
          (t) => t.templateId == previousTemplateId,
        );
      } else {
        selectedTemplate = templates.firstWhere(
          (t) => t.formName == 'General Intake Sheet',
          orElse: () => templates.first,
        );
      }

      if (selectedTemplate != null) {
        await _buildFormController();
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchTemplate(String templateId) async {
    selectedTemplate = templates.firstWhere((t) => t.templateId == templateId);
    notifyListeners();
    await _buildFormController();
    notifyListeners();
  }

  Future<void> _buildFormController() async {
    final template = selectedTemplate;
    if (template == null) {
      formController?.dispose();
      formController = null;
      return;
    }

    final oldCtrl = formController;
    formController = null;
    oldCtrl?.dispose();

    final ctrl = FormStateController(template: template);
    final loaded = await _fieldValueService.loadUserFieldValuesWithCrossFormFill(
      userId: userId,
      template: template,
    );
    ctrl.loadFromJson(loaded);

    for (final field in template.allFields) {
      if (field.fieldType == FormFieldType.signature) {
        final sigVal = loaded[field.fieldName];
        if (sigVal != null && sigVal.toString().isNotEmpty) {
          ctrl.signatureBase64 = sigVal.toString();
        }
        break;
      }
    }

    if ((ctrl.signatureBase64 == null || ctrl.signatureBase64!.isEmpty) &&
        loaded['__signature'] != null &&
        loaded['__signature'].toString().isNotEmpty) {
      ctrl.signatureBase64 = loaded['__signature'].toString();
    }

    formController = ctrl;
  }

  // Returns false and sets errorMessage on failure.
  Future<bool> saveProfile() async {
    final ctrl = formController;
    final template = selectedTemplate;
    if (ctrl == null || template == null) {
      errorMessage = 'No form loaded';
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      final signatureReady = await _waitForSignatureReady(ctrl);
      if (!signatureReady) {
        errorMessage =
            'Signature processing is taking longer than expected. Please wait a few seconds and save again.';
        return false;
      }

      final data = ctrl.toJson();
      if (data['__signature'] != null) {
        ctrl.signatureBase64 = data['__signature'];
      }

      final saved = await _fieldValueService.saveUserFieldValues(
        userId: userId,
        template: template,
        formData: data,
      );

      if (!saved) {
        errorMessage = 'Failed to save field values. Please try again.';
        return false;
      }

      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  // Null means no fields were checked by the user.
  Map<String, dynamic>? buildTransmitPayload() {
    final ctrl = formController;
    if (ctrl == null) return null;

    final hasAnyChecked =
        ctrl.selectAll || ctrl.fieldChecks.values.any((checked) => checked == true);
    if (!hasAnyChecked) return null;

    return ctrl.toFilteredJson();
  }

  @override
  void dispose() {
    formController?.dispose();
    super.dispose();
  }
}
