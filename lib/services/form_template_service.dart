/// Loads form templates from Supabase and keeps them cached in memory.
///
/// Used by both mobile and web to load form definitions.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';

class FormTemplateService {
  static final FormTemplateService _instance = FormTemplateService._internal();
  factory FormTemplateService() => _instance;
  FormTemplateService._internal();

  final _supabase = Supabase.instance.client;

  // Cache templates in memory so repeated reads do not hit Supabase again.
  final Map<String, FormTemplate> _cache = {};
  List<FormTemplate>? _allTemplates;

  // Fetch all active templates for builders and readers.
  Future<List<FormTemplate>> fetchActiveTemplates({bool forceRefresh = false}) async {
    if (!forceRefresh && _allTemplates != null) return _allTemplates!;
    try {
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active,
            form_code, reference_prefix, reference_format, requires_reference,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules,
              field_order, canonical_field_key, parent_field_id,
              form_field_options(
                option_id, option_value, option_label, option_order, is_default
              ),
              form_field_conditions!form_field_conditions_field_fkey(
                condition_id, field_id, trigger_field_id, trigger_value, action
              )
            )
          ''')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final templates = (res as List<dynamic>)
          .map((t) => FormTemplate.fromMap(t as Map<String, dynamic>))
          .toList();

      debugPrint('[FormTemplateService/fetchActiveTemplates] Action: Loaded ${templates.length} templates');

      _allTemplates = templates;
      for (final t in templates) {
        _cache[t.templateId] = t;
      }
      return templates;
    } catch (e, stack) {
      debugPrint('[FormTemplateService/fetchActiveTemplates] Error: $e');
      debugPrint('[FormTemplateService/fetchActiveTemplates] Stack: $stack');
      return [];
    }
  }

  // Fetch a single template by ID when the caller already knows the record.
  Future<FormTemplate?> fetchTemplate(String templateId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(templateId)) return _cache[templateId];
    try {
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active,
            form_code, reference_prefix, reference_format, requires_reference,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules,
              field_order, canonical_field_key, parent_field_id,
              form_field_options(
                option_id, option_value, option_label, option_order, is_default
              ),
              form_field_conditions!form_field_conditions_field_fkey(
                condition_id, field_id, trigger_field_id, trigger_value, action
              )
            )
          ''')
          .eq('template_id', templateId)
          .single();

      final template = FormTemplate.fromMap(res);
      _cache[templateId] = template;
      return template;
    } catch (e) {
      debugPrint('[FormTemplateService/fetchTemplate] Error: $e');
      return null;
    }
  }

  // Fetch a template by name when the caller only has the display label.
  Future<FormTemplate?> fetchTemplateByName(String name) async {
    final templates = await fetchActiveTemplates();
    try {
      return templates.firstWhere(
        (t) => t.formName.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  // Clear cached templates after an admin changes form definitions.
  void clearCache() {
    _cache.clear();
    _allTemplates = null;
  }
}
