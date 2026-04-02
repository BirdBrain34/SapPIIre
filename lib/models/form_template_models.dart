// Form Template Models
// Data models for the dynamic form system.
// These mirror the Supabase database schema for form_templates, form_sections, form_fields.
//
// Structure:
// - FormTemplate: Top-level form definition
// - FormSection: Groups related fields together
// - FormFieldModel: Individual field definition with type, validation, options
// - FieldOption: Dropdown/radio options
// - FieldCondition: Conditional visibility rules
//
// Used by FormTemplateService to parse database responses and by
// DynamicFormRenderer to build the UI.

// Field type enum
enum FormFieldType {
  text,
  paragraph,
  date,
  time,
  number,
  dropdown,
  radio,
  checkbox,
  boolean,
  linearScale,
  computed,
  conditional,
  membershipGroup,
  familyTable,
  supportingFamilyTable,
  memberTable,
  signature,
  unknown;

  static FormFieldType fromString(String v) {
    switch (v) {
      case 'text':
        return FormFieldType.text;
      case 'paragraph':
        return FormFieldType.paragraph;
      case 'date':
        return FormFieldType.date;
      case 'time':
        return FormFieldType.time;
      case 'number':
        return FormFieldType.number;
      case 'dropdown':
        return FormFieldType.dropdown;
      case 'radio':
        return FormFieldType.radio;
      case 'checkbox':
        return FormFieldType.checkbox;
      case 'boolean':
        return FormFieldType.boolean;
      case 'linear_scale':
        return FormFieldType.linearScale;
      case 'computed':
        return FormFieldType.computed;
      case 'conditional':
        return FormFieldType.conditional;
      case 'membership_group':
        return FormFieldType.membershipGroup;
      case 'family_table':
        return FormFieldType.familyTable;
      case 'supporting_family_table':
        return FormFieldType.supportingFamilyTable;
      case 'member_table':
        return FormFieldType.memberTable;
      case 'signature':
        return FormFieldType.signature;
      default:
        return FormFieldType.unknown;
    }
  }

  /// Whether this type is a system/custom type that should not be changed
  /// by the user in the form builder (e.g. familyTable, computed, signature).
  bool get isSystemType => const {
    FormFieldType.conditional,
    FormFieldType.membershipGroup,
    FormFieldType.familyTable,
    FormFieldType.supportingFamilyTable,
    FormFieldType.signature,
    FormFieldType.unknown,
  }.contains(this);

  /// Convert enum value back to the database string representation.
  String toDbString() {
    switch (this) {
      case FormFieldType.text:
        return 'text';
      case FormFieldType.paragraph:
        return 'paragraph';
      case FormFieldType.date:
        return 'date';
      case FormFieldType.time:
        return 'time';
      case FormFieldType.number:
        return 'number';
      case FormFieldType.dropdown:
        return 'dropdown';
      case FormFieldType.radio:
        return 'radio';
      case FormFieldType.checkbox:
        return 'checkbox';
      case FormFieldType.boolean:
        return 'boolean';
      case FormFieldType.linearScale:
        return 'linear_scale';
      case FormFieldType.computed:
        return 'computed';
      case FormFieldType.conditional:
        return 'conditional';
      case FormFieldType.membershipGroup:
        return 'membership_group';
      case FormFieldType.familyTable:
        return 'family_table';
      case FormFieldType.supportingFamilyTable:
        return 'supporting_family_table';
      case FormFieldType.memberTable:
        return 'member_table';
      case FormFieldType.signature:
        return 'signature';
      case FormFieldType.unknown:
        return 'unknown';
    }
  }
}

// Field option for dropdown/radio fields
class FieldOption {
  final String optionId;
  final String value;
  final String label;
  final int order;
  final bool isDefault;

  const FieldOption({
    required this.optionId,
    required this.value,
    required this.label,
    this.order = 0,
    this.isDefault = false,
  });

  factory FieldOption.fromMap(Map<String, dynamic> m) => FieldOption(
    optionId: m['option_id'] as String,
    value: m['option_value'] as String,
    label: m['option_label'] as String,
    order: (m['option_order'] as int?) ?? 0,
    isDefault: (m['is_default'] as bool?) ?? false,
  );
}

// Field condition for conditional visibility
class FieldCondition {
  final String conditionId;
  final String fieldId;
  final String triggerFieldId;
  final String? triggerValue;
  final String action; // 'show' | 'hide' | 'require'

  const FieldCondition({
    required this.conditionId,
    required this.fieldId,
    required this.triggerFieldId,
    this.triggerValue,
    this.action = 'show',
  });

  factory FieldCondition.fromMap(Map<String, dynamic> m) => FieldCondition(
    conditionId: m['condition_id'] as String,
    fieldId: m['field_id'] as String,
    triggerFieldId: m['trigger_field_id'] as String,
    triggerValue: m['trigger_value'] as String?,
    action: (m['action'] as String?) ?? 'show',
  );
}

// Form field definition
class FormFieldModel {
  final String fieldId;
  final String templateId;
  final String? sectionId;
  final String fieldName; // internal key, used as map key in form_data
  final String fieldLabel; // display label
  final FormFieldType fieldType;
  final bool isRequired;
  final Map<String, dynamic>? validationRules;
  final String? defaultValue;
  final int fieldOrder;
  final String?
  autofillSource; // e.g. 'lastname', 'address.barangay', 'socio.house_rent'
  final String? canonicalFieldKey;
  final String? placeholder;
  final List<FieldOption> options;
  final List<FieldCondition> conditions;
  final String? parentFieldId;
  final List<FormFieldModel>
  columns; // child column definitions for memberTable

  const FormFieldModel({
    required this.fieldId,
    required this.templateId,
    this.sectionId,
    required this.fieldName,
    required this.fieldLabel,
    required this.fieldType,
    this.isRequired = false,
    this.validationRules,
    this.defaultValue,
    this.fieldOrder = 0,
    this.autofillSource,
    this.canonicalFieldKey,
    this.placeholder,
    this.options = const [],
    this.conditions = const [],
    this.parentFieldId,
    this.columns = const [],
  });

  factory FormFieldModel.fromMap(Map<String, dynamic> m) => FormFieldModel(
    fieldId: m['field_id'] as String,
    templateId: m['template_id'] as String,
    sectionId: m['section_id'] as String?,
    fieldName: m['field_name'] as String,
    fieldLabel: m['field_label'] as String,
    fieldType: FormFieldType.fromString(m['field_type'] as String? ?? ''),
    isRequired: (m['is_required'] as bool?) ?? false,
    validationRules: m['validation_rules'] as Map<String, dynamic>?,
    defaultValue: m['default_value'] as String?,
    fieldOrder: (m['field_order'] as int?) ?? 0,
    autofillSource: m['autofill_source'] as String?,
    canonicalFieldKey: m['canonical_field_key'] as String?,
    placeholder: m['placeholder'] as String?,
    options:
        (m['form_field_options'] as List<dynamic>? ?? [])
            .map((o) => FieldOption.fromMap(o as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
    conditions: (m['form_field_conditions'] as List<dynamic>? ?? [])
        .map((c) => FieldCondition.fromMap(c as Map<String, dynamic>))
        .toList(),
    parentFieldId: m['parent_field_id'] as String?,
  );

  /// Display key for checkbox/sharing UI (avoids duplicating this across files).
  String get checkKey {
    if (fieldType == FormFieldType.familyTable) return 'Family Composition';
    if (fieldType == FormFieldType.signature) return 'Signature';
    if (fieldType == FormFieldType.membershipGroup) return 'Membership Group';
    if (fieldType == FormFieldType.memberTable) return fieldLabel;
    return fieldName;
  }

  /// Create a copy with selected fields overridden.
  FormFieldModel copyWith({
    String? fieldId,
    String? templateId,
    String? sectionId,
    String? fieldName,
    String? fieldLabel,
    FormFieldType? fieldType,
    bool? isRequired,
    Map<String, dynamic>? validationRules,
    String? defaultValue,
    int? fieldOrder,
    String? autofillSource,
    String? placeholder,
    List<FieldOption>? options,
    List<FieldCondition>? conditions,
    String? parentFieldId,
    List<FormFieldModel>? columns,
  }) {
    return FormFieldModel(
      fieldId: fieldId ?? this.fieldId,
      templateId: templateId ?? this.templateId,
      sectionId: sectionId ?? this.sectionId,
      fieldName: fieldName ?? this.fieldName,
      fieldLabel: fieldLabel ?? this.fieldLabel,
      fieldType: fieldType ?? this.fieldType,
      isRequired: isRequired ?? this.isRequired,
      validationRules: validationRules ?? this.validationRules,
      defaultValue: defaultValue ?? this.defaultValue,
      fieldOrder: fieldOrder ?? this.fieldOrder,
      autofillSource: autofillSource ?? this.autofillSource,
      placeholder: placeholder ?? this.placeholder,
      options: options ?? this.options,
      conditions: conditions ?? this.conditions,
      parentFieldId: parentFieldId ?? this.parentFieldId,
      columns: columns ?? this.columns,
    );
  }

  // Returns true if this field should be visible given current form values
  bool isVisible(Map<String, dynamic> formValues) {
    if (conditions.isEmpty) return true;
    // If ANY condition says "show", evaluate it
    final showConditions = conditions.where((c) => c.action == 'show').toList();
    if (showConditions.isEmpty) return true;

    String normalize(dynamic v) {
      final s = (v ?? '').toString().trim().toLowerCase();
      if (const {'true', 'yes', 'y', '1', 'on'}.contains(s)) return 'true';
      if (const {'false', 'no', 'n', '0', 'off'}.contains(s)) return 'false';
      return s;
    }

    return showConditions.any((c) {
      final currentVal = formValues[c.triggerFieldId];
      if (currentVal is List) {
        final expected = normalize(c.triggerValue);
        return currentVal.any((v) => normalize(v) == expected);
      }
      return normalize(currentVal) == normalize(c.triggerValue);
    });
  }
}

// Form section definition
class FormSection {
  final String sectionId;
  final String templateId;
  final String sectionName;
  final String? sectionDesc;
  final int sectionOrder;
  final bool isCollapsible;
  final List<FormFieldModel> fields;

  const FormSection({
    required this.sectionId,
    required this.templateId,
    required this.sectionName,
    this.sectionDesc,
    this.sectionOrder = 0,
    this.isCollapsible = false,
    this.fields = const [],
  });

  factory FormSection.fromMap(
    Map<String, dynamic> m,
    List<FormFieldModel> fields,
  ) => FormSection(
    sectionId: m['section_id'] as String,
    templateId: m['template_id'] as String,
    sectionName: m['section_name'] as String,
    sectionDesc: m['section_desc'] as String?,
    sectionOrder: (m['section_order'] as int?) ?? 0,
    isCollapsible: (m['is_collapsible'] as bool?) ?? false,
    fields: fields..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder)),
  );
}

// Form template definition
class FormTemplate {
  final String templateId;
  final String formName;
  final String? formDesc;
  final bool isActive;
  final String? formCode;
  final String? referencePrefix;
  final String referenceFormat;
  final bool requiresReference;
  final List<FormSection> sections;

  const FormTemplate({
    required this.templateId,
    required this.formName,
    this.formDesc,
    this.isActive = true,
    this.formCode,
    this.referencePrefix,
    this.referenceFormat = '{FORMCODE}-{YYYY}-{MM}-{####}',
    this.requiresReference = true,
    this.sections = const [],
  });

  // Flat list of all fields across all sections, ordered by section then field
  List<FormFieldModel> get allFields =>
      sections.expand((s) => s.fields).toList();

  // Look up a field by its field_name key
  FormFieldModel? fieldByName(String name) {
    try {
      return allFields.firstWhere((f) => f.fieldName == name);
    } catch (_) {
      return null;
    }
  }

  factory FormTemplate.fromMap(Map<String, dynamic> m) {
    final rawSections = (m['form_sections'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final rawFields = (m['form_fields'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((f) {
          final vr = f['validation_rules'] as Map<String, dynamic>?;
          return vr == null || vr['_archived'] != true;
        })
        .toList();

    final allParsed = rawFields.map((f) => FormFieldModel.fromMap(f)).toList();

    // Separate child column-definition fields from top-level fields
    final childFields = allParsed
        .where((f) => f.parentFieldId != null)
        .toList();
    final topLevelFields = allParsed
        .where((f) => f.parentFieldId == null)
        .toList();

    // Group children by parent ID
    final childrenByParent = <String, List<FormFieldModel>>{};
    for (final child in childFields) {
      childrenByParent.putIfAbsent(child.parentFieldId!, () => []).add(child);
    }

    // Attach columns to memberTable and familyTable fields
    final assembledWithColumns = topLevelFields.map((f) {
      if ((f.fieldType == FormFieldType.memberTable ||
              f.fieldType == FormFieldType.familyTable) &&
          childrenByParent.containsKey(f.fieldId)) {
        final cols = childrenByParent[f.fieldId]!
          ..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder));
        return f.copyWith(columns: cols);
      }
      return f;
    }).toList();

    // Defensive dedupe: duplicate field_name keys cause shared controller state
    // and can let computed outputs overwrite unrelated inputs.
    final seenFieldNames = <String>{};
    final assembledFields = assembledWithColumns.map((f) {
      final key = f.fieldName.trim();
      if (key.isEmpty) return f;
      if (!seenFieldNames.contains(key)) {
        seenFieldNames.add(key);
        return f;
      }

      final suffix = f.fieldId.length >= 8
          ? f.fieldId.substring(0, 8)
          : f.fieldId;
      final newKey = '${key}_$suffix';
      seenFieldNames.add(newKey);
      return f.copyWith(fieldName: newKey);
    }).toList();

    final sections = rawSections.map((s) {
      final sectionFields = assembledFields
          .where((f) => f.sectionId == s['section_id'])
          .toList();
      return FormSection.fromMap(s, sectionFields);
    }).toList()..sort((a, b) => a.sectionOrder.compareTo(b.sectionOrder));

    return FormTemplate(
      templateId: m['template_id'] as String,
      formName: m['form_name'] as String,
      formDesc: m['form_desc'] as String?,
      isActive: (m['is_active'] as bool?) ?? true,
      formCode: m['form_code'] as String?,
      referencePrefix: m['reference_prefix'] as String?,
      referenceFormat:
          (m['reference_format'] as String?)?.trim().isNotEmpty == true
          ? m['reference_format'] as String
          : '{FORMCODE}-{YYYY}-{MM}-{####}',
      requiresReference: (m['requires_reference'] as bool?) ?? true,
      sections: sections,
    );
  }
}
