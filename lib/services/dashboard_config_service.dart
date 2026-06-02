import 'package:flutter/foundation.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';

class DashboardWidgetConfig {
  final String fieldName;
  final String fieldLabel;
  final String chartType;
  final int order;

  const DashboardWidgetConfig({
    required this.fieldName,
    required this.fieldLabel,
    required this.chartType,
    this.order = 0,
  });

  factory DashboardWidgetConfig.fromField(FormFieldModel field) {
    return DashboardWidgetConfig(
      fieldName: field.fieldName,
      fieldLabel: field.fieldLabel.trim().isEmpty
          ? field.fieldName
          : field.fieldLabel,
      chartType: _chartTypeFor(field.fieldType),
      order: field.fieldOrder,
    );
  }

  static String _chartTypeFor(FormFieldType type) {
    switch (type) {
      case FormFieldType.boolean:
      case FormFieldType.dropdown:
      case FormFieldType.radio:
        return 'pie';
      case FormFieldType.checkbox:
        return 'hbar';
      case FormFieldType.number:
      case FormFieldType.text:
      case FormFieldType.linearScale:
        return 'bar';
      default:
        return 'table';
    }
  }
}

class DashboardConfigService {
  DashboardConfigService({FormTemplateService? templateService})
    : _templateService = templateService ?? FormTemplateService();

  final FormTemplateService _templateService;
  final Map<String, List<DashboardWidgetConfig>> _cache = {};

  Future<List<DashboardWidgetConfig>> fetchConfig(
    String templateId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache.containsKey(templateId)) {
      return _cache[templateId]!;
    }

    try {
      final template = await _templateService.fetchTemplate(
        templateId,
        forceRefresh: forceRefresh,
      );

      if (template == null) {
        return [];
      }

      final configs = _buildConfigs(template);
      _cache[templateId] = configs;
      return configs;
    } catch (e, stack) {
      debugPrint('[DashboardConfigService/fetchConfig] Error: $e');
      debugPrint('[DashboardConfigService/fetchConfig] Stack: $stack');
      return [];
    }
  }

  List<DashboardWidgetConfig> _buildConfigs(FormTemplate template) {
    final chartableFields =
        template.allFields
            .where((field) => field.parentFieldId == null)
            .where((field) => !_skipTypes.contains(field.fieldType))
            .toList()
          ..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder));

    return chartableFields
        .map(DashboardWidgetConfig.fromField)
        .toList(growable: false);
  }

  void clearCache() {
    _cache.clear();
  }
}

const _skipTypes = {
  FormFieldType.signature,
  FormFieldType.familyTable,
  FormFieldType.membershipGroup,
  FormFieldType.supportingFamilyTable,
  FormFieldType.computed,
  FormFieldType.paragraph,
  FormFieldType.memberTable,
  FormFieldType.conditional,
  FormFieldType.unknown,
};
