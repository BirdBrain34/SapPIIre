import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sappiire/models/form_template_models.dart';

String generateUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int s, int e) =>
      b.sublist(s, e).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

String slugify(String label) =>
    label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

String sanitizeCode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return cleaned.length > 10 ? cleaned.substring(0, 10) : cleaned;
}

List<String> referenceFormatParts(String referenceFormat) {
  if (referenceFormat.isEmpty) return const [];
  return RegExp(
    r'(\{[^{}]+\}|.)',
  ).allMatches(referenceFormat).map((m) => m.group(0)!).toList();
}

String appendReferenceToken(String referenceFormat, String token) =>
    '$referenceFormat$token';

String appendReferenceSeparator(String referenceFormat, String separator) =>
    '$referenceFormat$separator';

String removeReferencePartAt(String referenceFormat, int index) {
  final parts = referenceFormatParts(referenceFormat);
  if (index < 0 || index >= parts.length) return referenceFormat;
  parts.removeAt(index);
  return parts.join();
}

String referencePreview({
  required String referenceFormat,
  required String referencePrefix,
  required String formCode,
}) {
  final now = DateTime.now();
  var ref = referenceFormat;
  final prefix = referencePrefix.trim().isNotEmpty
      ? referencePrefix.trim().toUpperCase()
      : (formCode.trim().isNotEmpty ? formCode.trim().toUpperCase() : 'FORM');

  String pad(int v, int n) => v.toString().padLeft(n, '0');
  final yearStart = DateTime(now.year, 1, 1);
  final dayOfYear = now.difference(yearStart).inDays + 1;
  final quarter = ((now.month - 1) ~/ 3) + 1;

  ref = ref.replaceAll('{FORMCODE}', prefix);
  ref = ref.replaceAll('{YYYY}', now.year.toString());
  ref = ref.replaceAll('{YY}', now.year.toString().substring(2));
  ref = ref.replaceAll('{MM}', pad(now.month, 2));
  ref = ref.replaceAll(
    '{MON}',
    const [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ][now.month - 1],
  );
  ref = ref.replaceAll(
    '{MONTH}',
    const [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ][now.month - 1],
  );
  ref = ref.replaceAll('{DD}', pad(now.day, 2));
  ref = ref.replaceAll('{DDD}', pad(dayOfYear, 3));
  ref = ref.replaceAll('{Q}', '$quarter');
  ref = ref.replaceAll('{WW}', pad(((dayOfYear - 1) ~/ 7) + 1, 2));
  ref = ref.replaceAll('{IW}', pad(((dayOfYear - 1) ~/ 7) + 1, 2));
  ref = ref.replaceAll('{HH24}', pad(now.hour, 2));
  ref = ref.replaceAll('{MI}', pad(now.minute, 2));
  ref = ref.replaceAll('{SS}', pad(now.second, 2));
  ref = ref.replaceAll('{########}', '????????');
  ref = ref.replaceAll('{######}', '??????');
  ref = ref.replaceAll('{####}', '????');
  ref = ref.replaceAll('{###}', '???');
  ref = ref.replaceAll('{##}', '??');
  ref = ref.replaceAll('{#}', '?');
  return ref;
}

const typeLabels = <FormFieldType, String>{
  FormFieldType.radio: 'Multiple Choice',
  FormFieldType.checkbox: 'Checkboxes',
  FormFieldType.dropdown: 'Dropdown',
  FormFieldType.text: 'Short Answer',
  FormFieldType.date: 'Date',
  FormFieldType.time: 'Time',
  FormFieldType.number: 'Number',
  FormFieldType.boolean: 'Yes / No',
  FormFieldType.signature: 'Signature',
  FormFieldType.memberTable: 'Member Table',
};

const typeIcons = <FormFieldType, IconData>{
  FormFieldType.radio: Icons.radio_button_checked,
  FormFieldType.checkbox: Icons.check_box_outlined,
  FormFieldType.dropdown: Icons.arrow_drop_down_circle_outlined,
  FormFieldType.text: Icons.short_text,
  FormFieldType.date: Icons.calendar_today,
  FormFieldType.time: Icons.access_time,
  FormFieldType.number: Icons.pin,
  FormFieldType.boolean: Icons.toggle_on_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.memberTable: Icons.table_chart_outlined,
};

const systemTypeLabels = <FormFieldType, String>{
  FormFieldType.computed: 'Computed',
  FormFieldType.conditional: 'Conditional',
  FormFieldType.membershipGroup: 'Membership Group',
  FormFieldType.familyTable: 'Family Table',
  FormFieldType.supportingFamilyTable: 'Supporting Family Table',
  FormFieldType.signature: 'Signature',
  FormFieldType.unknown: 'Unknown',
};

const systemTypeIcons = <FormFieldType, IconData>{
  FormFieldType.computed: Icons.calculate_outlined,
  FormFieldType.conditional: Icons.device_hub_outlined,
  FormFieldType.membershipGroup: Icons.group_outlined,
  FormFieldType.familyTable: Icons.table_chart_outlined,
  FormFieldType.supportingFamilyTable: Icons.table_chart_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.unknown: Icons.help_outline,
};

const standardProfileCanonicalKeys = <({String key, String label})>[
  (key: 'last_name', label: 'Last Name'),
  (key: 'first_name', label: 'First Name'),
  (key: 'middle_name', label: 'Middle Name'),
  (key: 'date_of_birth', label: 'Date of Birth'),
  (key: 'age', label: 'Age'),
  (key: 'kasarian_sex', label: 'Sex / Kasarian'),
  (key: 'estadong_sibil_civil_status', label: 'Civil Status / Estadong Sibil'),
  (key: 'lugar_ng_kapanganakan_place_of_birth', label: 'Place of Birth'),
  (key: 'cp_number', label: 'Phone Number / CP Number'),
  (key: 'email_address', label: 'Email Address'),
  (
    key: 'house_number_street_name_phase_purok',
    label: 'House No. / Street / Purok',
  ),
  (key: 'barangay', label: 'Barangay'),
  (key: 'subdivison_', label: 'Subdivision'),
  (key: 'signature', label: 'Signature'),
];

const canonicalKeyEligibleTypes = <FormFieldType>{
  FormFieldType.text,
  FormFieldType.number,
  FormFieldType.date,
  FormFieldType.dropdown,
  FormFieldType.radio,
  FormFieldType.boolean,
};

class ReferenceToken {
  final String label;
  final String token;
  final String hint;
  final String group;

  const ReferenceToken(this.label, this.token, this.hint, this.group);
}

const referenceTokens = <ReferenceToken>[
  ReferenceToken('Form Code', '{FORMCODE}', 'GIS', 'Form Info'),
  ReferenceToken('Year (2026)', '{YYYY}', '2026', 'Date'),
  ReferenceToken('Year Short (26)', '{YY}', '26', 'Date'),
  ReferenceToken('Month Number (03)', '{MM}', '03', 'Date'),
  ReferenceToken('Month Short (MAR)', '{MON}', 'MAR', 'Date'),
  ReferenceToken('Day (26)', '{DD}', '26', 'Date'),
  ReferenceToken('Day of Year (085)', '{DDD}', '085', 'Date'),
  ReferenceToken('Quarter (1)', '{Q}', '1', 'Date'),
  ReferenceToken('Week Number (13)', '{WW}', '13', 'Date'),
  ReferenceToken('ISO Week (13)', '{IW}', '13', 'Date'),
  ReferenceToken('Hour (14)', '{HH24}', '14', 'Time'),
  ReferenceToken('Minute (30)', '{MI}', '30', 'Time'),
  ReferenceToken('Second (00)', '{SS}', '00', 'Time'),
  ReferenceToken('Counter 8-digit (00000001)', '{########}', '00000001', 'Counter'),
  ReferenceToken('Counter 6-digit (000001)', '{######}', '000001', 'Counter'),
  ReferenceToken('Counter 4-digit (0001)', '{####}', '0001', 'Counter'),
  ReferenceToken('Counter 3-digit (001)', '{###}', '001', 'Counter'),
  ReferenceToken('Counter 2-digit (01)', '{##}', '01', 'Counter'),
  ReferenceToken('Counter (1)', '{#}', '1', 'Counter'),
];

const referenceTokenGroups = <String>['Form Info', 'Date', 'Time', 'Counter'];

class BuilderOption {
  String id;
  String label;
  int order;

  BuilderOption({String? id, this.label = 'Option', this.order = 0})
    : id = id ?? generateUuid();
}

class BuilderColumn {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  int order;
  List<BuilderOption> options;
  String? dbMapKey;
  String? ageFromColumnId;

  BuilderColumn({
    String? id,
    this.label = 'Column',
    String? fieldName,
    this.type = FormFieldType.text,
    this.order = 0,
    List<BuilderOption>? options,
    this.dbMapKey,
    this.ageFromColumnId,
  })  : id = id ?? generateUuid(),
        fieldName = fieldName ?? 'col_${generateUuid().substring(0, 8)}',
        options = options ?? [];

  bool get isCoreColumn => dbMapKey != null;
}

class BuilderCondition {
  String triggerFieldId;
  String triggerValue;
  String action;

  BuilderCondition({
    this.triggerFieldId = '',
    this.triggerValue = '',
    this.action = 'show',
  });
}

class BuilderField {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  bool isRequired;
  String? canonicalFieldKey;
  int order;
  List<BuilderOption> options;
  List<BuilderColumn> columns;
  int scaleMin;
  int scaleMax;
  String formula;
  String? ageFromFieldId;
  BuilderCondition condition;

  BuilderField({
    String? id,
    this.label = 'Untitled Question',
    String? fieldName,
    this.type = FormFieldType.radio,
    this.isRequired = false,
    this.canonicalFieldKey,
    this.order = 0,
    List<BuilderOption>? options,
    List<BuilderColumn>? columns,
    this.scaleMin = 1,
    this.scaleMax = 5,
    this.formula = '',
    this.ageFromFieldId,
    BuilderCondition? condition,
  })  : id = id ?? generateUuid(),
        fieldName = fieldName ?? 'field_${generateUuid().substring(0, 8)}',
        options = options ?? [BuilderOption(label: 'Option 1', order: 0)],
        columns = columns ?? [],
        condition = condition ?? BuilderCondition();

  bool get hasOptions =>
      type == FormFieldType.radio ||
      type == FormFieldType.checkbox ||
      type == FormFieldType.dropdown;
}

class BuilderSection {
  String id;
  String name;
  String? description;
  int order;
  List<BuilderField> fields;

  BuilderSection({
    String? id,
    this.name = 'Untitled Section',
    this.description,
    this.order = 0,
    List<BuilderField>? fields,
  })  : id = id ?? generateUuid(),
        fields = fields ?? [];
}

enum TemplateListFilter { all, active, draft, published, archived }

class FormBuilderController extends ChangeNotifier {}
