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
            'status, created_by, published_at, pushed_to_mobile_at',
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
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, placeholder,
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
      final existingFields = await _supabase
          .from('form_fields')
          .select('field_id')
          .eq('template_id', templateId);

      for (final f in existingFields) {
        final fid = f['field_id'] as String;
        await _supabase
            .from('form_field_options')
            .delete()
            .eq('field_id', fid);
        await _supabase
            .from('form_field_conditions')
            .delete()
            .eq('field_id', fid);
      }

      await _supabase
          .from('form_fields')
          .delete()
          .eq('template_id', templateId);
      await _supabase
          .from('form_sections')
          .delete()
          .eq('template_id', templateId);
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
      final existingFields = await _supabase
          .from('form_fields')
          .select('field_id')
          .eq('template_id', templateId);

      for (final f in existingFields) {
        final fid = f['field_id'] as String;
        await _supabase
            .from('form_field_options')
            .delete()
            .eq('field_id', fid);
        await _supabase
            .from('form_field_conditions')
            .delete()
            .eq('field_id', fid);
      }

      await _supabase
          .from('form_fields')
          .delete()
          .eq('template_id', templateId);
      await _supabase
          .from('form_sections')
          .delete()
          .eq('template_id', templateId);
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
  /// Uses a clear-and-reinsert approach for reliability.
  Future<bool> saveTemplateStructure({
    required String templateId,
    required String formName,
    String? formDesc,
    Map<String, dynamic>? themeConfig,
    required List<Map<String, dynamic>> sections,
    required List<Map<String, dynamic>> fields,
    required List<Map<String, dynamic>> options,
  }) async {
    try {
      // 1. Update template metadata
      await _supabase.from('form_templates').update({
        'form_name': formName,
        'form_desc': formDesc,
        'theme_config': themeConfig,
      }).eq('template_id', templateId);

      // 2. Clear existing children
      final existingFields = await _supabase
          .from('form_fields')
          .select('field_id')
          .eq('template_id', templateId);

      for (final f in existingFields) {
        final fid = f['field_id'] as String;
        await _supabase
            .from('form_field_options')
            .delete()
            .eq('field_id', fid);
        await _supabase
            .from('form_field_conditions')
            .delete()
            .eq('field_id', fid);
      }

      await _supabase
          .from('form_fields')
          .delete()
          .eq('template_id', templateId);
      await _supabase
          .from('form_sections')
          .delete()
          .eq('template_id', templateId);

      // 3. Insert fresh structure
      if (sections.isNotEmpty) {
        await _supabase.from('form_sections').insert(sections);
      }
      if (fields.isNotEmpty) {
        await _supabase.from('form_fields').insert(fields);
      }
      if (options.isNotEmpty) {
        await _supabase.from('form_field_options').insert(options);
      }

      return true;
    } catch (e) {
      debugPrint('FormBuilderService.saveTemplateStructure error: $e');
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
