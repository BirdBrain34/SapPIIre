import 'package:flutter/material.dart';

import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/form_builder_service.dart';
import 'package:sappiire/web/controllers/form_builder_controller.dart' as base;

export 'package:sappiire/web/controllers/form_builder_controller.dart';

const systemBlocks =
    <
      FormFieldType,
      ({String label, String fieldName, String desc, IconData icon})
    >{
      FormFieldType.membershipGroup: (
        label: 'Membership Group',
        fieldName: 'membership_group',
        desc: 'Solo Parent, PWD, 4Ps, PHIC checkboxes',
        icon: Icons.group_outlined,
      ),
      FormFieldType.computed: (
        label: 'Computed Field',
        fieldName: 'computed_field',
        desc: 'Auto-calculated value (income, expenses, etc.)',
        icon: Icons.calculate_outlined,
      ),
      FormFieldType.signature: (
        label: 'Signature',
        fieldName: 'signature',
        desc:
            'Applicant draws their signature on screen. Saved as a base64 image in field values.',
        icon: Icons.draw_outlined,
      ),
    };

const familyTableCoreColumns =
    <({String label, String fieldName, String dbMapKey, FormFieldType type})>[
      (
        label: 'Name',
        fieldName: 'name',
        dbMapKey: 'name',
        type: FormFieldType.text,
      ),
      (
        label: 'Relationship',
        fieldName: 'relationship_of_relative',
        dbMapKey: 'relationship_of_relative',
        type: FormFieldType.text,
      ),
      (
        label: 'Birthdate',
        fieldName: 'birthdate',
        dbMapKey: 'birthdate',
        type: FormFieldType.date,
      ),
      (
        label: 'Age',
        fieldName: 'age',
        dbMapKey: 'age',
        type: FormFieldType.number,
      ),
      (
        label: 'Sex',
        fieldName: 'gender',
        dbMapKey: 'gender',
        type: FormFieldType.dropdown,
      ),
      (
        label: 'Civil Status',
        fieldName: 'civil_status',
        dbMapKey: 'civil_status',
        type: FormFieldType.dropdown,
      ),
      (
        label: 'Education',
        fieldName: 'education',
        dbMapKey: 'education',
        type: FormFieldType.dropdown,
      ),
      (
        label: 'Occupation',
        fieldName: 'occupation',
        dbMapKey: 'occupation',
        type: FormFieldType.text,
      ),
      (
        label: 'Allowance (₱)',
        fieldName: 'allowance',
        dbMapKey: 'allowance',
        type: FormFieldType.number,
      ),
    ];

// ---------------------------------------------------------------
// Exact set of columns that exist in form_fields table.
// Any key NOT in this set will be stripped before upsert to
// prevent "record has no field X" errors from DB triggers.
// ---------------------------------------------------------------
const _allowedFieldKeys = <String>{
  'field_id',
  'template_id',
  'section_id',
  'field_name',
  'field_label',
  'field_type',
  'is_required',
  'validation_rules',
  'field_order',
  'parent_field_id',
  'canonical_field_key',
};

// ---------------------------------------------------------------
// Exact set of columns that exist in form_sections table.
// ---------------------------------------------------------------
const _allowedSectionKeys = <String>{
  'section_id',
  'template_id',
  'section_name',
  'section_desc',
  'section_order',
  'is_collapsible',
};

/// Strip any key that isn't a real DB column before sending to Supabase.
/// This prevents "record 'new' has no field 'placeholder'" style errors
/// caused by DB triggers referencing columns that were removed from the schema.
Map<String, dynamic> _sanitizeFieldPayload(Map<String, dynamic> raw) {
  return {
    for (final entry in raw.entries)
      if (_allowedFieldKeys.contains(entry.key)) entry.key: entry.value,
  };
}

Map<String, dynamic> _sanitizeSectionPayload(Map<String, dynamic> raw) {
  return {
    for (final entry in raw.entries)
      if (_allowedSectionKeys.contains(entry.key)) entry.key: entry.value,
  };
}

class FormBuilderScreenController extends ChangeNotifier {
  FormBuilderScreenController({FormBuilderService? service})
    : _service = service ?? FormBuilderService();

  final FormBuilderService _service;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _disposed = false;

  String cswdId = '';
  String role = '';
  String displayName = '';
  void Function(String message, Color backgroundColor)? showSnackBar;
  void Function(base.BuilderField field)? onShowSumColumnPicker;

  List<Map<String, dynamic>> templates = [];
  bool isLoadingList = true;
  base.TemplateListFilter templateListFilter = base.TemplateListFilter.all;

  String? activeTemplateId;
  String formName = '';
  String formDesc = '';
  String formCode = '';
  String referencePrefix = '';
  String referenceFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
  bool requiresReference = true;
  String formStatus = 'draft';
  List<base.BuilderSection> sections = [];
  bool popupEnabled = false;
  String popupSubtitle = '';
  String popupDescription = '';

  int? activeSectionIdx;
  int? activeFieldIdx;

  bool isSaving = false;
  bool isLoadingTemplate = false;
  bool hasUnsavedChanges = false;
  List<({String key, String label})> availableCanonicalKeys = const [];
  bool isLoadingCanonicalKeys = false;

  String? get lastSaveError => _service.lastSaveError;
  String? get lastActionError => _service.lastActionError;

  TextEditingController ctrl(String key, String initial) {
    return _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  FocusNode focusNode(String key) {
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode(debugLabel: key);
      node.addListener(() {
        if (!node.hasFocus) {
          // Only mark changed on blur — do NOT call notifyListeners on
          // every keystroke.  Text fields write directly to model objects
          // (field.label = value) without needing a full rebuild.
          hasUnsavedChanges = true;
        }
      });
      return node;
    });
  }

  void clearCtrls() {
    for (final controller in _ctrls.values) {
      controller.dispose();
    }
    _ctrls.clear();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  /// Mark that the form has unsaved changes and notify listeners.
  ///
  /// Call this for STRUCTURAL changes only (add/remove field, type change,
  /// reorder, toggle switch, etc.).  Pure text edits (onChanged in a
  /// TextField) should just write to the model object directly and NOT
  /// call markChanged() — that avoids scroll-disrupting rebuilds on every
  /// keystroke.
  void markChanged() {
    if (_disposed) return;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void selectSection(int sectionIndex) {
    activeSectionIdx = sectionIndex;
    activeFieldIdx = null;
    markChanged();
  }

  void selectField(int sectionIndex, int fieldIndex) {
    activeSectionIdx = sectionIndex;
    activeFieldIdx = fieldIndex;
    markChanged();
  }

  String sanitizeCode(String input) => base.sanitizeCode(input);

  List<String> referenceFormatParts() =>
      base.referenceFormatParts(referenceFormat);

  void appendReferenceToken(String token) {
    referenceFormat = base.appendReferenceToken(referenceFormat, token);
    markChanged();
  }

  void appendReferenceSeparator(String separator) {
    referenceFormat = base.appendReferenceSeparator(referenceFormat, separator);
    markChanged();
  }

  void removeReferencePartAt(int index) {
    referenceFormat = base.removeReferencePartAt(referenceFormat, index);
    markChanged();
  }

  String referencePreview() => base.referencePreview(
    referenceFormat: referenceFormat,
    referencePrefix: referencePrefix,
    formCode: formCode,
  );

  List<String> formulaTokens(base.BuilderField field) =>
      field.formula.trim().isEmpty
      ? []
      : field.formula.trim().split(RegExp(r'\s+'));

  void appendFormulaToken(base.BuilderField field, String token) {
    final tokens = formulaTokens(field);
    tokens.add(token);
    field.formula = tokens.join(' ');
    markChanged();
  }

  void removeFormulaToken(base.BuilderField field, int index) {
    final tokens = formulaTokens(field);
    tokens.removeAt(index);
    field.formula = tokens.join(' ');
    markChanged();
  }

  bool get canPublish => sections.any((section) => section.fields.isNotEmpty);

  Future<void> loadTemplateList() async {
    isLoadingList = true;
    notifyListeners();
    final fetchedTemplates = await _service.fetchAllTemplates();
    if (_disposed) return;
    templates = fetchedTemplates;
    isLoadingList = false;
    notifyListeners();
  }

  Future<void> loadCanonicalKeys() async {
    isLoadingCanonicalKeys = true;
    notifyListeners();
    try {
      final dbKeys = (await _service.fetchCanonicalFieldKeys()).toSet();

      for (final standard in base.standardProfileCanonicalKeys) {
        dbKeys.add(standard.key);
      }

      final labelMap = {
        for (final standard in base.standardProfileCanonicalKeys)
          standard.key: standard.label,
      };
      final merged = dbKeys.map((key) {
        return (key: key, label: labelMap[key] ?? key);
      }).toList()..sort((a, b) => a.key.compareTo(b.key));

      if (_disposed) return;
      availableCanonicalKeys = merged;
      isLoadingCanonicalKeys = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[FormBuilderScreenController/_loadCanonicalKeys] Error: $e');
      if (_disposed) return;
      availableCanonicalKeys = List.of(base.standardProfileCanonicalKeys);
      isLoadingCanonicalKeys = false;
      notifyListeners();
    }
  }

  Future<void> loadTemplate(String templateId) async {
    isLoadingTemplate = true;
    notifyListeners();
    clearCtrls();

    final data = await _service.fetchTemplateWithStructure(templateId);
    if (_disposed) return;
    if (data == null) {
      isLoadingTemplate = false;
      notifyListeners();
      return;
    }

    final rawSections =
        (data['form_sections'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => ((a['section_order'] as int?) ?? 0).compareTo(
              (b['section_order'] as int?) ?? 0,
            ),
          );
    final rawFields = (data['form_fields'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((field) {
          final validationRules =
              field['validation_rules'] as Map<String, dynamic>?;
          return validationRules == null ||
              validationRules['_archived'] != true;
        })
        .toList();

    final childFields = rawFields
        .where((field) => field['parent_field_id'] != null)
        .toList();
    final topLevelFields = rawFields
        .where((field) => field['parent_field_id'] == null)
        .toList();

    final childrenByParent = <String, List<Map<String, dynamic>>>{};
    for (final childField in childFields) {
      final parentId = childField['parent_field_id'] as String;
      childrenByParent.putIfAbsent(parentId, () => []).add(childField);
    }

    final loadedSections = rawSections.map((section) {
      final sectionFields =
          topLevelFields
              .where((field) => field['section_id'] == section['section_id'])
              .toList()
            ..sort(
              (a, b) => ((a['field_order'] as int?) ?? 0).compareTo(
                (b['field_order'] as int?) ?? 0,
              ),
            );

      return base.BuilderSection(
        id: section['section_id'] as String,
        name: section['section_name'] as String? ?? 'Untitled Section',
        description: section['section_desc'] as String?,
        order: (section['section_order'] as int?) ?? 0,
        fields: sectionFields.map((field) {
          final rawOptions =
              (field['form_field_options'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>()
                ..sort(
                  (a, b) => ((a['option_order'] as int?) ?? 0).compareTo(
                    (b['option_order'] as int?) ?? 0,
                  ),
                );

          List<base.BuilderColumn> columns = [];
          final fieldId = field['field_id'] as String;
          final fieldType = field['field_type'] as String? ?? '';
          if ((fieldType == 'member_table' || fieldType == 'family_table') &&
              childrenByParent.containsKey(fieldId)) {
            final childList = childrenByParent[fieldId]!
              ..sort(
                (a, b) => ((a['field_order'] as int?) ?? 0).compareTo(
                  (b['field_order'] as int?) ?? 0,
                ),
              );
            columns = childList.map((childField) {
              final childOptions =
                  (childField['form_field_options'] as List<dynamic>? ?? [])
                      .cast<Map<String, dynamic>>()
                    ..sort(
                      (a, b) => ((a['option_order'] as int?) ?? 0).compareTo(
                        (b['option_order'] as int?) ?? 0,
                      ),
                    );
              final childValidation =
                  childField['validation_rules'] as Map<String, dynamic>?;
              final ageFromColumn =
                  (childValidation?['age_from_column'] as String?)?.trim();
              return base.BuilderColumn(
                id: childField['field_id'] as String,
                label: childField['field_label'] as String? ?? '',
                fieldName: childField['field_name'] as String? ?? '',
                type: FormFieldType.fromString(
                  childField['field_type'] as String? ?? 'text',
                ),
                order: (childField['field_order'] as int?) ?? 0,
                dbMapKey: childValidation?['db_map_key'] as String?,
                ageFromColumnId:
                    (ageFromColumn != null && ageFromColumn.isNotEmpty)
                    ? ageFromColumn
                    : null,
                options: childOptions
                    .map(
                      (option) => base.BuilderOption(
                        id: option['option_id'] as String,
                        label: option['option_label'] as String? ?? '',
                        order: (option['option_order'] as int?) ?? 0,
                      ),
                    )
                    .toList(),
              );
            }).toList();
          }

          final validationRules =
              field['validation_rules'] as Map<String, dynamic>?;
          final ageFromField = (validationRules?['age_from_field'] as String?)
              ?.trim();
          final rawConditions =
              (field['form_field_conditions'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
          Map<String, dynamic>? showCondition;
          for (final condition in rawConditions) {
            if ((condition['action'] as String? ?? 'show') == 'show') {
              showCondition = condition;
              break;
            }
          }
          showCondition ??= rawConditions.isNotEmpty
              ? rawConditions.first
              : null;

          return base.BuilderField(
            id: field['field_id'] as String,
            label: field['field_label'] as String? ?? '',
            fieldName: field['field_name'] as String? ?? '',
            type: FormFieldType.fromString(
              field['field_type'] as String? ?? 'text',
            ),
            isRequired: (field['is_required'] as bool?) ?? false,
            canonicalFieldKey: field['field_type'] == 'signature'
                ? 'signature'
                : field['canonical_field_key'] as String?,
            order: (field['field_order'] as int?) ?? 0,
            columns: columns,
            formula: (validationRules?['formula'] as String?) ?? '',
            ageFromFieldId: (ageFromField != null && ageFromField.isNotEmpty)
                ? ageFromField
                : null,
            condition: base.BuilderCondition(
              triggerFieldId:
                  (showCondition?['trigger_field_id'] as String?) ?? '',
              triggerValue: (showCondition?['trigger_value'] as String?) ?? '',
              action: (showCondition?['action'] as String?) ?? 'show',
            ),
            options: rawOptions
                .map(
                  (option) => base.BuilderOption(
                    id: option['option_id'] as String,
                    label: option['option_label'] as String? ?? '',
                    order: (option['option_order'] as int?) ?? 0,
                  ),
                )
                .toList(),
          );
        }).toList(),
      );
    }).toList();

    activeTemplateId = templateId;
    formName = data['form_name'] as String? ?? 'Untitled Form';
    formDesc = data['form_desc'] as String? ?? '';
    formCode = sanitizeCode(
      data['form_code'] as String? ?? base.slugify(formName).toUpperCase(),
    );
    referencePrefix = sanitizeCode(
      data['reference_prefix'] as String? ?? formCode,
    );
    referenceFormat =
        (data['reference_format'] as String?)?.trim().isNotEmpty == true
        ? data['reference_format'] as String
        : '{FORMCODE}-{YYYY}-{MM}-{####}';
    requiresReference = (data['requires_reference'] as bool?) ?? true;
    formStatus = data['status'] as String? ?? 'draft';
    sections = loadedSections;
    popupEnabled = (data['popup_enabled'] as bool?) ?? false;
    popupSubtitle = data['popup_subtitle'] as String? ?? '';
    popupDescription = data['popup_description'] as String? ?? '';
    activeSectionIdx = null;
    activeFieldIdx = null;
    hasUnsavedChanges = false;
    isLoadingTemplate = false;
    notifyListeners();
  }

  Future<void> createNewTemplate() async {
    const defaultFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
    // Use a UUID-derived code so it is guaranteed unique in form_templates.
    final uniqueCode =
        'FORM${base.generateUuid().substring(0, 6).toUpperCase()}';
    final id = await _service.createTemplate(
      formName: 'Untitled Form',
      formDesc: '',
      createdBy: cswdId,
      formCode: uniqueCode,
      referencePrefix: uniqueCode,
      referenceFormat: defaultFormat,
      requiresReference: true,
    );
    if (id == null || _disposed) return;
    await loadTemplateList();
    clearCtrls();

    activeTemplateId = id;
    formName = 'Untitled Form';
    formDesc = '';
    // Reflect the actual code persisted to the DB so Save doesn't try to
    // re-use a hardcoded code that might already exist.
    formCode = uniqueCode;
    referencePrefix = uniqueCode;
    referenceFormat = defaultFormat;
    requiresReference = true;
    formStatus = 'draft';
    popupEnabled = false;
    popupSubtitle = '';
    popupDescription = '';
    sections = [
      base.BuilderSection(
        name: 'Section 1',
        order: 0,
        fields: [base.BuilderField(label: 'Question 1', order: 0)],
      ),
    ];
    activeSectionIdx = 0;
    activeFieldIdx = 0;
    hasUnsavedChanges = true;
    isLoadingTemplate = false;
    notifyListeners();
  }

  Future<bool> saveTemplate() async {
    if (activeTemplateId == null) return false;
    isSaving = true;
    notifyListeners();

    final dbSections = <Map<String, dynamic>>[];
    final dbFields = <Map<String, dynamic>>[];
    final dbOptions = <Map<String, dynamic>>[];
    final dbConditions = <Map<String, dynamic>>[];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];

      // Sanitize section payload to only known columns.
      dbSections.add(_sanitizeSectionPayload({
        'section_id': section.id,
        'template_id': activeTemplateId,
        'section_name': section.name,
        'section_desc': section.description,
        'section_order': sectionIndex,
        'is_collapsible': false,
      }));

      for (
        var fieldIndex = 0;
        fieldIndex < section.fields.length;
        fieldIndex++
      ) {
        final field = section.fields[fieldIndex];
        final validationRules = <String, dynamic>{};
        if (field.type == FormFieldType.computed && field.formula.isNotEmpty) {
          validationRules['formula'] = field.formula;
        }
        if (field.type == FormFieldType.number &&
            field.ageFromFieldId != null &&
            field.ageFromFieldId!.isNotEmpty) {
          validationRules['age_from_field'] = field.ageFromFieldId;
        }

        // Build the field row then sanitize — strips any key that
        // isn't a real column in form_fields (e.g. 'placeholder').
        final rawFieldRow = <String, dynamic>{
          'field_id': field.id,
          'template_id': activeTemplateId,
          'section_id': section.id,
          'field_name': field.fieldName,
          'field_label': field.label,
          'field_type': field.type.toDbString(),
          'is_required': field.isRequired,
          'canonical_field_key': field.type == FormFieldType.signature
              ? 'signature'
              : field.canonicalFieldKey,
          'field_order': fieldIndex,
          if (validationRules.isNotEmpty) 'validation_rules': validationRules,
        };
        dbFields.add(_sanitizeFieldPayload(rawFieldRow));

        if (field.type == FormFieldType.memberTable ||
            field.type == FormFieldType.familyTable) {
          for (
            var columnIndex = 0;
            columnIndex < field.columns.length;
            columnIndex++
          ) {
            final column = field.columns[columnIndex];
            final columnValidationRules = <String, dynamic>{};
            if (column.dbMapKey != null) {
              columnValidationRules['db_map_key'] = column.dbMapKey;
            }
            if (column.type == FormFieldType.number &&
                column.ageFromColumnId != null &&
                column.ageFromColumnId!.isNotEmpty) {
              columnValidationRules['age_from_column'] = column.ageFromColumnId;
            }

            final rawColumnRow = <String, dynamic>{
              'field_id': column.id,
              'template_id': activeTemplateId,
              'section_id': section.id,
              'field_name': column.fieldName,
              'field_label': column.label,
              'field_type': column.type.toDbString(),
              'is_required': false,
              'field_order': columnIndex,
              'parent_field_id': field.id,
              if (columnValidationRules.isNotEmpty)
                'validation_rules': columnValidationRules,
            };
            dbFields.add(_sanitizeFieldPayload(rawColumnRow));

            if (column.type == FormFieldType.dropdown) {
              for (
                var optionIndex = 0;
                optionIndex < column.options.length;
                optionIndex++
              ) {
                final option = column.options[optionIndex];
                dbOptions.add({
                  'option_id': option.id,
                  'field_id': column.id,
                  'option_value': base.slugify(option.label),
                  'option_label': option.label,
                  'option_order': optionIndex,
                  'is_default': false,
                });
              }
            }
          }
        }

        if (field.hasOptions) {
          for (
            var optionIndex = 0;
            optionIndex < field.options.length;
            optionIndex++
          ) {
            final option = field.options[optionIndex];
            dbOptions.add({
              'option_id': option.id,
              'field_id': field.id,
              'option_value': base.slugify(option.label),
              'option_label': option.label,
              'option_order': optionIndex,
              'is_default': false,
            });
          }
        }

        if (field.condition.triggerFieldId.isNotEmpty &&
            field.condition.triggerValue.isNotEmpty) {
          dbConditions.add({
            'field_id': field.id,
            'trigger_field_id': field.condition.triggerFieldId,
            'trigger_value': field.condition.triggerValue,
            'action': field.condition.action,
          });
        }
      }
    }

    final normalizedCode = sanitizeCode(
      formCode.trim().isNotEmpty
          ? formCode
          : base.slugify(formName).toUpperCase(),
    );
    final normalizedPrefix = sanitizeCode(
      referencePrefix.trim().isNotEmpty ? referencePrefix : normalizedCode,
    );

    final success = await _service.saveTemplateStructure(
      templateId: activeTemplateId!,
      formName: formName,
      formDesc: formDesc,
      formCode: normalizedCode,
      referencePrefix: normalizedPrefix,
      referenceFormat: referenceFormat.trim().isNotEmpty
          ? referenceFormat.trim()
          : '{FORMCODE}-{YYYY}-{MM}-{####}',
      requiresReference: requiresReference,
      sections: dbSections,
      fields: dbFields,
      options: dbOptions,
      conditions: dbConditions,
    );

    if (success) {
      try {
        await _service.savePopupMetadata(
          templateId: activeTemplateId!,
          popupEnabled: popupEnabled,
          popupSubtitle: popupSubtitle,
          popupDescription: popupDescription,
        );
      } catch (e) {
        debugPrint('[FormBuilderScreenController/savePopupMetadata] Error: $e');
      }
    }

    if (_disposed) return success;
    isSaving = false;
    if (success) hasUnsavedChanges = false;
    notifyListeners();
    await loadTemplateList();
    return success;
  }

  Future<bool> publishTemplate() async {
    if (activeTemplateId == null) return false;

    final success = await _service.publishTemplate(activeTemplateId!);
    if (_disposed) return success;
    if (success) {
      formStatus = 'published';
      notifyListeners();
      await loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplatePublished,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: cswdId,
        actorName: displayName,
        actorRole: role,
        targetType: 'form_template',
        targetId: activeTemplateId,
        targetLabel: formName,
      );
    }
    return success;
  }

  Future<bool> pushToMobile() async {
    if (activeTemplateId == null) return false;

    final success = await _service.pushToMobile(activeTemplateId!);
    if (_disposed) return success;
    if (success) {
      formStatus = 'pushed_to_mobile';
      notifyListeners();
      await loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplatePushed,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: cswdId,
        actorName: displayName,
        actorRole: role,
        targetType: 'form_template',
        targetId: activeTemplateId,
        targetLabel: formName,
      );
    }
    return success;
  }

  Future<bool> archiveTemplate() async {
    if (activeTemplateId == null) return false;

    final success = await _service.archiveTemplate(activeTemplateId!);
    if (_disposed) return success;
    if (success) {
      formStatus = 'archived';
      notifyListeners();
      await loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplateArchived,
        category: kCategoryTemplate,
        severity: kSeverityWarning,
        actorId: cswdId,
        actorName: displayName,
        actorRole: role,
        targetType: 'form_template',
        targetId: activeTemplateId,
        targetLabel: formName,
      );
    }
    return success;
  }

  Future<bool> restoreTemplate() async {
    if (activeTemplateId == null) return false;

    final success = await _service.restoreTemplate(activeTemplateId!);
    if (_disposed) return success;
    if (success) {
      formStatus = 'draft';
      notifyListeners();
      await loadTemplateList();
    }
    return success;
  }

  Future<bool> unpublishTemplate() async {
    if (activeTemplateId == null) return false;

    final success = await _service.unpublishTemplate(activeTemplateId!);
    if (_disposed) return success;
    if (success) {
      formStatus = 'draft';
      notifyListeners();
      await loadTemplateList();
    }
    return success;
  }

  void addSection() {
    sections.add(
      base.BuilderSection(
        name: 'Section ${sections.length + 1}',
        order: sections.length,
      ),
    );
    markChanged();
  }

  void addField(int sectionIndex) {
    final section = sections[sectionIndex];
    section.fields.add(
      base.BuilderField(
        label: 'Question ${section.fields.length + 1}',
        order: section.fields.length,
      ),
    );
    activeSectionIdx = sectionIndex;
    activeFieldIdx = section.fields.length - 1;
    markChanged();
  }

  void addSystemField(int sectionIndex, FormFieldType type) {
    final block = systemBlocks[type];
    if (block == null) return;
    final section = sections[sectionIndex];

    final allFields = sections.expand((section) => section.fields);
    if (const {
          FormFieldType.membershipGroup,
          FormFieldType.signature,
        }.contains(type) &&
        allFields.any((field) => field.type == type)) {
      showSnackBar?.call(
        'A "${block.label}" block already exists in this form.',
        Colors.orange.shade700,
      );
      return;
    }

    List<base.BuilderColumn> columns = [];
    if (type == FormFieldType.familyTable) {
      columns = familyTableCoreColumns
          .asMap()
          .entries
          .map(
            (entry) => base.BuilderColumn(
              label: entry.value.label,
              fieldName: entry.value.fieldName,
              type: entry.value.type,
              order: entry.key,
              dbMapKey: entry.value.dbMapKey,
            ),
          )
          .toList();
    }

    final generatedFieldName = type == FormFieldType.computed
        ? 'computed_${base.generateUuid().substring(0, 8)}'
        : block.fieldName;
    section.fields.add(
      base.BuilderField(
        label: block.label,
        fieldName: generatedFieldName,
        type: type,
        isRequired: false,
        canonicalFieldKey: type == FormFieldType.signature ? 'signature' : null,
        order: section.fields.length,
        options: [],
        columns: columns,
      ),
    );
    activeSectionIdx = sectionIndex;
    activeFieldIdx = section.fields.length - 1;
    markChanged();
  }

  void removeField(int sectionIndex, int fieldIndex) {
    sections[sectionIndex].fields.removeAt(fieldIndex);
    activeFieldIdx = null;
    markChanged();
  }

  void removeSection(int sectionIndex) {
    sections.removeAt(sectionIndex);
    activeSectionIdx = null;
    activeFieldIdx = null;
    markChanged();
  }

  void duplicateField(int sectionIndex, int fieldIndex) {
    final source = sections[sectionIndex].fields[fieldIndex];
    sections[sectionIndex].fields.insert(
      fieldIndex + 1,
      base.BuilderField(
        label: '${source.label} (copy)',
        type: source.type,
        isRequired: source.isRequired,
        canonicalFieldKey: source.canonicalFieldKey,
        ageFromFieldId: source.ageFromFieldId,
        order: fieldIndex + 1,
        options: source.options
            .map((option) => base.BuilderOption(label: option.label))
            .toList(),
        condition: base.BuilderCondition(
          triggerFieldId: source.condition.triggerFieldId,
          triggerValue: source.condition.triggerValue,
          action: source.condition.action,
        ),
      ),
    );
    activeFieldIdx = fieldIndex + 1;
    markChanged();
  }

  void moveField(int sectionIndex, int fieldIndex, int direction) {
    final nextIndex = fieldIndex + direction;
    if (nextIndex < 0 || nextIndex >= sections[sectionIndex].fields.length) {
      return;
    }
    final field = sections[sectionIndex].fields.removeAt(fieldIndex);
    sections[sectionIndex].fields.insert(nextIndex, field);
    activeFieldIdx = nextIndex;
    markChanged();
  }

  void moveSection(int sectionIndex, int direction) {
    final nextIndex = sectionIndex + direction;
    if (nextIndex < 0 || nextIndex >= sections.length) return;
    final section = sections.removeAt(sectionIndex);
    sections.insert(nextIndex, section);
    activeSectionIdx = nextIndex;
    markChanged();
  }

  void moveColumn(base.BuilderField field, int columnIndex, int direction) {
    final nextIndex = columnIndex + direction;
    if (nextIndex < 0 || nextIndex >= field.columns.length) return;
    final column = field.columns.removeAt(columnIndex);
    field.columns.insert(nextIndex, column);
    markChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    clearCtrls();
    super.dispose();
  }
}