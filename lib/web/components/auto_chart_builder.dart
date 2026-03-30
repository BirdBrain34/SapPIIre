import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_analytics_service.dart';

class ChartConfig {
  final String title;
  final Map<String, int> data;
  final ChartStyle style;

  const ChartConfig({
    required this.title,
    required this.data,
    required this.style,
  });
}

enum ChartStyle { pie, bar }

const _chartableTypes = {
  FormFieldType.dropdown,
  FormFieldType.radio,
  FormFieldType.checkbox,
  FormFieldType.boolean,
  FormFieldType.number,
  FormFieldType.text,
  FormFieldType.linearScale,
};

const _skipTypes = {
  FormFieldType.signature,
  FormFieldType.familyTable,
  FormFieldType.membershipGroup,
  FormFieldType.supportingFamilyTable,
  FormFieldType.computed,
  FormFieldType.paragraph,
  FormFieldType.memberTable,
  FormFieldType.unknown,
};

class AutoChartBuilder {
  final DashboardAnalyticsService _service = DashboardAnalyticsService();

  Future<List<ChartConfig>> buildCharts({
    required FormTemplate template,
    required String formType,
  }) async {
    final chartableFields = template.allFields
        .where((field) => field.parentFieldId == null)
        .where((field) => _chartableTypes.contains(field.fieldType))
        .where((field) => !_skipTypes.contains(field.fieldType))
        .toList();

    if (chartableFields.isEmpty) {
      return [];
    }

    final futures = chartableFields.map((field) async {
      final isMulti = field.fieldType == FormFieldType.checkbox;
      final isNumeric = field.fieldType == FormFieldType.number;
      final isText = field.fieldType == FormFieldType.text;

      final data = await _service.fetchFieldDistribution(
        formType: formType,
        fieldName: field.fieldName,
        isNumeric: isNumeric,
        isMultiSelect: isMulti,
        topN: isText ? 10 : 1000,
      );

      if (data.length < 2) {
        return null;
      }

      return ChartConfig(
        title: field.fieldLabel.isNotEmpty ? field.fieldLabel : field.fieldName,
        data: data,
        style: _pickChartStyle(field, data),
      );
    });

    final results = await Future.wait(futures);
    return results.whereType<ChartConfig>().toList();
  }

  ChartStyle _pickChartStyle(FormFieldModel field, Map<String, int> data) {
    if (data.length <= 5 &&
        (field.fieldType == FormFieldType.radio ||
            field.fieldType == FormFieldType.dropdown ||
            field.fieldType == FormFieldType.boolean)) {
      return ChartStyle.pie;
    }

    return ChartStyle.bar;
  }
}
