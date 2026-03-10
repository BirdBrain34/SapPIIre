// FieldValueService
// Template-agnostic PII persistence layer.
//
// WHY THIS EXISTS:
//   _saveProfile() in manage_info_screen.dart routes values by autofill_source.
//   Fields with autofill_source = NULL (every field on non-GIS templates) are
//   silently dropped — they never reach Supabase.
//
//   This service uses field_id UUID as the key instead. Since every field in
//   every template already has a field_id in form_fields, new templates work
//   automatically — no migration needed per template.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';

class FieldValueService {
  static final FieldValueService _instance = FieldValueService._internal();
  factory FieldValueService() => _instance;
  FieldValueService._internal();

  final _supabase = Supabase.instance.client;

  // These field types store data in separate tables (family_composition etc.)
  // or are derived values — skip them from the generic blob.
  static const _skipTypes = {
    FormFieldType.familyTable,
    FormFieldType.supportingFamilyTable,
    FormFieldType.membershipGroup,
    FormFieldType.signature,
    FormFieldType.computed,
  };

  // ===========================================================================
  // SAVE — called at the end of _saveProfile() in manage_info_screen.dart
  // Persists every fillable field value to user_field_values using field_id.
  // Works for ANY template, not just GIS.
  // ===========================================================================
  Future<bool> saveUserFieldValues({
    required String userId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final rows = <Map<String, dynamic>>[];
      final now  = DateTime.now().toIso8601String();

      for (final field in template.allFields) {
        if (_skipTypes.contains(field.fieldType)) continue;

        final value = formData[field.fieldName];
        if (value == null) continue;

        final strValue = value.toString().trim();
        if (strValue.isEmpty) continue;

        rows.add({
          'user_id':     userId,
          'field_id':    field.fieldId,
          'field_value': strValue,
          'updated_at':  now,
        });
      }

      if (rows.isEmpty) return true;

      // Upsert in chunks of 50 to stay within Supabase request limits
      for (var i = 0; i < rows.length; i += 50) {
        final chunk = rows.sublist(i, (i + 50).clamp(0, rows.length));
        await _supabase
            .from('user_field_values')
            .upsert(chunk, onConflict: 'user_id,field_id');
      }

      debugPrint('FieldValueService: saved ${rows.length} values '
          '(template: ${template.formName})');
      return true;
    } catch (e) {
      debugPrint('FieldValueService.saveUserFieldValues error: $e');
      return false;
    }
  }

  // ===========================================================================
  // LOAD — called in _mergeFieldValues() inside _initFormController()
  // Returns Map<fieldName, value> for FormStateController.loadFromJson().
  // Only fills fields that are still empty after Pass 1 structured autofill.
  // ===========================================================================
  Future<Map<String, dynamic>> loadUserFieldValues({
    required String userId,
    required FormTemplate template,
  }) async {
    try {
      final eligibleFields = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .toList();

      if (eligibleFields.isEmpty) return {};

      final fieldIds = eligibleFields.map((f) => f.fieldId).toList();

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value')
          .eq('user_id', userId)
          .inFilter('field_id', fieldIds);

      // Reverse lookup: field_id → field_name (what FormStateController uses as key)
      final idToName = {for (final f in eligibleFields) f.fieldId: f.fieldName};

      final result = <String, dynamic>{};
      for (final row in rows) {
        final fieldId    = row['field_id']    as String?;
        final fieldValue = row['field_value'] as String?;
        if (fieldId == null || fieldValue == null || fieldValue.isEmpty) continue;
        final name = idToName[fieldId];
        if (name != null) result[name] = fieldValue;
      }

      debugPrint('FieldValueService: loaded ${result.length} saved values '
          '(template: ${template.formName})');
      return result;
    } catch (e) {
      debugPrint('FieldValueService.loadUserFieldValues error: $e');
      return {};
    }
  }

  // ===========================================================================
  // QR PUSH — replaces sendDataToWebSession() in _scanAndTransmit()
  // Writes both:
  //   - submission_field_values (normalised per-field rows for applicant records)
  //   - form_submission.form_data JSONB (what the web Realtime listener reads)
  // ===========================================================================
  Future<bool> pushToSubmission({
    required String sessionId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      // 1. Write normalised per-field rows to submission_field_values
      final rows = <Map<String, dynamic>>[];
      for (final field in template.allFields) {
        if (_skipTypes.contains(field.fieldType)) continue;
        final value = formData[field.fieldName];
        if (value == null) continue;
        final strValue = value.toString().trim();
        if (strValue.isEmpty) continue;
        rows.add({
          'submission_id': sessionId,
          'field_id':      field.fieldId,
          'field_value':   strValue,
        });
      }

      if (rows.isNotEmpty) {
        for (var i = 0; i < rows.length; i += 50) {
          final chunk = rows.sublist(i, (i + 50).clamp(0, rows.length));
          await _supabase
              .from('submission_field_values')
              .upsert(chunk, onConflict: 'submission_id,field_id');
        }
      }

      // 2. Update form_submission JSONB + stamp user_id
      final currentUserId = _supabase.auth.currentUser?.id;
      final updatePayload = <String, dynamic>{
        'form_data':  formData,
        'status':     'scanned',
        'scanned_at': DateTime.now().toIso8601String(),
      };
      if (currentUserId != null) {
        updatePayload['user_id'] = currentUserId;
      }

      final response = await _supabase
          .from('form_submission')
          .update(updatePayload)
          .eq('id', sessionId)
          .eq('status', 'active')
          .select()
          .maybeSingle();

      if (response == null) {
        debugPrint('FieldValueService: session $sessionId not found or already closed');
        return false;
      }

      debugPrint('FieldValueService: pushed ${rows.length} field values '
          'to submission $sessionId');
      return true;
    } catch (e) {
      debugPrint('FieldValueService.pushToSubmission error: $e');
      return false;
    }
  }
}
