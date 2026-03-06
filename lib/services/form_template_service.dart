// lib/services/form_template_service.dart
// Loads form templates (with sections, fields, options, conditions) from Supabase.
// Caches in-memory so repeat calls are instant.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';

class FormTemplateService {
  static final FormTemplateService _instance = FormTemplateService._internal();
  factory FormTemplateService() => _instance;
  FormTemplateService._internal();

  final _supabase = Supabase.instance.client;

  // ── In-memory cache ───────────────────────────────────────
  final Map<String, FormTemplate> _cache = {};
  List<FormTemplate>? _allTemplates;

  // ── Fetch all active templates (lightweight list) ─────────
  Future<List<FormTemplate>> fetchActiveTemplates({bool forceRefresh = false}) async {
    if (!forceRefresh && _allTemplates != null) return _allTemplates!;
    try {
      debugPrint('🔍 Fetching templates from Supabase...');
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, placeholder,
              form_field_options(
                option_id, option_value, option_label, option_order, is_default
              ),
              form_field_conditions!form_field_conditions_field_fkey(
                condition_id, field_id, trigger_field_id, trigger_value, action
              )
            )
          ''')
          .eq('is_active', true);

      debugPrint('✅ Raw response: ${res.toString().substring(0, res.toString().length > 200 ? 200 : res.toString().length)}...');

      final templates = (res as List<dynamic>)
          .map((t) => FormTemplate.fromMap(t as Map<String, dynamic>))
          .toList();

      debugPrint('✅ Parsed ${templates.length} templates');
      for (final t in templates) {
        debugPrint('  - ${t.formName} (${t.sections.length} sections, ${t.allFields.length} fields)');
      }

      _allTemplates = templates;
      for (final t in templates) {
        _cache[t.templateId] = t;
      }
      return templates;
    } catch (e, stack) {
      debugPrint('❌ FormTemplateService.fetchActiveTemplates error: $e');
      debugPrint('Stack: $stack');
      return [];
    }
  }

  // ── Fetch single template by ID ───────────────────────────
  Future<FormTemplate?> fetchTemplate(String templateId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(templateId)) return _cache[templateId];
    try {
      final res = await _supabase
          .from('form_templates')
          .select('''
            template_id, form_name, form_desc, is_active,
            form_sections(
              section_id, template_id, section_name, section_desc,
              section_order, is_collapsible
            ),
            form_fields(
              field_id, template_id, section_id, field_name, field_label,
              field_type, is_required, validation_rules, default_value,
              field_order, autofill_source, placeholder,
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

  // ── Fetch template by name (e.g. "General Intake Sheet") ──
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

  // ── Build autofill map from user_profiles + addresses + socio ──
  // Returns a Map<fieldName, value> ready to populate form_data.
  Map<String, dynamic> buildAutofillMap({
    required FormTemplate template,
    required Map<String, dynamic> profile,       // user_profiles row
    required Map<String, dynamic> address,        // user_addresses row
    required Map<String, dynamic> socio,          // socio_economic_data row
    required List<Map<String, dynamic>> family,   // family_composition rows
    required List<Map<String, dynamic>> supporting, // supporting_family rows
  }) {
    final result = <String, dynamic>{};

    for (final field in template.allFields) {
      final src = field.autofillSource;
      if (src == null) continue;

      dynamic value;

      if (src.startsWith('address.')) {
        final col = src.substring('address.'.length);
        value = address[col];
      } else if (src.startsWith('socio.')) {
        final col = src.substring('socio.'.length);
        value = socio[col];
      } else if (src == 'signature_data') {
        value = profile['signature_data'];
      } else {
        value = profile[src];
      }

      if (value != null) {
        result[field.fieldName] = value;
      }
    }

    // Special complex fields
    result['__family_composition'] = family.map((m) => {
      'name': m['name'] ?? '',
      'relationship': m['relationship_of_relative'] ?? '',
      'birthdate': m['birthdate']?.toString() ?? '',
      'age': m['age']?.toString() ?? '',
      'gender': m['gender'] ?? '',
      'civil_status': m['civil_status'] ?? '',
      'education': m['education'] ?? '',
      'occupation': m['occupation'] ?? '',
      'allowance': m['allowance']?.toString() ?? '',
    }).toList();

    result['__supporting_family'] = supporting.map((m) => {
      'name': m['name'] ?? '',
      'relationship': m['relationship'] ?? '',
      'regular_sustento': m['regular_sustento']?.toString() ?? '',
    }).toList();

    result['__membership'] = {
      'solo_parent': profile['solo_parent'] ?? false,
      'pwd': profile['pwd'] ?? false,
      'four_ps_member': profile['four_ps_member'] ?? false,
      'phic_member': profile['phic_member'] ?? false,
    };

    result['__signature'] = profile['signature_data'];

    if (supporting.isNotEmpty) {
      result['monthly_alimony'] =
          supporting[0]['monthly_alimony']?.toString() ?? '';
    }

    return result;
  }

  // ── Clear cache (e.g. after admin creates/edits a template) ──
  void clearCache() {
    _cache.clear();
    _allTemplates = null;
  }
}
