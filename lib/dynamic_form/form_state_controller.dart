// lib/dynamic_form/form_state_controller.dart
// Holds all mutable state for a dynamic form instance.
// Used by both the mobile and web renderers.
//
// FIX: _recomputeFields() now always sums family member allowances as (B).
// Previously it only computed A + C, so editing any other field (income,
// household size, etc.) would call setValue → _recomputeFields and silently
// drop B, causing gross to revert to A+C only.

import 'package:flutter/material.dart';
import 'package:sappiire/models/form_template_models.dart';

class FormStateController extends ChangeNotifier {
  final FormTemplate template;

  // ── Core value store ──────────────────────────────────────
  final Map<String, dynamic> _values = {};

  // ── TextEditingControllers for text/number/date fields ───
  final Map<String, TextEditingController> textControllers = {};

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

  // ── Checkbox selection state (mobile "what to share") ────
  final Map<String, bool> fieldChecks = {};
  bool selectAll = false;

  FormStateController({required this.template}) {
    _initControllers();
  }

  // ── Initialise one TextEditingController per text-like field ──
  void _initControllers() {
    for (final field in template.allFields) {
      switch (field.fieldType) {
        case FormFieldType.text:
        case FormFieldType.date:
        case FormFieldType.number:
        case FormFieldType.computed:
          textControllers[field.fieldName] = TextEditingController();
          fieldChecks[field.fieldName] = false;
          break;
        case FormFieldType.dropdown:
        case FormFieldType.radio:
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
        default:
          break;
      }
    }
  }

  // ── Get / set values ──────────────────────────────────────
  dynamic getValue(String fieldName) => _values[fieldName];

  void setValue(String fieldName, dynamic value, {bool notify = true}) {
    _values[fieldName] = value;
    if (textControllers.containsKey(fieldName)) {
      final ctrl = textControllers[fieldName]!;
      final strVal = value?.toString() ?? '';
      if (ctrl.text != strVal) ctrl.text = strVal;
    }
    _recomputeFields();
    if (notify) notifyListeners();
  }

  // ── Called when family member allowances change ───────────
  // Triggers a full recompute (B is derived from familyMembers)
  // then notifies listeners so computed fields update on screen.
  void recomputeFromFamilyChange() {
    _recomputeFields();
    notifyListeners();
  }

  // ── Load from Supabase form_data JSONB ───────────────────
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
        signaturePoints = null; // Clear points when loading saved signature
      } else {
        final field = template.fieldByName(key) ?? _findByLabel(key);
        if (field != null) {
          _values[field.fieldName] = value;
          if (textControllers.containsKey(field.fieldName)) {
            textControllers[field.fieldName]!.text = value?.toString() ?? '';
          }
          if (field.fieldType == FormFieldType.radio ||
              field.fieldType == FormFieldType.dropdown) {
            _values[field.fieldName] = value?.toString();
          }
          if (field.fieldName == 'housing_status') {
            housingStatus = value?.toString();
          }
          if (field.fieldName == 'has_support') {
            hasSupport = value == true || value == 'true';
          }
        } else {
          _values[key] = value;
        }
      }
    });

    _recomputeFields();
    notifyListeners();
  }

  // ── Export to JSONB (for Supabase save) ──────────────────
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      switch (field.fieldType) {
        case FormFieldType.text:
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
        case FormFieldType.boolean:
          result[field.fieldName] = _values[field.fieldName] ?? false;
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

  // ── Build filtered map for QR transmission ───────────────
  Map<String, dynamic> toFilteredJson() {
    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      final checkKey = _checkKeyFor(field);
      if (fieldChecks[checkKey] != true && !selectAll) continue;

      switch (field.fieldType) {
        case FormFieldType.text:
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
    result['__has_support'] = hasSupport;
    result['__housing_status'] = housingStatus ?? '';
    result['__supporting_family'] = supportingFamily;

    return result;
  }

  // ── Check if a field is visible ───────────────────────────
  bool isFieldVisible(FormFieldModel field) {
    final triggerMap = <String, dynamic>{};
    for (final f in template.allFields) {
      if (f.fieldType == FormFieldType.boolean) {
        triggerMap[f.fieldId] = (_values[f.fieldName] ?? false).toString();
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

  // ── Auto-compute calculated fields ───────────────────────
  //
  // Formula: D = A + B + C
  //   A = monthly_income      (client's own income)
  //   B = Σ familyMembers[*].allowance  (family member allowances)
  //   C = monthly_alimony     (support from others / sustento)
  //   D = gross_family_income (computed)
  //
  // IMPORTANT: B is read directly from familyMembers list here so
  // that every code path (setValue, recomputeFromFamilyChange,
  // loadFromJson) always produces the correct gross. Previously only
  // recomputeFromFamilyChange included B, so any other trigger (e.g.
  // typing in household_size) would overwrite gross with A+C only.
  void _recomputeFields() {
    final a = _parseNum('monthly_income');
    final c = _parseNum('monthly_alimony');

    // B — sum every family member's allowance field
    final b = familyMembers.fold<double>(0.0, (sum, m) {
      final raw = m['allowance']?.toString().replaceAll(',', '') ?? '0';
      final parsed = double.tryParse(raw) ?? 0.0;
      return sum + parsed;
    });

    debugPrint('💰 Recompute: A=$a, B=$b (${familyMembers.length} members), C=$c');

    final gross = a + b + c; // D = A + B + C

    final hhSize = _parseNum('household_size');
    final perCapita = hhSize > 0 ? gross / hhSize : 0.0;

    final expenses = [
      'house_rent', 'food_items', 'non_food_items', 'utility_bills',
      'baby_needs', 'school_needs', 'medical_needs',
      'transport_expenses', 'loans', 'gas', 'misc',
    ].fold<double>(0.0, (sum, key) => sum + _parseNum(key));

    final net = gross - expenses;

    _setComputed('gross_family_income', gross);
    _setComputed('monthly_per_capita', perCapita);
    _setComputed('total_monthly_expense', expenses);
    _setComputed('net_monthly_income', net);
  }

  double _parseNum(String key) {
    final raw = textControllers[key]?.text.replaceAll(',', '') ??
        _values[key]?.toString() ??
        '0';
    return double.tryParse(raw) ?? 0.0;
  }

  void _setComputed(String key, double value) {
    final str = value == 0 ? '' : value.toStringAsFixed(2);
    if (textControllers.containsKey(key)) {
      if (textControllers[key]!.text != str) {
        textControllers[key]!.text = str;
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
    membershipData = {
      'solo_parent': false, 'pwd': false,
      'four_ps_member': false, 'phic_member': false,
    };
    familyMembers = [];
    supportingFamily = [];
    hasSupport = false;
    housingStatus = null;
    signatureBase64 = null;
    signaturePoints = null;
    fieldChecks.updateAll((_, __) => false);
    selectAll = false;
    if (notify) notifyListeners();
  }

  FormFieldModel? _findByLabel(String label) {
    try {
      return template.allFields
          .firstWhere((f) => f.fieldLabel.toLowerCase() == label.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  String _checkKeyFor(FormFieldModel field) {
    if (field.fieldType == FormFieldType.familyTable) return 'Family Composition';
    if (field.fieldType == FormFieldType.signature) return 'Signature';
    if (field.fieldType == FormFieldType.membershipGroup) return 'Membership Group';
    return field.fieldName;
  }

  @override
  void dispose() {
    for (final ctrl in textControllers.values) ctrl.dispose();
    super.dispose();
  }
}