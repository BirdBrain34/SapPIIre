class AnalyticsField {
  final String fieldKey;
  final String label;
  final AnalyticsChartType chartType;

  const AnalyticsField({
    required this.fieldKey,
    required this.label,
    required this.chartType,
  });
}

enum AnalyticsChartType { bar, pie, counter }

class FormTypeAnalyticsConfig {
  static List<AnalyticsField> getFieldsForFormType(String formType) {
    if (formType == 'All') {
      return const [];
    }

    final normalized = _normalize(formType);

    if (normalized == _normalize('General Intake Sheet')) {
      return const [
        AnalyticsField(
          fieldKey: 'Kasarian',
          label: 'Gender Distribution',
          chartType: AnalyticsChartType.pie,
        ),
        AnalyticsField(
          fieldKey: '__age_group',
          label: 'Age Groups',
          chartType: AnalyticsChartType.bar,
        ),
        AnalyticsField(
          fieldKey: 'Buwanang Kita (A)',
          label: 'Monthly Income',
          chartType: AnalyticsChartType.bar,
        ),
        AnalyticsField(
          fieldKey: '__membership',
          label: 'Program Membership',
          chartType: AnalyticsChartType.bar,
        ),
      ];
    }

    return const [];
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
