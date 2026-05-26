import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/models/form_template_models.dart';

class FormStateController extends ChangeNotifier {
  final FormTemplate template;

  // Store the current field values keyed by field name.
  final Map<String, dynamic> _values = {};

  // Keep per-field listeners so a single change does not repaint the whole form.
  final Map<String, ValueNotifier<dynamic>> _fieldNotifiers = {};

  // Track text controllers for text, number, date, and computed fields.
  final Map<String, TextEditingController> textControllers = {};

  // Debounce formula recalculation while the user is still typing.
  Timer? _recomputeDebounce;

  // Store the state for grouped and computed field types.
  Map<String, bool> membershipData = {
    'solo_parent': false,
    'pwd': false,
    'four_ps_member': false,
    'phic_member': false,
  };
  List<Map<String, dynamic>> familyMembers = [];
  List<Map<String, dynamic>> supportingFamily = [];
  bool hasSupport = false;
  String? housingStatus;
  String? signatureBase64;
  List<Offset>? signaturePoints;
  bool signatureIsProcessing = false;

  // Store rows for member table fields.
  Map<String, List<Map<String, dynamic>>> memberTableData = {};

  // Track which fields are selected for sharing on mobile.
  final Map<String, bool> fieldChecks = {};
  bool selectAll = false;

  FormStateController({required this.template}) {
    _initControllers();
  }

  void _initControllers() {
    for (final field in template.allFields) {
      switch (field.fieldType) {
        case FormFieldType.text:
        case FormFieldType.conditional:
        case FormFieldType.date:
        case FormFieldType.number:
        case FormFieldType.computed:
          textControllers[field.fieldName] = TextEditingController();
          _initFieldNotifier(field.fieldName, null);
          fieldChecks[field.fieldName] = false;
          break;
        case FormFieldType.dropdown:
        case FormFieldType.radio:
        case FormFieldType.checkbox:
        case FormFieldType.boolean:
          _initFieldNotifier(field.fieldName, null);
          fieldChecks[field.fieldName] = false;
          break;
        case FormFieldType.familyTable:
          fieldChecks['Family Composition'] = false;
          break;
        case FormFieldType.signature:
          fieldChecks['Signature'] = false;
          break;
        case FormFieldType.membershipGroup:
          fieldChecks['Membership Group'] = false;
          break;
        case FormFieldType.supportingFamilyTable:
          break;
        case FormFieldType.memberTable:
          memberTableData[field.fieldName] = [];
          fieldChecks[field.fieldLabel] = false;
          break;
        default:
          break;
      }
    }
  }

  void _initFieldNotifier(String fieldName, dynamic initialValue) {
    if (!_fieldNotifiers.containsKey(fieldName)) {
      _fieldNotifiers[fieldName] = ValueNotifier(initialValue);
    }
  }

  ValueNotifier<dynamic>? getFieldNotifier(String fieldName) =>
      _fieldNotifiers[fieldName];

  dynamic getValue(String fieldName) => _values[fieldName];

  bool _truthy(dynamic v) => v == true || v?.toString().toLowerCase() == 'true';

  String _normalizeSupportKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  bool isSupportBooleanField(FormFieldModel field) {
    if (field.fieldType != FormFieldType.boolean) return false;

    final candidates = <String>{
      field.fieldName,
      field.fieldLabel,
      field.canonicalFieldKey ?? '',
      field.autofillSource ?? '',
      (field.validationRules?['db_map_key'] ?? '').toString(),
    };

    for (final c in candidates) {
      final n = _normalizeSupportKey(c);
      if (n == 'has_support' ||
          n == 'support' ||
          n.contains('sumusuporta') ||
          (n.contains('support') && n.contains('family'))) {
        return true;
      }
    }

    return false;
  }

  FormFieldModel? _supportBooleanField() {
    for (final f in template.allFields) {
      if (isSupportBooleanField(f)) return f;
    }
    return null;
  }

  void setValue(String fieldName, dynamic value, {bool notify = true}) {
    _values[fieldName] = value;
    final supportField = _supportBooleanField();
    if (supportField != null && supportField.fieldName == fieldName) {
      hasSupport = _truthy(value);
    }
    _fieldNotifiers[fieldName]?.value = value; // Keep the field-specific notifier in sync.

    if (textControllers.containsKey(fieldName)) {
      final ctrl = textControllers[fieldName]!;
      final strVal = value?.toString() ?? '';
      if (ctrl.text != strVal) ctrl.text = strVal;
    }

    _syncAgeFromBirthDate(changedFieldName: fieldName);

    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(
      const Duration(milliseconds: 150),
      _recomputeFields,
    );

    // Only structural changes and computed cascades need a full repaint.
    if (notify || _hasStructuralDependencies(fieldName)) {
      notifyListeners();
    }
  }

  bool isAgeAutoField(FormFieldModel field) {
    if (_ageFromFieldId(field) != null) return true;

    final fieldName = field.fieldName.trim().toLowerCase();
    final label = field.fieldLabel.trim().toLowerCase();
    final canonical = (field.canonicalFieldKey ?? '').trim().toLowerCase();
    final autofill = (field.autofillSource ?? '').trim().toLowerCase();
    final dbMapKey = (field.validationRules?['db_map_key'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return fieldName == 'age' ||
        label == 'age' ||
        canonical == 'age' ||
        autofill == 'age' ||
        dbMapKey == 'age';
  }

  bool _isBirthDateField(FormFieldModel field) {
    final fieldName = field.fieldName.trim().toLowerCase();
    final label = field.fieldLabel.trim().toLowerCase();
    final canonical = (field.canonicalFieldKey ?? '').trim().toLowerCase();
    final autofill = (field.autofillSource ?? '').trim().toLowerCase();
    final dbMapKey = (field.validationRules?['db_map_key'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return field.fieldType == FormFieldType.date &&
        (fieldName == 'date_of_birth' ||
            fieldName == 'birthdate' ||
            fieldName == 'dob' ||
            label == 'date of birth' ||
            label == 'birthdate' ||
            canonical == 'birth_date' ||
            autofill == 'birth_date' ||
            dbMapKey == 'birth_date');
  }

  String? _ageFromFieldId(FormFieldModel field) {
    final raw = (field.validationRules?['age_from_field'] ?? '')
        .toString()
        .trim();
    return raw.isEmpty ? null : raw;
  }

  String _fieldTextValue(String fieldName) {
    return (textControllers[fieldName]?.text ??
            _values[fieldName]?.toString() ??
            '')
        .trim();
  }

  String _computeAgeString(String dobRaw) {
    final parsedDob = _tryParseFlexibleDate(dobRaw);
    if (parsedDob == null) return '';

    final today = DateTime.now();
    var age = today.year - parsedDob.year;
    final hadBirthdayThisYear =
        today.month > parsedDob.month ||
        (today.month == parsedDob.month && today.day >= parsedDob.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age >= 0 ? age.toString() : '';
  }

  void _setFieldTextValue(String fieldName, String value) {
    final current = _fieldTextValue(fieldName);
    if (current == value) return;

    if (textControllers.containsKey(fieldName)) {
      textControllers[fieldName]!.text = value;
    }
    _values[fieldName] = value;
    _fieldNotifiers[fieldName]?.value = value;
  }

  void _syncAgeFromBirthDate({String? changedFieldName}) {
    final fields = template.allFields;
    final fieldsById = <String, FormFieldModel>{
      for (final f in fields) f.fieldId: f,
    };

    final explicitlyLinkedAgeFields = fields
        .where((f) => _ageFromFieldId(f) != null)
        .toList();

    if (explicitlyLinkedAgeFields.isNotEmpty) {
      for (final ageField in explicitlyLinkedAgeFields) {
        final dobFieldId = _ageFromFieldId(ageField);
        if (dobFieldId == null) continue;
        final dobField = fieldsById[dobFieldId];
        if (dobField == null) continue;

        if (changedFieldName != null &&
            changedFieldName != dobField.fieldName &&
            changedFieldName != ageField.fieldName) {
          continue;
        }

        final nextAge = _computeAgeString(_fieldTextValue(dobField.fieldName));
        _setFieldTextValue(ageField.fieldName, nextAge);
      }
      return;
    }

    // Keep older templates working when they do not define age_from_field.
    FormFieldModel? fallbackDobField;
    FormFieldModel? fallbackAgeField;
    for (final f in fields) {
      if (fallbackDobField == null && _isBirthDateField(f)) {
        fallbackDobField = f;
      }
      if (fallbackAgeField == null && isAgeAutoField(f)) {
        fallbackAgeField = f;
      }
      if (fallbackDobField != null && fallbackAgeField != null) break;
    }

    if (fallbackDobField == null || fallbackAgeField == null) return;
    if (changedFieldName != null &&
        changedFieldName != fallbackDobField.fieldName &&
        changedFieldName != fallbackAgeField.fieldName) {
      return;
    }

    final nextAge = _computeAgeString(
      _fieldTextValue(fallbackDobField.fieldName),
    );
    _setFieldTextValue(fallbackAgeField.fieldName, nextAge);
  }

  DateTime? _tryParseFlexibleDate(String raw) {
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw);
    if (slash != null) {
      final month = int.tryParse(slash.group(1)!);
      final day = int.tryParse(slash.group(2)!);
      final year = int.tryParse(slash.group(3)!);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dash = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (dash != null) {
      final year = int.tryParse(dash.group(1)!);
      final month = int.tryParse(dash.group(2)!);
      final day = int.tryParse(dash.group(3)!);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  /// Returns true when the changed field controls other fields' visibility.
  bool _hasStructuralDependencies(String fieldName) {
    final changedField = template.fieldByName(fieldName);
    if (changedField == null) return false;

    // Check whether any field depends on the changed field for visibility.
    for (final field in template.allFields) {
      if (field.conditions.any(
        (cond) => cond.triggerFieldId == changedField.fieldId,
      )) {
        return true;
      }
    }
    return false;
  }

  // Recompute derived values and notify listeners.
  void recomputeFromFamilyChange() {
    _recomputeFields();
    notifyListeners();
  }

  // Notify widgets that need a full form refresh.
  void notifyFormChanged() {
    notifyListeners();
  }

  // Helpers for member table fields.
  List<Map<String, dynamic>> getMemberTableRows(String fieldName) {
    return memberTableData[fieldName] ?? [];
  }

  void setMemberTableRows(String fieldName, List<Map<String, dynamic>> rows) {
    memberTableData[fieldName] = rows;
    notifyListeners();
  }

  void addMemberTableRow(String fieldName, List<FormFieldModel> columns) {
    final emptyRow = <String, dynamic>{
      for (final col in columns) col.fieldName: '',
    };
    memberTableData.putIfAbsent(fieldName, () => []);
    memberTableData[fieldName]!.add(emptyRow);
    notifyListeners();
  }

  void removeMemberTableRow(String fieldName, int index) {
    final rows = memberTableData[fieldName];
    if (rows != null && index >= 0 && index < rows.length) {
      rows.removeAt(index);
      
      // Recompute formulas because removing a row can change totals.
      _recomputeDebounce?.cancel();
      _recomputeDebounce = Timer(
        const Duration(milliseconds: 150),
        _recomputeFields,
      );
      
      notifyListeners();
    }
  }

  void updateMemberTableCell(
    String fieldName,
    int rowIndex,
    String colName,
    dynamic value,
  ) {
    final rows = memberTableData[fieldName];
    if (rows != null && rowIndex >= 0 && rowIndex < rows.length) {
      rows[rowIndex][colName] = value;
      
      // Recompute formulas because member table values feed computed fields.
      _recomputeDebounce?.cancel();
      _recomputeDebounce = Timer(
        const Duration(milliseconds: 150),
        _recomputeFields,
      );
      
      notifyListeners();
    }
  }

  // Load form data from JSON from the database or QR transmission.
  void loadFromJson(Map<String, dynamic> data) {
    clearAll(notify: false);

    data.forEach((key, value) {
      if (key == '__membership' && value is Map) {
        membershipData = {
          'solo_parent': (value['solo_parent'] as bool?) ?? false,
          'pwd': (value['pwd'] as bool?) ?? false,
          'four_ps_member': (value['four_ps_member'] as bool?) ?? false,
          'phic_member': (value['phic_member'] as bool?) ?? false,
        };
      } else if (key == '__family_composition' && value is List) {
        familyMembers = value.cast<Map<String, dynamic>>();
      } else if (key == '__supporting_family' && value is List) {
        supportingFamily = value.cast<Map<String, dynamic>>();
      } else if (key == '__has_support') {
        hasSupport = _truthy(value);
        final supportField = _supportBooleanField();
        if (supportField != null) {
          setValue(supportField.fieldName, hasSupport, notify: false);
        }
      } else if (key == '__housing_status') {
        housingStatus = value?.toString();
      } else if (key == '__signature') {
        signatureBase64 = value?.toString();
        signaturePoints = null;
        signatureIsProcessing = false;
      } else if (
        key == 'signature' &&
        value != null &&
        value.toString().isNotEmpty
      ) {
        signatureBase64 = value.toString();
        signaturePoints = null;
        signatureIsProcessing = false;
      } else {
        final field = template.fieldByName(key) ?? _findByLabel(key);
        if (field != null) {
          if (field.fieldType == FormFieldType.memberTable && value is List) {
            memberTableData[field.fieldName] = value
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } else {
            dynamic parsedValue = value;
            if (field.fieldType == FormFieldType.boolean) {
              parsedValue = value == true || value == 'true';
            } else if (field.fieldType == FormFieldType.radio ||
                field.fieldType == FormFieldType.dropdown) {
              parsedValue =
                  _normalizeChoiceValue(field, value) ?? value?.toString();
            } else if (field.fieldType == FormFieldType.checkbox) {
              if (value is List) {
                parsedValue = value.map((e) => e.toString()).toList();
              } else {
                final raw = value?.toString() ?? '';
                parsedValue = raw.trim().isEmpty
                    ? <String>[]
                    : raw
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
              }
            } else if (field.fieldType == FormFieldType.signature) {
              final signature = value?.toString();
              if (signature != null && signature.isNotEmpty) {
                signatureBase64 = signature;
                signaturePoints = null;
                signatureIsProcessing = false;
              }
              parsedValue = signature;
            }

            setValue(field.fieldName, parsedValue, notify: false);

            if (field.fieldName == 'housing_status') {
              housingStatus = value?.toString();
            }
            if (isSupportBooleanField(field)) {
              hasSupport = _truthy(value);
            }
          }
        } else {
          _values[key] = value;
        }
      }
    });

    _recomputeFields();
    notifyListeners();
  }

  // Export form data to JSON for database storage.
  Map<String, dynamic> toJson() {
    // Flush pending recomputation before saving.
    _recomputeDebounce?.cancel();
    _recomputeFields();

    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      // Skip fields that are hidden by conditional logic.
      if (!isFieldVisible(field)) continue;

      switch (field.fieldType) {
        case FormFieldType.text:
        case FormFieldType.conditional:
        case FormFieldType.date:
        case FormFieldType.number:
        case FormFieldType.computed:
          final val = textControllers[field.fieldName]?.text ?? '';
          if (val.isNotEmpty) result[field.fieldName] = val;
          break;
        case FormFieldType.dropdown:
        case FormFieldType.radio:
          final val = _values[field.fieldName];
          if (val != null) result[field.fieldName] = val;
          break;
        case FormFieldType.checkbox:
          final val = _values[field.fieldName];
          if (val is List && val.isNotEmpty) {
            result[field.fieldName] = val;
          }
          break;
        case FormFieldType.boolean:
          final raw = _values[field.fieldName];
          result[field.fieldName] = raw == true || raw == 'true';
          break;
        case FormFieldType.memberTable:
          final rows = memberTableData[field.fieldName];
          if (rows != null && rows.isNotEmpty) {
            result[field.fieldName] = rows;
          }
          break;
        default:
          break;
      }
    }

    result['__membership'] = membershipData;
    result['__family_composition'] = familyMembers;
    result['__supporting_family'] = supportingFamily;
    result['__has_support'] = hasSupport;
    result['__housing_status'] = housingStatus ?? '';
    if (signatureBase64 != null) result['__signature'] = signatureBase64;

    return result;
  }

  // Export only the selected fields for QR transmission.
  Map<String, dynamic> toFilteredJson() {
    // Flush pending recomputation before transmission.
    _recomputeDebounce?.cancel();
    _recomputeFields();

    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      // Skip fields that should not be shared.
      if (!isFieldVisible(field)) continue;

      final checkKey = field.checkKey;
      if (fieldChecks[checkKey] != true && !selectAll) continue;

      switch (field.fieldType) {
        case FormFieldType.text:
        case FormFieldType.conditional:
        case FormFieldType.date:
        case FormFieldType.number:
        case FormFieldType.computed:
          final val = textControllers[field.fieldName]?.text ?? '';
          if (val.isNotEmpty) result[field.fieldName] = val;
          break;
        case FormFieldType.dropdown:
        case FormFieldType.radio:
          final val = _values[field.fieldName];
          if (val != null) result[field.fieldName] = val;
          break;
        case FormFieldType.checkbox:
          final val = _values[field.fieldName];
          if (val is List && val.isNotEmpty) {
            result[field.fieldName] = val;
          }
          break;
        case FormFieldType.memberTable:
          final rows = memberTableData[field.fieldName];
          if (rows != null && rows.isNotEmpty) {
            result[field.fieldName] = rows;
          }
          break;
        default:
          break;
      }
    }

    if (fieldChecks['Membership Group'] == true || selectAll) {
      result['__membership'] = membershipData;
    }
    if (fieldChecks['Family Composition'] == true || selectAll) {
      result['__family_composition'] = familyMembers;
    }
    if (signatureBase64 != null &&
        (fieldChecks['Signature'] == true || selectAll)) {
      result['__signature'] = signatureBase64;
    }

    if (selectAll || fieldChecks.values.any((v) => v == true)) {
      result['__has_support'] = hasSupport;
      if (housingStatus != null && housingStatus!.isNotEmpty) {
        result['__housing_status'] = housingStatus;
      }
    }

    if (hasSupport &&
        supportingFamily.isNotEmpty &&
        (selectAll || fieldChecks.values.any((v) => v == true))) {
      result['__supporting_family'] = supportingFamily;
    }

    return result;
  }

  // Check visibility using the field's conditional rules.
  bool isFieldVisible(FormFieldModel field) {
    final triggerMap = <String, dynamic>{};
    for (final f in template.allFields) {
      if (f.fieldType == FormFieldType.boolean) {
        if (isSupportBooleanField(f)) {
          triggerMap[f.fieldId] = hasSupport.toString();
        } else {
          triggerMap[f.fieldId] = (_values[f.fieldName] ?? false).toString();
        }
      } else if (f.fieldType == FormFieldType.checkbox) {
        final raw = _values[f.fieldName];
        if (raw is List) {
          triggerMap[f.fieldId] = raw.map((e) => e.toString()).toList();
        } else {
          triggerMap[f.fieldId] = const <String>[];
        }
      } else if (f.fieldType == FormFieldType.membershipGroup) {
        final selected = membershipData.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();
        triggerMap[f.fieldId] = selected;
      } else {
        triggerMap[f.fieldId] = _values[f.fieldName]?.toString() ?? '';
      }
    }
    final hasSupportField = _supportBooleanField();
    if (hasSupportField != null) {
      triggerMap[hasSupportField.fieldId] = hasSupport.toString();
    }
    return field.isVisible(triggerMap);
  }

  void _recomputeFields() {
    final computedFields = template.allFields
        .where((f) => f.fieldType == FormFieldType.computed)
        .toList();

    if (computedFields.isEmpty) return;

    // Resolve computed dependencies even when the template order is chained.
    // Multiple passes let downstream fields settle on the latest values.
    final maxPasses = computedFields.length;
    for (var pass = 0; pass < maxPasses; pass++) {
      var anyChanged = false;

      for (final field in computedFields) {
        final formula = field.validationRules?['formula'] as String? ?? '';
        if (formula.trim().isEmpty) continue;
        try {
          final result = _evalFormula(formula);
          final shouldShowZero =
              RegExp(r'\bSUM_COLUMN\s*\(').hasMatch(formula) ||
              formula.contains('/');
          final changed = _setComputed(
            field.fieldName,
            result,
            showZero: shouldShowZero,
          );
          anyChanged = anyChanged || changed;
        } catch (_) {
          // Leave the field blank when the formula cannot be evaluated.
        }
      }

      if (!anyChanged) break;
    }
  }

  /// Expand SUM_COLUMN() aggregate function calls before evaluation.
  String _expandAggregates(String formula) {
    // Match SUM_COLUMN(tableKey, "columnKey") or SUM_COLUMN(tableKey, 'columnKey').
    final regex = RegExp(
      'SUM_COLUMN\\(([a-zA-Z_][a-zA-Z0-9_]*)\\s*,\\s*[\'"]([^\'"]+)[\'"]\\s*\\)',
    );
    return formula.replaceAllMapped(regex, (m) {
      final tableKey = m.group(1)!;
      final columnKey = m.group(2)!;
      final sum = _sumTableColumn(tableKey, columnKey);
      return sum.toString();
    });
  }

  String _normalizeFormulaFieldReferences(String formula) {
    // Support legacy formulas that use labels instead of field names.
    final replacements = template.allFields
        .where((f) => f.fieldLabel.trim().isNotEmpty)
        .where((f) => f.fieldLabel.trim() != f.fieldName.trim())
        .toList()
      ..sort((a, b) => b.fieldLabel.length.compareTo(a.fieldLabel.length));

    var normalized = formula;
    for (final f in replacements) {
      final label = f.fieldLabel.trim();
      final key = f.fieldName.trim();
      if (label.isEmpty || key.isEmpty) continue;

      // Replace only standalone label matches so unrelated identifiers stay intact.
      final escaped = RegExp.escape(label);
      final pattern = RegExp('(?<![A-Za-z0-9_])$escaped(?![A-Za-z0-9_])');
      normalized = normalized.replaceAll(pattern, key);
    }
    return normalized;
  }

  /// Sum all numeric values in a table column.
  double _sumTableColumn(String tableKey, String columnKey) {
    final table = _resolveTableRows(tableKey);

    if (table == null || table.isEmpty) return 0.0;

    double sum = 0.0;
    for (final row in table) {
      final rawValue = _readRowColumnValue(row, tableKey, columnKey);
      // Treat null and empty values as zero.
      if (rawValue == null || rawValue == '') {
        continue;
      }
      // Treat non-numeric values as zero.
      final numVal =
          double.tryParse(rawValue.toString().replaceAll(',', '')) ?? 0.0;
      sum += numVal;
    }
    return sum;
  }

  dynamic _readRowColumnValue(
    Map<String, dynamic> row,
    String tableKey,
    String columnKey,
  ) {
    final direct = row[columnKey];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct;
    }

    final aliases = _columnAliasesForTable(tableKey, columnKey);
    for (final alias in aliases) {
      final v = row[alias];
      if (v != null && v.toString().trim().isNotEmpty) return v;
    }
    return direct;
  }

  List<String> _columnAliasesForTable(String tableKey, String columnKey) {
    FormFieldModel? tableField;

    if (tableKey == '__family_composition') {
      tableField = template.allFields
          .where((f) => f.fieldType == FormFieldType.familyTable)
          .cast<FormFieldModel?>()
          .firstWhere((f) => f != null, orElse: () => null);
    } else if (tableKey == '__supporting_family') {
      return const <String>[];
    } else {
      final normalized = tableKey.startsWith('__')
          ? tableKey.replaceFirst(RegExp(r'^__+'), '')
          : tableKey;
      tableField = template.allFields
          .where(
            (f) =>
                f.fieldType == FormFieldType.memberTable &&
                f.fieldName == normalized,
          )
          .cast<FormFieldModel?>()
          .firstWhere((f) => f != null, orElse: () => null);
    }

    if (tableField == null || tableField.columns.isEmpty) {
      return const <String>[];
    }

    final aliases = <String>[];
    for (final col in tableField.columns) {
      final dbMapKey = (col.validationRules?['db_map_key'] as String?)?.trim();
      if (dbMapKey == columnKey && col.fieldName.trim().isNotEmpty) {
        aliases.add(col.fieldName.trim());
      }
    }
    return aliases;
  }

  List<Map<String, dynamic>>? _resolveTableRows(String tableKey) {
    final formState = _currentFormStateJson();
    final normalizedKey = tableKey.trim();

    final raw =
        formState[normalizedKey] ??
        (normalizedKey.startsWith('__')
            ? formState[normalizedKey.replaceFirst(RegExp(r'^__+'), '')]
            : null);

    if (raw is! List) return null;

    return raw
        .whereType<dynamic>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Map<String, dynamic> _currentFormStateJson() {
    final state = <String, dynamic>{};

    state.addAll(_values);
    state['__family_composition'] = familyMembers;
    state['__supporting_family'] = supportingFamily;
    state.addAll(memberTableData);

    return state;
  }

  /// Tokenise and evaluate a simple arithmetic formula.
  double _evalFormula(String formula) {
    // Step 1: Normalize label-based references to field names.
    final normalized = _normalizeFormulaFieldReferences(formula);

    // Step 2: Expand aggregate functions such as SUM_COLUMN.
    final expanded = _expandAggregates(normalized);

    final knownFieldNames = template.allFields
        .map((f) => f.fieldName)
        .where((name) => name.trim().isNotEmpty)
        .toSet();

    // Step 3: Replace known field names with their numeric values.
    // Unknown tokens are replaced with zero so evaluation keeps running.
    final resolved = expanded.replaceAllMapped(
      RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*'),
      (m) {
        final name = m.group(0)!;
        if (!knownFieldNames.contains(name)) return '0';
        return _parseNum(name).toString();
      },
    );

    // Step 4: Evaluate the arithmetic expression.
    return _evalExpr(resolved.replaceAll(' ', ''), _Pos(0));
  }

  double _evalExpr(String s, _Pos p) {
    var result = _evalTerm(s, p);
    while (p.i < s.length && (s[p.i] == '+' || s[p.i] == '-')) {
      final op = s[p.i++];
      final right = _evalTerm(s, p);
      result = op == '+' ? result + right : result - right;
    }
    return result;
  }

  double _evalTerm(String s, _Pos p) {
    var result = _evalFactor(s, p);
    while (p.i < s.length && (s[p.i] == '*' || s[p.i] == '/')) {
      final op = s[p.i++];
      final right = _evalFactor(s, p);
      result = op == '*' ? result * right : (right != 0 ? result / right : 0);
    }
    return result;
  }

  double _evalFactor(String s, _Pos p) {
    if (p.i < s.length && s[p.i] == '(') {
      p.i++; // Consume '('.
      final result = _evalExpr(s, p);
      if (p.i < s.length && s[p.i] == ')') p.i++; // Consume ')'.
      return result;
    }
    if (p.i < s.length && s[p.i] == '-') {
      p.i++;
      return -_evalFactor(s, p);
    }
    // Parse a number token.
    final start = p.i;
    while (p.i < s.length &&
        (s[p.i] == '.' ||
            (s[p.i].codeUnitAt(0) >= 48 && s[p.i].codeUnitAt(0) <= 57))) {
      p.i++;
    }
    return double.tryParse(s.substring(start, p.i)) ?? 0.0;
  }

  double _parseNum(String key) {
    final raw =
        _values[key]?.toString() ??
        textControllers[key]?.text ??
        '0';
    final normalized = raw.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0.0;
  }

  bool _setComputed(String key, double value, {bool showZero = false}) {
    final str = value == 0 ? (showZero ? '0' : '') : value.toStringAsFixed(2);
    var changed = false;
    if (textControllers.containsKey(key)) {
      if (textControllers[key]!.text != str) {
        textControllers[key]!.text = str;
        _fieldNotifiers[key]?.value = str; // Keep the field notifier in sync.
        changed = true;
      }
    }
    if (_values[key] != str) {
      changed = true;
    }
    _values[key] = str;
    return changed;
  }

  // Toggle sharing for every field.
  void setSelectAll(bool val) {
    selectAll = val;
    fieldChecks.updateAll((_, _) => val);
    notifyListeners();
  }

  // Clear all form state.
  void clearAll({bool notify = true}) {
    _values.clear();
    for (final ctrl in textControllers.values) {
      ctrl.clear();
    }
    for (final notifier in _fieldNotifiers.values) {
      notifier.value = null;
    }
    membershipData = {
      'solo_parent': false,
      'pwd': false,
      'four_ps_member': false,
      'phic_member': false,
    };
    familyMembers = [];
    supportingFamily = [];
    hasSupport = false;
    housingStatus = null;
    signatureBase64 = null;
    signaturePoints = null;
    signatureIsProcessing = false;
    memberTableData.clear();
    fieldChecks.updateAll((_, _) => false);
    selectAll = false;
    if (notify) notifyListeners();
  }

  String? _normalizeChoiceValue(FormFieldModel field, dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    if (field.options.isEmpty) return raw;

    bool eq(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    for (final opt in field.options) {
      if (eq(opt.value, raw)) return opt.value;
    }

    for (final opt in field.options) {
      if (eq(opt.label, raw)) return opt.value;
    }

    String? matchByAliases(List<String> aliases) {
      for (final opt in field.options) {
        final ov = opt.value.toLowerCase();
        final ol = opt.label.toLowerCase();
        if (aliases.contains(ov) || aliases.contains(ol)) {
          return opt.value;
        }
      }
      return null;
    }

    final normalized = raw.toLowerCase();
    if (normalized == 'm') {
      final gender = matchByAliases(['m', 'male', 'lalaki']);
      if (gender != null) return gender;
      final civil = matchByAliases(['m', 'married']);
      if (civil != null) return civil;
    }

    final aliasGroups = <List<String>>[
      if (normalized == 'male' || normalized == 'lalaki')
        ['m', 'male', 'lalaki'],
      if (normalized == 'f' || normalized == 'female' || normalized == 'babae')
        ['f', 'female', 'babae'],
      if (normalized == 's' || normalized == 'single') ['s', 'single'],
      if (normalized == 'married') ['m', 'married'],
      if (normalized == 'w' || normalized == 'widowed') ['w', 'widowed'],
      if (normalized == 'h' ||
          normalized == 'sep' ||
          normalized == 'separated' ||
          normalized == 'hiwalay')
        ['h', 'sep', 'separated', 'hiwalay'],
      if (normalized == 'li' ||
          normalized == 'live_in' ||
          normalized == 'live_in_' ||
          normalized == 'livein' ||
          normalized == 'live-in')
        ['li', 'live_in', 'livein', 'live-in'],
      if (normalized == 'c' || normalized == 'minor') ['c', 'minor'],
      if (normalized == 'a' || normalized == 'annulled') ['a', 'annulled'],
    ];

    for (final aliases in aliasGroups) {
      final match = matchByAliases(aliases);
      if (match != null) return match;
    }

    return raw;
  }

  FormFieldModel? _findByLabel(String label) {
    try {
      return template.allFields.firstWhere(
        (f) => f.fieldLabel.toLowerCase() == label.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _recomputeDebounce?.cancel();
    for (final ctrl in textControllers.values) {
      ctrl.dispose();
    }
    for (final notifier in _fieldNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}

/// Mutable position pointer used by the recursive-descent formula parser.
class _Pos {
  int i;
  _Pos(this.i);
}
