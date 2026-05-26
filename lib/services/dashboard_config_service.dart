import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardWidgetConfig {
  final String id;
  final String templateId;
  final String fieldName;
  final String fieldLabel;
  final String chartType;
  final int displayOrder;

  const DashboardWidgetConfig({
    required this.id,
    required this.templateId,
    required this.fieldName,
    required this.fieldLabel,
    required this.chartType,
    required this.displayOrder,
  });

  factory DashboardWidgetConfig.fromMap(Map<String, dynamic> map) {
    return DashboardWidgetConfig(
      id: map['id']?.toString() ?? '',
      templateId: map['template_id']?.toString() ?? '',
      fieldName: map['field_name']?.toString() ?? '',
      fieldLabel: map['field_label']?.toString() ?? '',
      chartType: map['chart_type']?.toString() ?? 'bar',
      displayOrder: int.tryParse(map['display_order']?.toString() ?? '0') ?? 0,
    );
  }
}

class DashboardConfigService {
  static final DashboardConfigService _instance =
      DashboardConfigService._internal();

  factory DashboardConfigService() => _instance;

  DashboardConfigService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  String? lastError;

  Future<List<DashboardWidgetConfig>> fetchConfig(String templateId) async {
    try {
      final rows = await _supabase
          .from('dashboard_widget_configs')
          .select('id, template_id, field_name, field_label, chart_type, display_order')
          .eq('template_id', templateId)
          .order('display_order', ascending: true);

      return List<Map<String, dynamic>>.from(rows)
          .map(DashboardWidgetConfig.fromMap)
          .toList();
    } catch (e) {
      debugPrint('[DashboardConfigService/fetchConfig] Error: $e');
      return [];
    }
  }

  Future<bool> saveConfig(
    String templateId,
    List<DashboardWidgetConfig> configs,
    String createdBy,
  ) async {
    try {
      await _supabase.from('dashboard_widget_configs').delete().eq(
            'template_id',
            templateId,
          );

      if (configs.isNotEmpty) {
        final rows = configs.asMap().entries.map((entry) {
          final config = entry.value;
          return {
            'template_id': templateId,
            'field_name': config.fieldName,
            'field_label': config.fieldLabel,
            'chart_type': config.chartType,
            'display_order': entry.key,
            'created_by': createdBy,
          };
        }).toList();

        await _supabase.from('dashboard_widget_configs').insert(rows);
      }

      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[DashboardConfigService/saveConfig] Error: $e');
      return false;
    }
  }

  Future<void> deleteConfig(String templateId) async {
    try {
      await _supabase.from('dashboard_widget_configs').delete().eq(
            'template_id',
            templateId,
          );
    } catch (e) {
      debugPrint('[DashboardConfigService/deleteConfig] Error: $e');
      rethrow;
    }
  }
}