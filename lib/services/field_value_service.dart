// Saves/loads field values for ANY template using field_id as the key.
// Works for GIS and every custom template — no migration needed per form.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';

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

  // ── SAVE: upsert all field values to user_field_values ────
  Future<bool> saveUserFieldValues({
    required String userId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final rows = _buildFieldRows(template, formData, (field, strValue) => {
        'user_id': userId,
        'field_id': field.fieldId,
        'field_value': strValue,
        'updated_at': now,
      });

      if (rows.isEmpty) return true;
      await _upsertChunked('user_field_values', rows, 'user_id,field_id');
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
        if (fid == null || fval == null || fval.isEmpty) continue;
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
      // NOTE: For signature fields, the caller must also set
      // controller.signatureBase64 = result[signatureFieldName]
      // after calling loadFromJson() so the drawing widget
      // renders the saved signature correctly.
      return result;
    } catch (e) {
      debugPrint('loadUserFieldValues error: $e');
      return {};
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
      final rows = _buildFieldRows(template, formData, (field, strValue) => {
        'submission_id': sessionId,
        'field_id': field.fieldId,
        'field_value': strValue,
      });
      if (rows.isNotEmpty) {
        await _upsertChunked('submission_field_values', rows, 'submission_id,field_id');
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
    Map<String, dynamic> Function(FormFieldModel field, String value) rowBuilder,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final field in template.allFields) {
      if (_skipTypes.contains(field.fieldType)) continue;
      if (field.parentFieldId != null) continue; // skip child column-definitions

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
}
