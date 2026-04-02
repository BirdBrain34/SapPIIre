import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/models/form_template_models.dart';

class FormStateController extends ChangeNotifier {
  final FormTemplate template;

  // ── Core value store ──────────────────────────────────────
  final Map<String, dynamic> _values = {};

  // Per-field notifier — avoids full form repaint on each change
  final Map<String, ValueNotifier<dynamic>> _fieldNotifiers = {};

  // ── TextEditingControllers for text/number/date fields ───
  final Map<String, TextEditingController> textControllers = {};

  // Debounce prevents formula recalc on every single keystroke
  Timer? _recomputeDebounce;

  // ── Complex field state ───────────────────────────────────
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

  // ── Member table state (generic user-defined tables) ──
  Map<String, List<Map<String, dynamic>>> memberTableData = {};

  // ── Checkbox selection state (mobile "what to share") ────
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

  void setValue(String fieldName, dynamic value, {bool notify = true}) {
    _values[fieldName] = value;
    _fieldNotifiers[fieldName]?.value = value; // Update per-field notifier

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

    // Only structural changes (conditions, computed cascades) trigger full repaint
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

    // Backward compatibility for older templates without explicit age_from_field.
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

  /// Checks if a changed field triggers conditional visibility on other fields.
  bool _hasStructuralDependencies(String fieldName) {
    final changedField = template.fieldByName(fieldName);
    if (changedField == null) return false;

    // Check if any field's visibility condition is bound to the changed field.
    for (final field in template.allFields) {
      if (field.conditions.any(
        (cond) => cond.triggerFieldId == changedField.fieldId,
      )) {
        return true;
      }
    }
    return false;
  }

  // Notifies listeners so computed fields update on screen.
  void recomputeFromFamilyChange() {
    _recomputeFields();
    notifyListeners();
  }

  // Public notifier wrapper for widgets that need a full form refresh.
  void notifyFormChanged() {
    notifyListeners();
  }

  // ── Member table helpers ──────────────────────────────────
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
      
      // Trigger recompute when row is removed (affects SUM_COLUMN formulas)
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
      
      // Trigger recompute for formulas that depend on member table data
      _recomputeDebounce?.cancel();
      _recomputeDebounce = Timer(
        const Duration(milliseconds: 150),
        _recomputeFields,
      );
      
      notifyListeners();
    }
  }

  // Load form data from JSON (from database or QR transmission)
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
        hasSupport = (value as bool?) ?? false;
      } else if (key == '__housing_status') {
        housingStatus = value?.toString();
      } else if (key == '__signature') {
        signatureBase64 = value?.toString();
        signaturePoints = null;
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
              }
              parsedValue = signature;
            }

            setValue(field.fieldName, parsedValue, notify: false);

            if (field.fieldName == 'housing_status') {
              housingStatus = value?.toString();
            }
            if (field.fieldName == 'has_support') {
              hasSupport = value == true || value == 'true';
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

  // Export form data to JSON for database storage
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      // Do not persist values for fields that are currently hidden by conditions.
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

  // Export filtered data for QR transmission (only checked fields)
  Map<String, dynamic> toFilteredJson() {
    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      // Hidden fields should never be part of transmitted shared data.
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

  // Check if field should be visible based on conditional logic
  bool isFieldVisible(FormFieldModel field) {
    final triggerMap = <String, dynamic>{};
    for (final f in template.allFields) {
      if (f.fieldType == FormFieldType.boolean) {
        triggerMap[f.fieldId] = (_values[f.fieldName] ?? false).toString();
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
    final hasSupportField = template.fieldByName('has_support');
    if (hasSupportField != null) {
      triggerMap[hasSupportField.fieldId] = hasSupport.toString();
    }
    return field.isVisible(triggerMap);
  }

  void _recomputeFields() {
    final computedFields = template.allFields
        .where((f) => f.fieldType == FormFieldType.computed)
        .toList();

    for (final field in computedFields) {
      final formula = field.validationRules?['formula'] as String? ?? '';
      if (formula.trim().isEmpty) continue;
      try {
        final result = _evalFormula(formula);
        final shouldShowZero = RegExp(r'\bSUM_COLUMN\s*\(').hasMatch(formula);
        _setComputed(field.fieldName, result, showZero: shouldShowZero);
      } catch (_) {
        // Leave field blank if formula is invalid
      }
    }
  }

  /// Preprocess formula to expand SUM_COLUMN() aggregate function calls.
  /// Converts SUM_COLUMN(__family_composition, "allowance") → numeric sum
  String _expandAggregates(String formula) {
    // Match: SUM_COLUMN(tableKey, "columnKey") or SUM_COLUMN(tableKey, 'columnKey')
    final regex = RegExp(
      'SUM_COLUMN\\(([a-zA-Z_][a-zA-Z0-9_]*)\\s*,\\s*[\'"]([a-zA-Z_][a-zA-Z0-9_]*)[\'"]\\s*\\)',
    );
    return formula.replaceAllMapped(regex, (m) {
      final tableKey = m.group(1)!;
      final columnKey = m.group(2)!;
      final sum = _sumTableColumn(tableKey, columnKey);
      return sum.toString();
    });
  }

  /// Sum all numeric values in a specific column across all rows of a table field.
  /// Returns 0 if table is empty, not found, or contains no valid numeric values.
  /// Handles null, empty string, and non-numeric values safely (treated as 0).
  double _sumTableColumn(String tableKey, String columnKey) {
    final table = _resolveTableRows(tableKey);

    if (table == null || table.isEmpty) return 0.0;

    double sum = 0.0;
    for (final row in table) {
      final rawValue = _readRowColumnValue(row, tableKey, columnKey);
      // Treat null and empty string as 0
      if (rawValue == null || rawValue == '') {
        continue;
      }
      // Parse as number; non-numeric → 0
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
    // Step 1: Expand aggregate functions (SUM_COLUMN, etc.)
    final expanded = _expandAggregates(formula);

    // Step 2: Replace field names with their numeric values
    final resolved = expanded.replaceAllMapped(
      RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*'),
      (m) {
        final name = m.group(0)!;
        return _parseNum(name).toString();
      },
    );

    // Step 3: Evaluate the arithmetic expression
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
      p.i++; // consume '('
      final result = _evalExpr(s, p);
      if (p.i < s.length && s[p.i] == ')') p.i++; // consume ')'
      return result;
    }
    if (p.i < s.length && s[p.i] == '-') {
      p.i++;
      return -_evalFactor(s, p);
    }
    // Parse number
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
        textControllers[key]?.text.replaceAll(',', '') ??
        _values[key]?.toString() ??
        '0';
    return double.tryParse(raw) ?? 0.0;
  }

  void _setComputed(String key, double value, {bool showZero = false}) {
    final str = value == 0 ? (showZero ? '0' : '') : value.toStringAsFixed(2);
    if (textControllers.containsKey(key)) {
      if (textControllers[key]!.text != str) {
        textControllers[key]!.text = str;
        _fieldNotifiers[key]?.value = str; // Also update notifier
      }
    }
    _values[key] = str;
  }

  // ── Select-all toggle ─────────────────────────────────────
  void setSelectAll(bool val) {
    selectAll = val;
    fieldChecks.updateAll((_, __) => val);
    notifyListeners();
  }

  // ── Clear everything ──────────────────────────────────────
  void clearAll({bool notify = true}) {
    _values.clear();
    for (final ctrl in textControllers.values) ctrl.clear();
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
    memberTableData.clear();
    fieldChecks.updateAll((_, __) => false);
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
      if (normalized == 'sep' || normalized == 'separated')
        ['sep', 'separated'],
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
    for (final ctrl in textControllers.values) ctrl.dispose();
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
