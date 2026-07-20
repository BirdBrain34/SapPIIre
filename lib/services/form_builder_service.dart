// ignore_for_file: use_null_aware_elements
// Form Builder Service
// CRUD operations for building/editing form templates.
// Handles the publishing workflow from draft to published to pushed_to_mobile.
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
  String? lastActionError;

  bool _isLegacyArchivedFlag(Map<String, dynamic>? themeConfig) {
    final val = themeConfig?['archived'];
    return val == true || val == 'true';
  }

  Map<String, dynamic>? _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _isStatusCheckConstraintError(Object e) {
    if (e is! PostgrestException) return false;
    final msg = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();
    return e.code == '23514' ||
        msg.contains('check constraint') ||
        msg.contains('status') && msg.contains('constraint');
  }

  Future<Map<String, dynamic>> _loadThemeConfig(String templateId) async {
    final existing = await _supabase
        .from('form_templates')
        .select('theme_config')
        .eq('template_id', templateId)
        .maybeSingle();

    final raw = existing?['theme_config'];
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<void> _setLegacyArchiveFlag(
    String templateId, {
    required bool archived,
    bool setInactive = false,
    String? statusOverride,
  }) async {
    final themeConfig = await _loadThemeConfig(templateId);
    if (archived) {
      themeConfig['archived'] = true;
    } else {
      themeConfig.remove('archived');
    }

    final payload = <String, dynamic>{
      'theme_config': themeConfig.isEmpty ? null : themeConfig,
      if (setInactive) 'is_active': false,
      if (statusOverride != null) 'status': statusOverride,
    };

    await _supabase
        .from('form_templates')
        .update(payload)
        .eq('template_id', templateId);
  }

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
      final fieldIds = existingFields
          .map((f) => f['field_id'] as String)
          .toList();
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
            .from('user_field_values')
            .delete()
            .inFilter('field_id', fieldIds);
      }
    }

    // Delete child fields first (parent_field_id IS NOT NULL), then parents.
    await _supabase
        .from('form_fields')
        .delete()
        .eq('template_id', templateId)
        .not('parent_field_id', 'is', null);
    await _supabase.from('form_fields').delete().eq('template_id', templateId);
    await _supabase
        .from('form_sections')
        .delete()
        .eq('template_id', templateId);
  }

  // ================================================================
  // TEMPLATE CRUD
  // ================================================================

  /// Fetch all templates, including drafts, for the form builder list.
  Future<List<Map<String, dynamic>>> fetchAllTemplates() async {
    try {
      final res = await _supabase
          .from('form_templates')
          .select(
            'template_id, form_name, form_desc, is_active, '
            'status, created_by, published_at, pushed_to_mobile_at, '
            'form_code, reference_prefix, reference_format, requires_reference, '
            'theme_config, submitted_for_approval_by, submitted_for_approval_at, '
            'approved_by, approved_at, rejected_at, rejection_reason',
          )
          .order('form_name', ascending: true);
      return List<Map<String, dynamic>>.from(res).map((row) {
        final item = Map<String, dynamic>.from(row);
        final themeConfig = _asStringDynamicMap(item['theme_config']);
        if (_isLegacyArchivedFlag(themeConfig)) {
          item['status'] = 'archived';
        }
        return item;
      }).toList();
    } catch (e) {
      debugPrint('[FormBuilderService/fetchAllTemplates] Error: $e');
      return [];
    }
  }

  /// Fetch a single template with full structure (sections, fields, options).
  Future<Map<String, dynamic>?> fetchTemplateWithStructure(
    String templateId,
  ) async {
    try {
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active, status,
            theme_config, created_by, published_at, pushed_to_mobile_at,
            form_code, reference_prefix, reference_format, requires_reference,
            popup_enabled, popup_subtitle, popup_description,
            submitted_for_approval_by, submitted_for_approval_at,
            approved_by, approved_at, rejected_at, rejection_reason,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules,
              field_order, parent_field_id,
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
      final item = Map<String, dynamic>.from(res);
      final themeConfig = _asStringDynamicMap(item['theme_config']);
      if (_isLegacyArchivedFlag(themeConfig)) {
        item['status'] = 'archived';
      }
      return item;
    } catch (e) {
      debugPrint('[FormBuilderService/fetchTemplateWithStructure] Error: $e');
      return null;
    }
  }

  Future<List<String>> fetchCanonicalFieldKeys() async {
    final res = await _supabase
        .from('form_fields')
        .select('canonical_field_key')
        .not('canonical_field_key', 'is', null);

    final keys = <String>{};
    for (final row in (res as List<dynamic>)) {
      final key = (row['canonical_field_key'] as String?)?.trim();
      if (key != null && key.isNotEmpty) {
        keys.add(key);
      }
    }
    return keys.toList();
  }

  Future<void> savePopupMetadata({
    required String templateId,
    required bool popupEnabled,
    String? popupSubtitle,
    String? popupDescription,
  }) async {
    await _supabase
        .from('form_templates')
        .update({
          'popup_enabled': popupEnabled,
          'popup_subtitle': popupSubtitle?.trim().isEmpty == true
              ? null
              : popupSubtitle?.trim(),
          'popup_description': popupDescription?.trim().isEmpty == true
              ? null
              : popupDescription?.trim(),
        })
        .eq('template_id', templateId);
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
      debugPrint('[FormBuilderService/createTemplate] Error: $e');
      return null;
    }
  }

  /// Delete a template and all its children (cascade).
  /// Returns a result map: { success: bool, message: String }
  /// Blocks hard delete if active submissions exist; callers should archive instead.
  Future<Map<String, dynamic>> deleteTemplate(String templateId) async {
    try {
      // Safety check: block deletion if submissions reference this template.
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

      // Delete options, conditions, fields, sections, and then the template.
      await _cascadeDeleteStructure(templateId);
      await _supabase
          .from('form_templates')
          .delete()
          .eq('template_id', templateId);
      return {'success': true, 'message': 'Template deleted'};
    } catch (e) {
      debugPrint('[FormBuilderService/deleteTemplate] Error: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Force-delete a template regardless of submissions (for superadmin override).
  Future<bool> forceDeleteTemplate(String templateId) async {
    try {
      // Delete any form_submission rows that reference this template by form_type.
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

      // Remove the template structure and any submission values.
      await _cascadeDeleteStructure(templateId, includeValues: true);
      await _supabase
          .from('form_templates')
          .delete()
          .eq('template_id', templateId);
      return true;
    } catch (e) {
      debugPrint('[FormBuilderService/forceDeleteTemplate] Error: $e');
      return false;
    }
  }

  // ================================================================
  // BATCH SAVE (clear & re-insert structure)
  // ================================================================

  Future<void> _insertNotification({
    required String templateId,
    required String templateName,
    required String changeType,
    required String changeSummary,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _supabase.from('form_template_notifications').insert({
        'template_id': templateId,
        'template_name': templateName,
        'change_type': changeType,
        'change_summary': changeSummary,
        if (details != null && details.isNotEmpty) 'details': details,
      });
    } catch (e) {
      debugPrint('[FormBuilderService/_insertNotification] Error: $e');
    }
  }

  /// Save the entire template structure (metadata + sections + fields + options).
  /// Upserts current data, then deletes orphaned rows removed in the builder.
  /// After a successful save, emits notifications for added/updated/deleted fields.
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
      await _supabase
          .from('form_templates')
          .update({
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
          })
          .eq('template_id', templateId);

      // Refresh child rows, then reinsert the current structure.
      final existingFields = await _supabase
          .from('form_fields')
          .select('field_id, field_label, field_type')
          .eq('template_id', templateId);

      final existingOptions = await _supabase
          .from('form_field_options')
          .select('field_id, option_label')
          .inFilter('field_id', existingFields.map((f) => f['field_id'] as String).toList());

      if (existingFields.isNotEmpty) {
        final existingIds = existingFields
            .map((f) => f['field_id'] as String)
            .toList();
        await _supabase
            .from('form_field_options')
            .delete()
            .inFilter('field_id', existingIds);
        await _supabase
            .from('form_field_conditions')
            .delete()
            .inFilter('field_id', existingIds);
      }

      if (sections.isNotEmpty) {
        await _supabase
            .from('form_sections')
            .upsert(sections, onConflict: 'section_id');
      }

      final parentFields = fields
          .where((f) => f['parent_field_id'] == null)
          .toList();
      final childFields = fields
          .where((f) => f['parent_field_id'] != null)
          .toList();

      for (final f in parentFields) {
        await _supabase.from('form_fields').upsert(f, onConflict: 'field_id');
      }
      for (final f in childFields) {
        await _supabase.from('form_fields').upsert(f, onConflict: 'field_id');
      }

      if (options.isNotEmpty) {
        final seen = <String>{};
        final uniqueOptions = options.where((opt) {
          final key = '${opt['field_id']}__${(opt['option_value'] as String?)?.trim().toLowerCase() ?? ''}';
          return seen.add(key);
        }).toList();
        await _supabase.from('form_field_options').insert(uniqueOptions);
      }

      if (conditions.isNotEmpty) {
        await _supabase.from('form_field_conditions').insert(conditions);
      }

      final newFieldIds = fields.map((f) => f['field_id'] as String).toSet();
      final existingFieldIds = existingFields
          .map((f) => f['field_id'] as String)
          .toSet();
      final orphanFieldIds = existingFieldIds.difference(newFieldIds).toList();

      if (orphanFieldIds.isNotEmpty) {
        await _supabase
            .from('form_fields')
            .update({
              'validation_rules': {'_archived': true},
            })
            .inFilter('field_id', orphanFieldIds);
      }

      final newSectionIds = sections.map((s) => s['section_id'] as String).toSet();
      final existingSections = await _supabase
          .from('form_sections')
          .select('section_id')
          .eq('template_id', templateId);
      final existingSectionIds = existingSections
          .map((s) => s['section_id'] as String)
          .toSet();
      final orphanSectionIds = existingSectionIds.difference(newSectionIds).toList();

      if (orphanSectionIds.isNotEmpty) {
        await _supabase
            .from('form_sections')
            .delete()
            .inFilter('section_id', orphanSectionIds);
      }

      // ── Emit field-level notifications ──────────────────────────────
      final existingLabels = <String, String>{};
      final existingFieldTypes = <String, String>{};
      for (final f in existingFields) {
        final fid = f['field_id'] as String;
        existingLabels[fid] = (f['field_label'] as String?) ?? 'Untitled Question';
        existingFieldTypes[fid] = (f['field_type'] as String?) ?? 'text';
      }

      final existingOptionMap = <String, List<String>>{};
      for (final opt in existingOptions) {
        final fid = opt['field_id'] as String;
        final label = (opt['option_label'] as String?) ?? '';
        existingOptionMap.putIfAbsent(fid, () => []).add(label);
      }
      for (final list in existingOptionMap.values) {
        list.sort();
      }

      // Build new option map from the separate options parameter.
      final newOptionMap = <String, List<String>>{};
      for (final opt in options) {
        final fid = opt['field_id'] as String;
        final label = (opt['option_label'] as String?) ?? '';
        newOptionMap.putIfAbsent(fid, () => []).add(label);
      }
      for (final list in newOptionMap.values) {
        list.sort();
      }

      final addedFieldIds = newFieldIds.difference(existingFieldIds).toList();
      final deletedFieldIds = orphanFieldIds;

      for (final fid in addedFieldIds) {
        final field = fields.firstWhere((f) => f['field_id'] == fid, orElse: () => {});
        final label = (field['field_label'] as String?) ?? 'Untitled Question';
        await _insertNotification(
          templateId: templateId,
          templateName: formName,
          changeType: 'field_added',
          changeSummary: 'New field added: "$label" in "$formName"',
          details: {'field_id': fid, 'field_label': label},
        );
      }

      for (final fid in deletedFieldIds) {
        final label = existingLabels[fid] ?? 'Unknown field';
        await _insertNotification(
          templateId: templateId,
          templateName: formName,
          changeType: 'field_deleted',
          changeSummary: 'Field removed: "$label" from "$formName"',
          details: {'field_id': fid, 'field_label': label},
        );
      }

      // Only flag as updated if the field's label, type, or options changed.
      final updatedFieldIds = <String>[];
      for (final fid in newFieldIds.intersection(existingFieldIds)) {
        final incoming = fields.firstWhere((f) => f['field_id'] == fid, orElse: () => {});
        final oldLabel = existingLabels[fid] ?? 'Untitled Question';
        final newLabel = (incoming['field_label'] as String?) ?? 'Untitled Question';
        final oldType = existingFieldTypes[fid] ?? 'text';
        final newType = (incoming['field_type'] as String?) ?? 'text';

        final oldOpts = existingOptionMap[fid] ?? <String>[];
        final newOpts = newOptionMap[fid] ?? <String>[];

        if (oldLabel != newLabel || oldType != newType || oldOpts != newOpts) {
          updatedFieldIds.add(fid);
        }
      }

      for (final fid in updatedFieldIds) {
        final label = existingLabels[fid] ?? 'Untitled Question';
        await _insertNotification(
          templateId: templateId,
          templateName: formName,
          changeType: 'field_updated',
          changeSummary: 'Field updated: "$label" in "$formName"',
          details: {'field_id': fid, 'field_label': label},
        );
      }

      // If something else (e.g. conditions only) changed without any
      // field add/delete/update, emit a generic update notice.
      if (addedFieldIds.isEmpty &&
          deletedFieldIds.isEmpty &&
          updatedFieldIds.isEmpty &&
          existingFieldIds.isNotEmpty) {
        await _insertNotification(
          templateId: templateId,
          templateName: formName,
          changeType: 'updated',
          changeSummary: '"$formName" was updated. Tap RELOAD to see the changes.',
          details: {'scope': 'conditions_or_metadata'},
        );
      }

      return true;
    } catch (e, stack) {
      debugPrint('[FormBuilderService/saveTemplateStructure] Error: $e');
      debugPrint('[FormBuilderService/saveTemplateStructure] Stack: $stack');
      lastSaveError = e.toString();
      return false;
    }
  }

  // ================================================================
  // PUBLISHING WORKFLOW
  // ================================================================

  /// Publish template so it is visible to admin staff in Manage Forms.
  Future<bool> publishTemplate(String templateId) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      // ignore: unused_local_variable
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({
            'status': 'published',
            'is_active': true,
            'published_at': DateTime.now().toIso8601String(),
          })
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      return true;
    } catch (e) {
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/publishTemplate] Error: $e');
      return false;
    }
  }

  /// Push published template to mobile app.
  Future<bool> pushToMobile(String templateId) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      // ignore: unused_local_variable
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({
            'status': 'pushed_to_mobile',
            'pushed_to_mobile_at': DateTime.now().toIso8601String(),
          })
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'pushed_to_mobile',
        changeSummary: '"$formName" has been pushed to mobile. Tap RELOAD to see the changes.',
      );

      return true;
    } catch (e) {
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/pushToMobile] Error: $e');
      return false;
    }
  }

  /// Revert a published or pushed template back to draft.
  Future<bool> unpublishTemplate(String templateId) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({'status': 'draft', 'is_active': false})
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'updated',
        changeSummary: '"$formName" has been reverted to draft and removed from mobile.',
      );

      return true;
    } catch (e) {
      if (_isStatusCheckConstraintError(e)) {
        try {
          await _setLegacyArchiveFlag(
            templateId,
            archived: false,
            setInactive: true,
            statusOverride: 'draft',
          );
          return true;
        } catch (fallbackError) {
          lastActionError = fallbackError.toString();
          debugPrint(
            'FormBuilderService.restoreTemplate fallback error: $fallbackError',
          );
          return false;
        }
      }
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/unpublishTemplate] Error: $e');
      return false;
    }
  }

  // ================================================================
  // APPROVAL WORKFLOW
  // ================================================================

  /// Submit a draft template for superadmin approval.
  /// Sets status='pending_approval' and records who submitted it.
  Future<bool> submitForApproval(String templateId, String submittedBy) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({
            'status': 'pending_approval',
            'is_active': false,
            'submitted_for_approval_by': submittedBy,
            'submitted_for_approval_at': DateTime.now().toIso8601String(),
            'approved_by': null,
            'approved_at': null,
            'rejected_at': null,
            'rejection_reason': null,
          })
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'submitted_for_approval',
        changeSummary: '"$formName" has been submitted for approval.',
        details: {'submitted_by': submittedBy},
      );

      return true;
    } catch (e) {
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/submitForApproval] Error: $e');
      return false;
    }
  }

  /// Approve a pending template. Sets status='published', is_active=true.
  Future<bool> approveTemplate(String templateId, String approverId) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({
            'status': 'published',
            'is_active': true,
            'published_at': DateTime.now().toIso8601String(),
            'approved_by': approverId,
            'approved_at': DateTime.now().toIso8601String(),
            'rejected_at': null,
            'rejection_reason': null,
          })
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'approved',
        changeSummary: '"$formName" has been approved and published.',
        details: {'approved_by': approverId},
      );

      return true;
    } catch (e) {
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/approveTemplate] Error: $e');
      return false;
    }
  }

  /// Reject a pending template. Sets status='draft', records rejection reason.
  Future<bool> rejectTemplate(String templateId, String reason) async {
    lastActionError = null;
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      final formName = templateData?['form_name'] as String? ?? 'Untitled Form';

      await _supabase
          .from('form_templates')
          .update({
            'status': 'draft',
            'is_active': false,
            'rejected_at': DateTime.now().toIso8601String(),
            'rejection_reason': reason,
          })
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'rejected',
        changeSummary: '"$formName" was rejected. Reason: $reason',
        details: {'rejection_reason': reason},
      );

      return true;
    } catch (e) {
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/rejectTemplate] Error: $e');
      return false;
    }
  }

  /// Fetch templates with pending_approval status.
  Future<List<Map<String, dynamic>>> fetchPendingApprovalTemplates() async {
    try {
      final res = await _supabase
          .from('form_templates')
          .select(
            'template_id, form_name, form_desc, status, '
            'created_by, created_at, submitted_for_approval_by, '
            'submitted_for_approval_at',
          )
          .eq('status', 'pending_approval')
          .order('submitted_for_approval_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[FormBuilderService/fetchPendingApprovalTemplates] Error: $e');
      return [];
    }
  }

  // ================================================================
  // ARCHIVE / RESTORE
  // ================================================================

  /// Archive a template to soft-remove it from admin and mobile views.
  /// Sets is_active = false and status = 'archived'.
  Future<bool> archiveTemplate(String templateId) async {
    lastActionError = null;
    var formName = 'Untitled Form';
    try {
      final templateData = await _supabase
          .from('form_templates')
          .select('form_name')
          .eq('template_id', templateId)
          .maybeSingle();
      if (templateData != null) {
        formName = templateData['form_name'] as String? ?? 'Untitled Form';
      }

      await _supabase
          .from('form_templates')
          .update({'status': 'archived', 'is_active': false})
          .eq('template_id', templateId);

      await _insertNotification(
        templateId: templateId,
        templateName: formName,
        changeType: 'archived',
        changeSummary: 'Form "$formName" has been archived.',
      );

      return true;
    } catch (e) {
      if (_isStatusCheckConstraintError(e)) {
        try {
          await _setLegacyArchiveFlag(
            templateId,
            archived: true,
            setInactive: true,
            statusOverride: 'draft',
          );
          await _insertNotification(
            templateId: templateId,
            templateName: formName,
            changeType: 'archived',
            changeSummary: 'Form "$formName" has been archived.',
          );
          return true;
        } catch (fallbackError) {
          lastActionError = fallbackError.toString();
          debugPrint(
            'FormBuilderService.archiveTemplate fallback error: $fallbackError',
          );
          return false;
        }
      }
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/archiveTemplate] Error: $e');
      return false;
    }
  }

  /// Restore an archived template back to draft.
  Future<bool> restoreTemplate(String templateId) async {
    lastActionError = null;
    try {
      await _supabase
          .from('form_templates')
          .update({'status': 'draft', 'is_active': false})
          .eq('template_id', templateId);
      await _setLegacyArchiveFlag(templateId, archived: false);

      return true;
    } catch (e) {
      if (_isStatusCheckConstraintError(e)) {
        try {
          await _setLegacyArchiveFlag(
            templateId,
            archived: false,
            setInactive: true,
            statusOverride: 'draft',
          );
          return true;
        } catch (fallbackError) {
          lastActionError = fallbackError.toString();
          debugPrint(
            'FormBuilderService.restoreTemplate fallback error: $fallbackError',
          );
          return false;
        }
      }
      lastActionError = e.toString();
      debugPrint('[FormBuilderService/restoreTemplate] Error: $e');
      return false;
    }
  }

  // ================================================================
  // SUBMISSION CHECKS
  // ================================================================

  /// Count how many submissions exist for a template by form_name match.
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
      debugPrint('[FormBuilderService/countSubmissions] Error: $e');
      return 0;
    }
  }
}