// Form Template Service
// Loads form templates from Supabase and caches them in memory.
//
// Responsibilities:
// - Fetch form templates with sections, fields, options, and conditions
// - Cache templates to avoid repeated database queries
// - Build autofill maps from user profile data for form population
//
// Used by both mobile and web to load form definitions.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';

class FormTemplateService {
  static final FormTemplateService _instance = FormTemplateService._internal();
  factory FormTemplateService() => _instance;
  FormTemplateService._internal();

  final _supabase = Supabase.instance.client;

  // In-memory cache
  final Map<String, FormTemplate> _cache = {};
  List<FormTemplate>? _allTemplates;

  // Fetch all active templates from database
  Future<List<FormTemplate>> fetchActiveTemplates({bool forceRefresh = false}) async {
    if (!forceRefresh && _allTemplates != null) return _allTemplates!;
    try {
      debugPrint('Fetching templates from Supabase...');
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
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, canonical_field_key, placeholder, parent_field_id,
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

      debugPrint('Raw response: ${res.toString().substring(0, res.toString().length > 200 ? 200 : res.toString().length)}...');

      final templates = (res as List<dynamic>)
          .map((t) => FormTemplate.fromMap(t as Map<String, dynamic>))
          .toList();

      debugPrint('Parsed ${templates.length} templates');
      for (final t in templates) {
        debugPrint('  - ${t.formName} (${t.sections.length} sections, ${t.allFields.length} fields)');
      }

      _allTemplates = templates;
      for (final t in templates) {
        _cache[t.templateId] = t;
      }
      return templates;
    } catch (e, stack) {
      debugPrint('FormTemplateService.fetchActiveTemplates error: $e');
      debugPrint('Stack: $stack');
      return [];
    }
  }

  // Fetch single template by ID
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
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, canonical_field_key, placeholder, parent_field_id,
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
      debugPrint('FormTemplateService.fetchTemplate error: $e');
      return null;
    }
  }

  // Fetch template by name (e.g. "General Intake Sheet")
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

  // Clear cache (e.g. after admin creates/edits a template)
  void clearCache() {
    _cache.clear();
    _allTemplates = null;
  }
}
