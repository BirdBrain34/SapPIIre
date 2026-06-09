import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_template_service.dart';

class DashboardWidgetConfig {
  final String? id;
  final String? templateId;
  final String fieldName;
  final String fieldLabel;
  final String chartType;
  final int displayOrder;

  const DashboardWidgetConfig({
    this.id,
    this.templateId,
    required this.fieldName,
    required this.fieldLabel,
    required this.chartType,
    this.displayOrder = 0,
  });

  factory DashboardWidgetConfig.fromField(FormFieldModel field) {
    return DashboardWidgetConfig(
      fieldName: field.fieldName,
      fieldLabel: field.fieldLabel.trim().isEmpty
          ? field.fieldName
          : field.fieldLabel,
      chartType: _chartTypeFor(field.fieldType),
      displayOrder: field.fieldOrder,
    );
  }

  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> json) {
    return DashboardWidgetConfig(
      id: json['id'] as String?,
      templateId: json['template_id'] as String?,
      fieldName: json['field_name'] as String? ?? '',
      fieldLabel: json['field_label'] as String? ?? '',
      chartType: json['chart_type'] as String? ?? 'bar',
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'template_id': templateId,
    'field_name': fieldName,
    'field_label': fieldLabel,
    'chart_type': chartType,
    'display_order': displayOrder,
  };

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
  static final DashboardConfigService _instance =
      DashboardConfigService._internal();

  factory DashboardConfigService() => _instance;

  DashboardConfigService._internal({FormTemplateService? templateService})
    : _templateService = templateService ?? FormTemplateService();

  final FormTemplateService _templateService;
  final SupabaseClient _supabase = Supabase.instance.client;
  final Map<String, List<DashboardWidgetConfig>> _cache = {};

  Future<List<DashboardWidgetConfig>> fetchConfig(
    String templateId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache.containsKey(templateId)) {
      return _cache[templateId]!;
    }

    try {
      // Try to fetch from database first
      final rows = await _supabase
          .from('dashboard_widget_configs')
          .select()
          .eq('template_id', templateId)
          .order('display_order', ascending: true);

      if (rows.isNotEmpty) {
        final configs = List<DashboardWidgetConfig>.from(
          (rows as List).map((row) => DashboardWidgetConfig.fromJson(
            row as Map<String, dynamic>,
          )),
        );
        _cache[templateId] = configs;
        return configs;
      }

      // Fallback: generate defaults from template if no saved config exists
      final template = await _templateService.fetchTemplate(
        templateId,
        forceRefresh: forceRefresh,
      );

      if (template == null) {
        return [];
      }

      final configs = _buildConfigs(template, templateId);
      _cache[templateId] = configs;
      return configs;
    } catch (e, stack) {
      debugPrint('[DashboardConfigService/fetchConfig] Error: $e');
      debugPrint('[DashboardConfigService/fetchConfig] Stack: $stack');
      return [];
    }
  }

  Future<void> saveConfig(
    String templateId,
    List<DashboardWidgetConfig> widgets,
    String staffId,
  ) async {
    try {
      // Delete existing config for this template
      await _supabase
          .from('dashboard_widget_configs')
          .delete()
          .eq('template_id', templateId);

      // Insert new config rows
      if (widgets.isNotEmpty) {
        final rows = widgets.asMap().entries.map((entry) {
          final config = entry.value;
          final index = entry.key;
          return {
            'template_id': templateId,
            'field_name': config.fieldName,
            'field_label': config.fieldLabel,
            'chart_type': config.chartType,
            'display_order': index,
            'created_by': staffId,
          };
        }).toList();

        await _supabase.from('dashboard_widget_configs').insert(rows);
      }

      // Clear cache to force reload
      _cache.remove(templateId);
    } catch (e, stack) {
      debugPrint('[DashboardConfigService/saveConfig] Error: $e');
      debugPrint('[DashboardConfigService/saveConfig] Stack: $stack');
      rethrow;
    }
  }

  List<DashboardWidgetConfig> _buildConfigs(
    FormTemplate template,
    String templateId,
  ) {
    final chartableFields =
        template.allFields
            .where((field) => field.parentFieldId == null)
            .where((field) => !_skipTypes.contains(field.fieldType))
            .toList()
          ..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder));

    return chartableFields
        .map((field) => DashboardWidgetConfig.fromField(field))
        .toList();
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
