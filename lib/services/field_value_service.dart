// Saves/loads field values for ANY template using field_id as the key.
// Works for GIS and every custom template — no migration needed per form.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';
import 'form_template_service.dart';

class FieldValueService {
  static final FieldValueService _instance = FieldValueService._internal();
  factory FieldValueService() => _instance;
  FieldValueService._internal();

  final _supabase = Supabase.instance.client;

  // Field types stored in dedicated tables or derived — skip from generic save.
  static const _skipTypes = {
    FormFieldType.familyTable,
    FormFieldType.supportingFamilyTable,
    FormFieldType.membershipGroup,
  };
  static const _clearedSentinel = '__CLEARED__';

  // ── SAVE: upsert all field values to user_field_values ────
  Future<bool> saveUserFieldValues({
    required String userId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      final eligibleFieldIds = eligible.map((f) => f.fieldId).toList();
      if (eligibleFieldIds.isEmpty) return true;

      final now = DateTime.now().toIso8601String();
      final existingRows = await _supabase
          .from('user_field_values')
          .select('field_id')
          .eq('user_id', userId)
          .inFilter('field_id', eligibleFieldIds);
      final existingFieldIds = existingRows
          .map((r) => r['field_id'] as String?)
          .whereType<String>()
          .toSet();

      final rows = _buildFieldRows(
        template,
        formData,
        (field, strValue) => {
          'user_id': userId,
          'field_id': field.fieldId,
          'field_value': strValue,
          'updated_at': now,
        },
      );

      final savedFieldIds = rows
          .map((r) => r['field_id'] as String?)
          .whereType<String>()
          .toSet();

      // Fields that previously had direct rows but are now empty should be
      // marked as cleared to suppress cross-form fallback repopulation.
      final clearedFieldIds = existingFieldIds
          .where((id) => !savedFieldIds.contains(id))
          .toList();
      if (clearedFieldIds.isNotEmpty) {
        final clearedRows = clearedFieldIds
            .map(
              (id) => <String, dynamic>{
                'user_id': userId,
                'field_id': id,
                'field_value': _clearedSentinel,
                'updated_at': now,
              },
            )
            .toList();
        await _upsertChunked(
          'user_field_values',
          clearedRows,
          'user_id,field_id',
        );
      }

      if (rows.isNotEmpty) {
        await _upsertChunked('user_field_values', rows, 'user_id,field_id');
      }
      return true;
    } catch (e) {
      debugPrint('saveUserFieldValues error: $e');
      return false;
    }
  }

  // ── LOAD: fetch saved values and map field_id back to field_name ──
  Future<Map<String, dynamic>> loadUserFieldValues({
    required String userId,
    required FormTemplate template,
  }) async {
    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) return {};

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value')
          .eq('user_id', userId)
          .inFilter('field_id', eligible.map((f) => f.fieldId).toList());

      // Reverse map: field_id → field_name and field_id → field_type
      final idToName = {for (final f in eligible) f.fieldId: f.fieldName};
      final idToType = {for (final f in eligible) f.fieldId: f.fieldType};
      final result = <String, dynamic>{};
      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null ||
            fval == null ||
            fval.isEmpty ||
            fval == _clearedSentinel) {
          continue;
        }
        final name = idToName[fid];
        if (name == null) continue;

        if (idToType[fid] == FormFieldType.memberTable) {
          try {
            result[name] = (jsonDecode(fval) as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (_) {
            result[name] = <Map<String, dynamic>>[];
          }
          continue;
        }

        result[name] = fval;
      }
      return result;
    } catch (e) {
      debugPrint('loadUserFieldValues error: $e');
      return {};
    }
  }

  // ── LOAD + CROSS-FORM FILL: direct values first, then canonical matches ──
  Future<Map<String, dynamic>> loadUserFieldValuesWithCrossFormFill({
    required String userId,
    required FormTemplate template,
  }) async {
    final direct = await loadUserFieldValues(
      userId: userId,
      template: template,
    );

    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) return direct;

      final missingByCanonical = <String, List<FormFieldModel>>{};
      var protectedCount = 0;
      final directRows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value')
          .eq('user_id', userId)
          .inFilter('field_id', eligible.map((f) => f.fieldId).toList());
      final clearedFieldIds = directRows
          .where((r) => (r['field_value'] as String?) == _clearedSentinel)
          .map((r) => r['field_id'] as String?)
          .whereType<String>()
          .toSet();

      for (final field in eligible) {
        if (clearedFieldIds.contains(field.fieldId)) {
          // User explicitly cleared this field in this template.
          continue;
        }
        final current = direct[field.fieldName];
        final hasValue =
            current != null && current.toString().trim().isNotEmpty;
        final canonical = _semanticFieldKey(field);
        if (hasValue) {
          protectedCount++;
          continue;
        }
        if (canonical == null || canonical.isEmpty) continue;
        missingByCanonical
            .putIfAbsent(canonical, () => <FormFieldModel>[])
            .add(field);
      }

      debugPrint('DirectValues loaded: ${direct.length} fields');
      debugPrint('Protected from cross-fill: $protectedCount fields');

      debugPrint(
        'crossFormFill: template=${template.formName}, direct=${direct.length}, missingKeys=${missingByCanonical.length}',
      );

      if (missingByCanonical.isEmpty) return direct;

      final valueRows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, updated_at')
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final allFieldIds = valueRows
          .map((row) => row['field_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      debugPrint(
        'crossFormFill: user_field_values rows=${valueRows.length}, distinctFieldIds=${allFieldIds.length}',
      );
      if (allFieldIds.isEmpty) return direct;

      final idToCanonical = <String, String>{};
      try {
        final fieldRows = await _supabase
            .from('form_fields')
            .select(
              'field_id, canonical_field_key, autofill_source, field_name, field_label',
            )
            .inFilter('field_id', allFieldIds);

        for (final row in fieldRows) {
          final fid = row['field_id'] as String?;
          final canonical =
              _normalizeCanonicalKey(row['canonical_field_key'] as String?) ??
              _keyFromTextPreferAlias(row['autofill_source'] as String?) ??
              _keyFromTextPreferAlias(row['field_name'] as String?) ??
              _keyFromTextPreferAlias(row['field_label'] as String?);
          if (fid == null || canonical == null || canonical.isEmpty) continue;
          idToCanonical[fid] = canonical;
        }
      } catch (e) {
        debugPrint('crossFormFill form_fields query failed: $e');
      }

      debugPrint(
        'crossFormFill: resolved fieldId->canonical=${idToCanonical.length}',
      );
      if (idToCanonical.isEmpty) return direct;

      final canonicalBestValue = <String, String>{};
      for (final row in valueRows) {
        final fid = row['field_id'] as String?;
        final value = row['field_value'] as String?;
        if (fid == null ||
            value == null ||
            value.trim().isEmpty ||
            value == _clearedSentinel) {
          continue;
        }

        final canonical = idToCanonical[fid];
        if (canonical == null) continue;

        // Rows are pre-sorted by updated_at descending, so first hit per
        // canonical key is the most recent value.
        canonicalBestValue.putIfAbsent(canonical, () => value);
      }
      debugPrint(
        'crossFormFill: canonical values=${canonicalBestValue.length}',
      );

      final unmatchedKeys =
          missingByCanonical.keys
              .where(
                (k) => !_candidateLookupKeys(
                  k,
                ).any(canonicalBestValue.containsKey),
              )
              .toList()
            ..sort();
      if (unmatchedKeys.isNotEmpty) {
        final missingPreview = unmatchedKeys.take(12).join(', ');
        final availablePreview = canonicalBestValue.keys.take(20).join(', ');
        debugPrint(
          'crossFormFill: unmatchedKeys(${unmatchedKeys.length})=[$missingPreview]',
        );
        debugPrint('crossFormFill: availableKeys(sample)=[$availablePreview]');
      }

      final merged = <String, dynamic>{...direct};
      var filledCount = 0;
      for (final entry in missingByCanonical.entries) {
        String? bestValue;
        for (final k in _candidateLookupKeys(entry.key)) {
          final v = canonicalBestValue[k];
          if (v != null && v.trim().isNotEmpty) {
            bestValue = v;
            break;
          }
        }
        if (bestValue == null || bestValue.trim().isEmpty) continue;

        for (final field in entry.value) {
          final current = merged[field.fieldName];
          final isEmpty = current == null || current.toString().trim().isEmpty;
          if (isEmpty) {
            merged[field.fieldName] = bestValue;
            filledCount++;
          }
        }
      }
      debugPrint('Cross-filled: $filledCount fields');

      if (filledCount == 0 && missingByCanonical.isNotEmpty) {
        try {
          final legacy = await loadUserFieldValuesWithCanonicalFallback(
            userId: userId,
            template: template,
          );
          if (legacy.length > merged.length) return legacy;
        } catch (e) {
          debugPrint('crossFormFill legacy fallback failed: $e');
        }
      }

      return merged;
    } catch (e) {
      debugPrint('loadUserFieldValuesWithCrossFormFill error: $e');
      return direct;
    }
  }

  // ── LOAD + CANONICAL FALLBACK: auto-fill missing fields across templates ──
  Future<Map<String, dynamic>> loadUserFieldValuesWithCanonicalFallback({
    required String userId,
    required FormTemplate template,
  }) async {
    try {
      // Pass 1: direct field_id loading for the selected template.
      final direct = await loadUserFieldValues(
        userId: userId,
        template: template,
      );

      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) return direct;

      final missingByCanonical = <String, List<FormFieldModel>>{};
      for (final field in eligible) {
        final current = direct[field.fieldName];
        final hasValue =
            current != null && current.toString().trim().isNotEmpty;
        final canonical = _normalizeCanonicalKey(field.canonicalFieldKey);
        if (hasValue || canonical == null || canonical.isEmpty) continue;
        missingByCanonical
            .putIfAbsent(canonical, () => <FormFieldModel>[])
            .add(field);
      }

      if (missingByCanonical.isEmpty) return direct;

      final templates = await FormTemplateService().fetchActiveTemplates();
      final allFields = templates
          .expand((t) => t.allFields)
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();

      final canonicalNeeded = missingByCanonical.keys.toSet();
      final idToCanonical = <String, String>{};
      final candidateFieldIds = <String>[];
      for (final field in allFields) {
        final canonical = _normalizeCanonicalKey(field.canonicalFieldKey);
        if (canonical == null || canonical.isEmpty) continue;
        if (!canonicalNeeded.contains(canonical)) continue;
        idToCanonical[field.fieldId] = canonical;
        candidateFieldIds.add(field.fieldId);
      }

      if (candidateFieldIds.isEmpty) return direct;

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, updated_at')
          .eq('user_id', userId)
          .inFilter('field_id', candidateFieldIds)
          .order('updated_at', ascending: false);

      final canonicalResolved = <String>{};
      final merged = <String, dynamic>{...direct};
      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final value = row['field_value'] as String?;
        if (fid == null || value == null || value.trim().isEmpty) continue;

        final canonical = idToCanonical[fid];
        if (canonical == null || canonicalResolved.contains(canonical))
          continue;

        final targets = missingByCanonical[canonical];
        if (targets == null || targets.isEmpty) continue;

        for (final target in targets) {
          if (merged[target.fieldName] == null ||
              merged[target.fieldName].toString().trim().isEmpty) {
            merged[target.fieldName] = value;
          }
        }
        canonicalResolved.add(canonical);
      }

      return merged;
    } catch (e) {
      debugPrint('loadUserFieldValuesWithCanonicalFallback error: $e');
      return await loadUserFieldValues(userId: userId, template: template);
    }
  }

  // ── QR PUSH: write per-field rows + update form_submission JSONB ──
  Future<bool> pushToSubmission({
    required String sessionId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      // 1. Normalised per-field rows
      final rows = _buildFieldRows(
        template,
        formData,
        (field, strValue) => {
          'submission_id': sessionId,
          'field_id': field.fieldId,
          'field_value': strValue,
        },
      );
      if (rows.isNotEmpty) {
        await _upsertChunked(
          'submission_field_values',
          rows,
          'submission_id,field_id',
        );
      }

      // 2. Update session JSONB + stamp user_id so web can resolve name
      final uid = _supabase.auth.currentUser?.id;
      final payload = <String, dynamic>{
        'form_data': formData,
        'status': 'scanned',
        'scanned_at': DateTime.now().toIso8601String(),
        if (uid != null) 'user_id': uid,
      };

      final res = await _supabase
          .from('form_submission')
          .update(payload)
          .eq('id', sessionId)
          .eq('status', 'active')
          .select()
          .maybeSingle();

      if (res == null) {
        debugPrint('pushToSubmission: session $sessionId not found/closed');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('pushToSubmission error: $e');
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  /// Iterate template fields, skip non-saveable types, build row maps.
  List<Map<String, dynamic>> _buildFieldRows(
    FormTemplate template,
    Map<String, dynamic> formData,
    Map<String, dynamic> Function(FormFieldModel field, String value)
    rowBuilder,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final field in template.allFields) {
      if (_skipTypes.contains(field.fieldType)) continue;
      if (field.parentFieldId != null)
        continue; // skip child column-definitions

      if (field.fieldType == FormFieldType.signature) {
        final sigVal =
            (formData[field.fieldName] ?? formData['__signature'])
                ?.toString() ??
            '';
        if (sigVal.trim().isEmpty) continue;
        rows.add(rowBuilder(field, sigVal));
        continue;
      }

      if (field.fieldType == FormFieldType.memberTable) {
        final val = formData[field.fieldName];
        if (val == null) continue;
        final jsonStr = jsonEncode(val);
        if (jsonStr == '[]' || jsonStr.isEmpty) continue;
        rows.add(rowBuilder(field, jsonStr));
        continue;
      }

      final val = formData[field.fieldName]?.toString().trim() ?? '';
      if (val.isEmpty) continue;
      rows.add(rowBuilder(field, val));
    }
    return rows;
  }

  /// Upsert rows in chunks of 50 to stay within Supabase limits.
  Future<void> _upsertChunked(
    String table,
    List<Map<String, dynamic>> rows,
    String onConflict,
  ) async {
    for (var i = 0; i < rows.length; i += 50) {
      final chunk = rows.sublist(i, (i + 50).clamp(0, rows.length));
      await _supabase.from(table).upsert(chunk, onConflict: onConflict);
    }
  }

  String? _normalizeCanonicalKey(String? raw) {
    if (raw == null) return null;
    final lowered = raw.trim().toLowerCase();
    if (lowered.isEmpty) return null;
    final normalized = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  String? _semanticFieldKey(FormFieldModel field) {
    final canonical = _keyFromTextPreferAlias(field.canonicalFieldKey);
    if (canonical != null) return canonical;

    final source = _keyFromTextPreferAlias(field.autofillSource);
    if (source != null) return source;

    final aliasFromName = _keyFromTextPreferAlias(field.fieldName);
    if (aliasFromName != null) return aliasFromName;

    final aliasFromLabel = _keyFromTextPreferAlias(field.fieldLabel);
    if (aliasFromLabel != null) return aliasFromLabel;

    return _normalizeCanonicalKey(field.fieldName);
  }

  String? _keyFromTextPreferAlias(String? raw) {
    final alias = _semanticAliasFromText(raw);
    if (alias != null) return alias;
    return _normalizeCanonicalKey(raw);
  }

  String? _semanticAliasFromText(String? raw) {
    final t = _normalizeCanonicalKey(raw);
    if (t == null) return null;

    // Name variants (English + Filipino labels/keys)
    if (t == 'lastname' ||
        t == 'last_name' ||
        t == 'surname' ||
        t == 'family_name' ||
        t.contains('apelyido') ||
        (t.contains('last') && t.contains('name'))) {
      return 'last_name';
    }

    if (t == 'firstname' ||
        t == 'first_name' ||
        t == 'given_name' ||
        t == 'given_names' ||
        t.contains('pangalan') ||
        (t.contains('first') && t.contains('name'))) {
      return 'first_name';
    }

    if (t == 'middlename' ||
        t == 'middle_name' ||
        t.contains('gitnang') ||
        (t.contains('middle') && t.contains('name'))) {
      return 'middle_name';
    }

    // Birthdate variants
    if (t == 'birthdate' ||
        t == 'date_of_birth' ||
        t.contains('kapanganakan') ||
        (t.contains('birth') && (t.contains('date') || t.contains('day')))) {
      return 'birth_date';
    }

    // Civil/marital status variants
    if (t == 'civil_status' ||
        t == 'marital_status' ||
        t == 'estadong_sibil_civil_status' ||
        t.contains('sibil') ||
        (t.contains('civil') && t.contains('status')) ||
        (t.contains('marital') && t.contains('status'))) {
      return 'civil_status';
    }

    // Sex/gender variants
    if (t == 'sex' ||
        t == 'gender' ||
        t == 'kasarian_sex' ||
        t.contains('kasarian') ||
        t.contains('gender')) {
      return 'gender';
    }

    // Contact variants
    if (t == 'cp_number' ||
        t == 'contact_no' ||
        t == 'contact_number' ||
        t == 'mobile_no' ||
        t == 'cellphone_number' ||
        t.contains('phone') ||
        t.contains('mobile') ||
        t.contains('contact')) {
      return 'phone';
    }

    // Email variants
    if (t == 'email_address' || t.contains('email') || t.contains('e_mail')) {
      return 'email';
    }

    // Place of birth variants
    if (t == 'lugar_ng_kapanganakan_place_of_birth' ||
        t == 'place_of_birth' ||
        t == 'birth_place' ||
        (t.contains('birth') && t.contains('place'))) {
      return 'birthplace';
    }

    // Address component variants used in profile + GIS forms
    if (t == 'house_number_street_name_phase_purok' ||
        t == 'house_no_street' ||
        t == 'address_line' ||
        t.contains('street')) {
      return 'address_line';
    }

    if (t == 'subdivison_' || t == 'subdivision' || t.contains('subdivision')) {
      return 'subdivision';
    }

    if (t.contains('barangay')) return 'barangay';
    if (t.contains('purok') || t.contains('sitio')) return 'purok_sitio';

    return null;
  }

  List<String> _candidateLookupKeys(String key) {
    final normalized = _normalizeCanonicalKey(key);
    if (normalized == null || normalized.isEmpty) return const [];

    final set = <String>{normalized};
    switch (normalized) {
      case 'civil_status':
        set.add('estadong_sibil_civil_status');
        break;
      case 'gender':
        set.add('kasarian_sex');
        break;
      case 'phone':
        set.add('cp_number');
        break;
      case 'email':
        set.add('email_address');
        break;
      case 'birth_date':
        set.add('date_of_birth');
        break;
      case 'birthplace':
        set.add('lugar_ng_kapanganakan_place_of_birth');
        break;
      case 'address_line':
        set.add('house_number_street_name_phase_purok');
        break;
      case 'subdivision':
        set.add('subdivison_');
        break;
    }
    return set.toList(growable: false);
  }
}
