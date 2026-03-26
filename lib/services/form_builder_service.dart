// Form Builder Service
// CRUD operations for building/editing form templates.
// Handles the publishing workflow: draft → published → pushed_to_mobile.
//
// Used exclusively by the FormBuilderScreen (superadmin only).
// For read-only template fetching, use FormTemplateService instead.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormBuilderService {
  static final FormBuilderService _instance = FormBuilderService._internal();
  factory FormBuilderService() => _instance;
  FormBuilderService._internal();

  final _supabase = Supabase.instance.client;

  /// Last error from saveTemplateStructure (for UI display).
  String? lastSaveError;

  /// Delete all child rows (options, conditions, values) for a template's fields,
  /// then delete the fields and sections themselves.
  Future<void> _cascadeDeleteStructure(
    String templateId, {
    bool includeValues = false,
  }) async {
    final existingFields = await _supabase
        .from('form_fields')
        .select('field_id')
        .eq('template_id', templateId);

    if (existingFields.isNotEmpty) {
      final fieldIds =
          existingFields.map((f) => f['field_id'] as String).toList();
      await _supabase
          .from('form_field_options')
          .delete()
          .inFilter('field_id', fieldIds);
      await _supabase
          .from('form_field_conditions')
          .delete()
          .inFilter('field_id', fieldIds);
      if (includeValues) {
        await _supabase
            .from('submission_field_values')
            .delete()
            .inFilter('field_id', fieldIds);
        await _supabase
            .from('user_field_values')
            .delete()
            .inFilter('field_id', fieldIds);
      }
    }

    // Delete child fields first (parent_field_id IS NOT NULL), then parents
    await _supabase
        .from('form_fields')
        .delete()
        .eq('template_id', templateId)
        .not('parent_field_id', 'is', null);
    await _supabase
        .from('form_fields')
        .delete()
        .eq('template_id', templateId);
    await _supabase
        .from('form_sections')
        .delete()
        .eq('template_id', templateId);
  }

  // ================================================================
  // TEMPLATE CRUD
  // ================================================================

  /// Fetch all templates (including drafts) for the form builder list.
  Future<List<Map<String, dynamic>>> fetchAllTemplates() async {
    try {
      final res = await _supabase
          .from('form_templates')
          .select(
            'template_id, form_name, form_desc, is_active, '
            'status, created_by, published_at, pushed_to_mobile_at, '
            'form_code, reference_prefix, reference_format, requires_reference',
          )
          .order('form_name', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('FormBuilderService.fetchAllTemplates error: $e');
      return [];
    }
  }

  /// Fetch a single template with full structure (sections, fields, options).
  Future<Map<String, dynamic>?> fetchTemplateWithStructure(
      String templateId) async {
    try {
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active, status,
            theme_config, created_by, published_at, pushed_to_mobile_at,
            form_code, reference_prefix, reference_format, requires_reference,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, placeholder, parent_field_id,
              canonical_field_key,
              form_field_options(
                option_id, field_id, option_value, option_label,
                option_order, is_default
              ),
              form_field_conditions!form_field_conditions_field_fkey(
                condition_id, field_id, trigger_field_id, trigger_value, action
              )
            )
          ''')
          .eq('template_id', templateId)
          .single();
      return res;
    } catch (e) {
      debugPrint('FormBuilderService.fetchTemplateWithStructure error: $e');
      return null;
    }
  }

  /// Create a new template (draft).
  Future<String?> createTemplate({
    required String formName,
    String? formDesc,
    required String createdBy,
    String? formCode,
    String? referencePrefix,
    String? referenceFormat,
    bool requiresReference = true,
  }) async {
    try {
      final res = await _supabase
          .from('form_templates')
          .insert({
            'form_name': formName,
            'form_desc': formDesc,
            'is_active': false,
            'status': 'draft',
            'created_by': createdBy,
            if (formCode != null && formCode.trim().isNotEmpty)
              'form_code': formCode.trim().toUpperCase(),
            if (referencePrefix != null && referencePrefix.trim().isNotEmpty)
              'reference_prefix': referencePrefix.trim().toUpperCase(),
            if (referenceFormat != null && referenceFormat.trim().isNotEmpty)
              'reference_format': referenceFormat.trim(),
            'requires_reference': requiresReference,
          })
          .select('template_id')
          .single();
      return res['template_id'] as String;
    } catch (e) {
      debugPrint('FormBuilderService.createTemplate error: $e');
      return null;
    }
  }

  /// Delete a template and all its children (cascade).
  /// Returns a result map: { success: bool, message: String }
  /// Blocks hard delete if active submissions exist — caller should archive instead.
  Future<Map<String, dynamic>> deleteTemplate(String templateId) async {
    try {
      // Safety check: block deletion if submissions reference this template
      final submissionCount = await countSubmissions(templateId);
      if (submissionCount > 0) {
        return {
          'success': false,
          'message':
              'Cannot delete: $submissionCount submission(s) reference this form. '
              'Archive it instead to preserve historical data.',
          'submissionCount': submissionCount,
        };
      }

      // Manually cascade: options → conditions → fields → sections → template
      await _cascadeDeleteStructure(templateId);
      await _supabase
          .from('form_templates')
          .delete()
          .eq('template_id', templateId);
      return {'success': true, 'message': 'Template deleted'};
    } catch (e) {
      debugPrint('FormBuilderService.deleteTemplate error: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Force-delete a template regardless of submissions (for superadmin override).
  Future<bool> forceDeleteTemplate(String templateId) async {
    try {
      // Delete any form_submission rows that reference this template by form_type
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      if (templateData != null) {
        final formName = templateData['form_name'] as String;
        await _supabase
            .from('form_submission')
            .delete()
            .eq('form_type', formName);
        await _supabase
            .from('client_submissions')
            .delete()
            .eq('form_type', formName);
      }

      // Now cascade-delete structure
      await _cascadeDeleteStructure(templateId, includeValues: true);
      await _supabase
          .from('form_templates')
          .delete()
          .eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.forceDeleteTemplate error: $e');
      return false;
    }
  }

  // ================================================================
  // BATCH SAVE (clear & re-insert structure)
  // ================================================================

  /// Save the entire template structure (metadata + sections + fields + options).
  /// Upserts current data, then deletes orphaned rows (fields/sections that
  /// were removed in the builder) to prevent ghost blocks on reload.
  Future<bool> saveTemplateStructure({
    required String templateId,
    required String formName,
    String? formDesc,
    String? formCode,
    String? referencePrefix,
    String? referenceFormat,
    bool? requiresReference,
    Map<String, dynamic>? themeConfig,
    required List<Map<String, dynamic>> sections,
    required List<Map<String, dynamic>> fields,
    required List<Map<String, dynamic>> options,
    List<Map<String, dynamic>> conditions = const [],
  }) async {
    try {
      // 1. Update template metadata
      await _supabase.from('form_templates').update({
        'form_name': formName,
        'form_desc': formDesc,
        'theme_config': themeConfig,
        if (formCode != null && formCode.trim().isNotEmpty)
          'form_code': formCode.trim().toUpperCase(),
        if (referencePrefix != null && referencePrefix.trim().isNotEmpty)
          'reference_prefix': referencePrefix.trim().toUpperCase(),
        if (referenceFormat != null && referenceFormat.trim().isNotEmpty)
          'reference_format': referenceFormat.trim(),
        if (requiresReference != null)
          'requires_reference': requiresReference,
      }).eq('template_id', templateId);

      // 2. Delete options only (safe — no user data references options)
      final existingFields = await _supabase
          .from('form_fields')
          .select('field_id')
          .eq('template_id', templateId);

      if (existingFields.isNotEmpty) {
        final existingIds =
            existingFields.map((f) => f['field_id'] as String).toList();
        await _supabase
            .from('form_field_options')
            .delete()
            .inFilter('field_id', existingIds);
        await _supabase
            .from('form_field_conditions')
            .delete()
            .inFilter('field_id', existingIds);
      }

      // 3. Upsert sections
      if (sections.isNotEmpty) {
        await _supabase
            .from('form_sections')
            .upsert(sections, onConflict: 'section_id');
      }

      // 4. Upsert fields (parents first, then children)
      final parentFields =
          fields.where((f) => f['parent_field_id'] == null).toList();
      final childFields =
          fields.where((f) => f['parent_field_id'] != null).toList();

      for (final f in parentFields) {
        await _supabase
            .from('form_fields')
            .upsert(f, onConflict: 'field_id');
      }
      for (final f in childFields) {
        await _supabase
            .from('form_fields')
            .upsert(f, onConflict: 'field_id');
      }

      // 5. Insert fresh options
      if (options.isNotEmpty) {
        await _supabase.from('form_field_options').insert(options);
      }

      // 5b. Insert fresh conditions for conditional fields
      if (conditions.isNotEmpty) {
        await _supabase.from('form_field_conditions').insert(conditions);
      }

      // 6. Soft-delete orphaned fields — fields removed in the builder
      //    are marked as archived instead of deleted so that historical
      //    submission_field_values and user_field_values are preserved.
      final newFieldIds =
          fields.map((f) => f['field_id'] as String).toSet();
      final existingFieldIds =
          existingFields.map((f) => f['field_id'] as String).toSet();
      final orphanFieldIds =
          existingFieldIds.difference(newFieldIds).toList();

      if (orphanFieldIds.isNotEmpty) {
        // Mark orphan fields as archived (keeps field + value rows intact)
        await _supabase
            .from('form_fields')
            .update({'validation_rules': {'_archived': true}})
            .inFilter('field_id', orphanFieldIds);
      }

      // 7. Delete orphaned sections no longer in the payload
      final newSectionIds =
          sections.map((s) => s['section_id'] as String).toSet();
      final existingSections = await _supabase
          .from('form_sections')
          .select('section_id')
          .eq('template_id', templateId);
      final existingSectionIds = existingSections
          .map((s) => s['section_id'] as String)
          .toSet();
      final orphanSectionIds =
          existingSectionIds.difference(newSectionIds).toList();

      if (orphanSectionIds.isNotEmpty) {
        await _supabase
            .from('form_sections')
            .delete()
            .inFilter('section_id', orphanSectionIds);
      }

      return true;
    } catch (e, stack) {
      debugPrint('FormBuilderService.saveTemplateStructure error: $e');
      debugPrint('Stack: $stack');
      lastSaveError = e.toString();
      return false;
    }
  }

  // ================================================================
  // PUBLISHING WORKFLOW
  // ================================================================

  /// Publish template → visible to admin staff in Manage Forms.
  Future<bool> publishTemplate(String templateId) async {
    try {
      await _supabase.from('form_templates').update({
        'status': 'published',
        'is_active': true,
        'published_at': DateTime.now().toIso8601String(),
      }).eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.publishTemplate error: $e');
      return false;
    }
  }

  /// Push published template to mobile app.
  Future<bool> pushToMobile(String templateId) async {
    try {
      await _supabase.from('form_templates').update({
        'status': 'pushed_to_mobile',
        'pushed_to_mobile_at': DateTime.now().toIso8601String(),
      }).eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.pushToMobile error: $e');
      return false;
    }
  }

  /// Revert a published/pushed template back to draft.
  Future<bool> unpublishTemplate(String templateId) async {
    try {
      await _supabase.from('form_templates').update({
        'status': 'draft',
        'is_active': false,
      }).eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.unpublishTemplate error: $e');
      return false;
    }
  }

  // ================================================================
  // ARCHIVE / RESTORE
  // ================================================================

  /// Archive a template — soft-remove from admin/mobile views.
  /// Sets is_active = false and status = 'archived'.
  /// Data remains intact for historical reference.
  Future<bool> archiveTemplate(String templateId) async {
    try {
      await _supabase.from('form_templates').update({
        'status': 'archived',
        'is_active': false,
      }).eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.archiveTemplate error: $e');
      return false;
    }
  }

  /// Restore an archived template back to draft.
  Future<bool> restoreTemplate(String templateId) async {
    try {
      await _supabase.from('form_templates').update({
        'status': 'draft',
        'is_active': false,
      }).eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('FormBuilderService.restoreTemplate error: $e');
      return false;
    }
  }

  // ================================================================
  // SUBMISSION CHECKS
  // ================================================================

  /// Count how many submissions exist for a template (by form_name match).
  Future<int> countSubmissions(String templateId) async {
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      if (templateData == null) return 0;

      final formName = templateData['form_name'] as String;
      final res = await _supabase
          .from('client_submissions')
          .select('id')
          .eq('form_type', formName);
      return (res as List).length;
    } catch (e) {
      debugPrint('FormBuilderService.countSubmissions error: $e');
      return 0;
    }
  }
}
