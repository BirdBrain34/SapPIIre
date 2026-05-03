// Form Builder Screen
// Dashboard-style interface for superadmins to create/edit form templates.
//
// Layout: Template list panel (left) + Toolbar + Builder canvas (center)
// Supports: Multiple choice, checkboxes, dropdown, short answer, paragraph,
//           linear scale, date, time, number, yes/no field types.
// Workflow: Draft → Publish (to admins) → Push to Mobile

import 'dart:math';
import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/services/form_builder_service.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/web/controllers/form_builder_controller.dart';
import 'package:sappiire/web/widgets/form_builder_widgets.dart';

// ── UUID v4 generator ──────────────────────────────────────
String _generateUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int s, int e) =>
      b.sublist(s, e).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

/// Convert a label to a snake_case slug for field/option values.
String _slugify(String label) =>
    label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

// ── Field type labels and icons for the builder ─────────────
const _typeLabels = <FormFieldType, String>{
  FormFieldType.radio: 'Multiple Choice',
  FormFieldType.checkbox: 'Checkboxes',
  FormFieldType.dropdown: 'Dropdown',
  FormFieldType.text: 'Short Answer',
  FormFieldType.paragraph: 'Paragraph',
  FormFieldType.linearScale: 'Linear Scale',
  FormFieldType.date: 'Date',
  FormFieldType.time: 'Time',
  FormFieldType.number: 'Number',
  FormFieldType.boolean: 'Yes / No',
  FormFieldType.signature: 'Signature',
  FormFieldType.memberTable: 'Member Table',
};

const _typeIcons = <FormFieldType, IconData>{
  FormFieldType.radio: Icons.radio_button_checked,
  FormFieldType.checkbox: Icons.check_box_outlined,
  FormFieldType.dropdown: Icons.arrow_drop_down_circle_outlined,
  FormFieldType.text: Icons.short_text,
  FormFieldType.paragraph: Icons.notes,
  FormFieldType.linearScale: Icons.linear_scale,
  FormFieldType.date: Icons.calendar_today,
  FormFieldType.time: Icons.access_time,
  FormFieldType.number: Icons.pin,
  FormFieldType.boolean: Icons.toggle_on_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.memberTable: Icons.table_chart_outlined,
};

const _systemTypeLabels = <FormFieldType, String>{
  FormFieldType.computed: 'Computed',
  FormFieldType.conditional: 'Conditional',
  FormFieldType.membershipGroup: 'Membership Group',
  FormFieldType.familyTable: 'Family Table',
  FormFieldType.supportingFamilyTable: 'Supporting Family Table',
  FormFieldType.signature: 'Signature',
  FormFieldType.unknown: 'Unknown',
};

const _systemTypeIcons = <FormFieldType, IconData>{
  FormFieldType.computed: Icons.calculate_outlined,
  FormFieldType.conditional: Icons.device_hub_outlined,
  FormFieldType.membershipGroup: Icons.group_outlined,
  FormFieldType.familyTable: Icons.table_chart_outlined,
  FormFieldType.supportingFamilyTable: Icons.table_chart_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.unknown: Icons.help_outline,
};

const _standardProfileCanonicalKeys = <({String key, String label})>[
  (key: 'last_name', label: 'Last Name'),
  (key: 'first_name', label: 'First Name'),
  (key: 'middle_name', label: 'Middle Name'),
  (key: 'date_of_birth', label: 'Date of Birth'),
  (key: 'age', label: 'Age'),
  (key: 'kasarian_sex', label: 'Sex / Kasarian'),
  (key: 'estadong_sibil_civil_status', label: 'Civil Status / Estadong Sibil'),
  (key: 'lugar_ng_kapanganakan_place_of_birth', label: 'Place of Birth'),
  (key: 'cp_number', label: 'Phone Number / CP Number'),
  (key: 'email_address', label: 'Email Address'),
  (
    key: 'house_number_street_name_phase_purok',
    label: 'House No. / Street / Purok',
  ),
  (key: 'barangay', label: 'Barangay'),
  (key: 'subdivison_', label: 'Subdivision'),
  (key: 'signature', label: 'Signature'),
];

const _canonicalKeyEligibleTypes = <FormFieldType>{
  FormFieldType.text,
  FormFieldType.number,
  FormFieldType.date,
  FormFieldType.dropdown,
  FormFieldType.radio,
  FormFieldType.boolean,
};

class _ReferenceToken {
  final String label;
  final String token;
  final String hint;
  final String group;

  const _ReferenceToken(this.label, this.token, this.hint, this.group);
}

const _referenceTokens = <_ReferenceToken>[
  _ReferenceToken('Form Code', '{FORMCODE}', 'GIS', 'Form Info'),
  _ReferenceToken('Year (2026)', '{YYYY}', '2026', 'Date'),
  _ReferenceToken('Year Short (26)', '{YY}', '26', 'Date'),
  _ReferenceToken('Month Number (03)', '{MM}', '03', 'Date'),
  _ReferenceToken('Month Short (MAR)', '{MON}', 'MAR', 'Date'),
  _ReferenceToken('Day (26)', '{DD}', '26', 'Date'),
  _ReferenceToken('Day of Year (085)', '{DDD}', '085', 'Date'),
  _ReferenceToken('Quarter (1)', '{Q}', '1', 'Date'),
  _ReferenceToken('Week Number (13)', '{WW}', '13', 'Date'),
  _ReferenceToken('ISO Week (13)', '{IW}', '13', 'Date'),
  _ReferenceToken('Hour (14)', '{HH24}', '14', 'Time'),
  _ReferenceToken('Minute (30)', '{MI}', '30', 'Time'),
  _ReferenceToken('Second (00)', '{SS}', '00', 'Time'),
  _ReferenceToken(
    'Counter 8-digit (00000001)',
    '{########}',
    '00000001',
    'Counter',
  ),
  _ReferenceToken('Counter 6-digit (000001)', '{######}', '000001', 'Counter'),
  _ReferenceToken('Counter 4-digit (0001)', '{####}', '0001', 'Counter'),
  _ReferenceToken('Counter 3-digit (001)', '{###}', '001', 'Counter'),
  _ReferenceToken('Counter 2-digit (01)', '{##}', '01', 'Counter'),
  _ReferenceToken('Counter (1)', '{#}', '1', 'Counter'),
];

const _referenceTokenGroups = <String>['Form Info', 'Date', 'Time', 'Counter'];

// ── Mutable builder models (file-private) ───────────────────
class _BuilderOption {
  String id;
  String label;
  int order;

  _BuilderOption({String? id, this.label = 'Option', this.order = 0})
    : id = id ?? _generateUuid();
}

class _BuilderColumn {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  int order;
  List<_BuilderOption> options;
  String? dbMapKey;
  String? ageFromColumnId;

  _BuilderColumn({
    String? id,
    this.label = 'Column',
    String? fieldName,
    this.type = FormFieldType.text,
    this.order = 0,
    List<_BuilderOption>? options,
    this.dbMapKey,
    this.ageFromColumnId,
  }) : id = id ?? _generateUuid(),
       fieldName = fieldName ?? 'col_${_generateUuid().substring(0, 8)}',
       options = options ?? [];

  bool get isCoreColumn => dbMapKey != null;
}

class _BuilderCondition {
  String triggerFieldId;
  String triggerValue;
  String action;

  _BuilderCondition({
    this.triggerFieldId = '',
    this.triggerValue = '',
    this.action = 'show',
  });
}

class _BuilderField {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  bool isRequired;
  String? placeholder;
  String? canonicalFieldKey;
  int order;
  List<_BuilderOption> options;
  List<_BuilderColumn> columns;
  int scaleMin;
  int scaleMax;
  String formula;
  String? ageFromFieldId;
  _BuilderCondition condition;

  _BuilderField({
    String? id,
    this.label = 'Untitled Question',
    String? fieldName,
    this.type = FormFieldType.radio,
    this.isRequired = false,
    this.placeholder,
    this.canonicalFieldKey,
    this.order = 0,
    List<_BuilderOption>? options,
    List<_BuilderColumn>? columns,
    this.scaleMin = 1,
    this.scaleMax = 5,
    this.formula = '',
    this.ageFromFieldId,
    _BuilderCondition? condition,
  }) : id = id ?? _generateUuid(),
       fieldName = fieldName ?? 'field_${_generateUuid().substring(0, 8)}',
       options = options ?? [_BuilderOption(label: 'Option 1', order: 0)],
       columns = columns ?? [],
       condition = condition ?? _BuilderCondition();

  bool get hasOptions =>
      type == FormFieldType.radio ||
      type == FormFieldType.checkbox ||
      type == FormFieldType.dropdown;
}

class _BuilderSection {
  String id;
  String name;
  String? description;
  int order;
  List<_BuilderField> fields;

  _BuilderSection({
    String? id,
    this.name = 'Untitled Section',
    this.description,
    this.order = 0,
    List<_BuilderField>? fields,
  }) : id = id ?? _generateUuid(),
       fields = fields ?? [];
}

// ═══════════════════════════════════════════════════════════════
// FORM BUILDER SCREEN
// ═══════════════════════════════════════════════════════════════
class FormBuilderScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;
  final String? editTemplateId;

  const FormBuilderScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
    this.editTemplateId,
  });

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

enum _TemplateListFilter { all, active, draft, published, archived }

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  final _service = FormBuilderService();
  final _authService = WebAuthService();
  final _scrollCtrl = ScrollController();
  final PageStorageBucket _canvasStorageBucket = PageStorageBucket();
  late final FormBuilderController _controller;
  double _lastCanvasOffset = 0.0;

  // Template list
  List<Map<String, dynamic>> _templates = [];
  bool _isLoadingList = true;
  _TemplateListFilter _templateListFilter = _TemplateListFilter.all;

  // Active builder state
  String? _activeTemplateId;
  String _formName = '';
  String _formDesc = '';
  String _formCode = '';
  String _referencePrefix = '';
  String _referenceFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
  bool _requiresReference = true;
  String _formStatus = 'draft';
  List<_BuilderSection> _sections = [];

  // ── Popup intro state (new) ────────────────────────────────
  bool _popupEnabled = false;
  String _popupSubtitle = '';
  String _popupDescription = '';

  // Selection tracking
  int? _activeSectionIdx;
  int? _activeFieldIdx;

  // Flags
  bool _isSaving = false;
  bool _isLoadingTemplate = false;
  bool _hasUnsavedChanges = false;
  List<({String key, String label})> _availableCanonicalKeys = const [];
  bool _isLoadingCanonicalKeys = false;

  // Text controller cache (prevents cursor jump on rebuild)
  final Map<String, TextEditingController> _ctrls = {};

  TextEditingController _ctrl(String key, String initial) {
    return _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  void _clearCtrls() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
  }

  String _sanitizeCode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length > 10 ? cleaned.substring(0, 10) : cleaned;
  }

  List<String> _referenceFormatParts() {
    if (_referenceFormat.isEmpty) return const [];
    return RegExp(
      r'(\{[^{}]+\}|.)',
    ).allMatches(_referenceFormat).map((m) => m.group(0)!).toList();
  }

  void _appendReferenceToken(String token) {
    setState(() {
      _referenceFormat = '$_referenceFormat$token';
      _hasUnsavedChanges = true;
    });
  }

  void _appendReferenceSeparator(String separator) {
    setState(() {
      _referenceFormat = '$_referenceFormat$separator';
      _hasUnsavedChanges = true;
    });
  }

  void _removeReferencePartAt(int index) {
    final parts = _referenceFormatParts();
    if (index < 0 || index >= parts.length) return;
    setState(() {
      parts.removeAt(index);
      _referenceFormat = parts.join();
      _hasUnsavedChanges = true;
    });
  }

  String _referencePreview() {
    final now = DateTime.now();
    var ref = _referenceFormat;
    final prefix = _referencePrefix.trim().isNotEmpty
        ? _referencePrefix.trim().toUpperCase()
        : (_formCode.trim().isNotEmpty
              ? _formCode.trim().toUpperCase()
              : 'FORM');

    String pad(int v, int n) => v.toString().padLeft(n, '0');
    final yearStart = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(yearStart).inDays + 1;
    final quarter = ((now.month - 1) ~/ 3) + 1;

    ref = ref.replaceAll('{FORMCODE}', prefix);
    ref = ref.replaceAll('{YYYY}', now.year.toString());
    ref = ref.replaceAll('{YY}', now.year.toString().substring(2));
    ref = ref.replaceAll('{MM}', pad(now.month, 2));
    ref = ref.replaceAll(
      '{MON}',
      const [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ][now.month - 1],
    );
    ref = ref.replaceAll(
      '{MONTH}',
      const [
        'JANUARY',
        'FEBRUARY',
        'MARCH',
        'APRIL',
        'MAY',
        'JUNE',
        'JULY',
        'AUGUST',
        'SEPTEMBER',
        'OCTOBER',
        'NOVEMBER',
        'DECEMBER',
      ][now.month - 1],
    );
    ref = ref.replaceAll('{DD}', pad(now.day, 2));
    ref = ref.replaceAll('{DDD}', pad(dayOfYear, 3));
    ref = ref.replaceAll('{Q}', '$quarter');
    ref = ref.replaceAll('{WW}', pad(((dayOfYear - 1) ~/ 7) + 1, 2));
    ref = ref.replaceAll('{IW}', pad(((dayOfYear - 1) ~/ 7) + 1, 2));
    ref = ref.replaceAll('{HH24}', pad(now.hour, 2));
    ref = ref.replaceAll('{MI}', pad(now.minute, 2));
    ref = ref.replaceAll('{SS}', pad(now.second, 2));
    ref = ref.replaceAll('{########}', '????????');
    ref = ref.replaceAll('{######}', '??????');
    ref = ref.replaceAll('{####}', '????');
    ref = ref.replaceAll('{###}', '???');
    ref = ref.replaceAll('{##}', '??');
    ref = ref.replaceAll('{#}', '?');
    return ref;
  }

  @override
  void initState() {
    super.initState();
    _controller = FormBuilderController(
      cswdId: widget.cswd_id,
      role: widget.role,
      displayName: widget.displayName,
      editTemplateId: widget.editTemplateId,
    );
    _controller.attachContext(context);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        _lastCanvasOffset = _scrollCtrl.offset;
      }
    });
    _controller.init();
  }

  void _setStatePreserveCanvasScroll(VoidCallback fn) {
    final targetOffset = _scrollCtrl.hasClients
        ? _scrollCtrl.offset
        : _lastCanvasOffset;

    if (!mounted) return;
    super.setState(fn);

    void restoreOffset() {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, max).toDouble();
      if ((_scrollCtrl.offset - clamped).abs() > 0.5) {
        _scrollCtrl.jumpTo(clamped);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreOffset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restoreOffset();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _clearCtrls();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data Loading ────────────────────────────────────────────
  Future<void> _loadTemplateList() async {
    setState(() => _isLoadingList = true);
    final templates = await _service.fetchAllTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _isLoadingList = false;
    });
  }

  Future<void> _loadCanonicalKeys() async {
    if (mounted) setState(() => _isLoadingCanonicalKeys = true);
    try {
      final dbKeys = (await _service.fetchCanonicalFieldKeys()).toSet();

      for (final s in _standardProfileCanonicalKeys) {
        dbKeys.add(s.key);
      }

      final labelMap = {
        for (final s in _standardProfileCanonicalKeys) s.key: s.label,
      };
      final merged = dbKeys.map((k) {
        return (key: k, label: labelMap[k] ?? k);
      }).toList()..sort((a, b) => a.key.compareTo(b.key));

      if (mounted) {
        setState(() {
          _availableCanonicalKeys = merged;
          _isLoadingCanonicalKeys = false;
        });
      }
    } catch (e) {
      debugPrint('_loadCanonicalKeys error: $e');
      if (mounted) {
        setState(() {
          _availableCanonicalKeys = List.of(_standardProfileCanonicalKeys);
          _isLoadingCanonicalKeys = false;
        });
      }
    }
  }

  Future<void> _loadTemplate(String templateId) async {
    setState(() => _isLoadingTemplate = true);
    _clearCtrls();

    final data = await _service.fetchTemplateWithStructure(templateId);
    if (!mounted) return;
    if (data == null) {
      setState(() => _isLoadingTemplate = false);
      return;
    }

    final rawSections =
        (data['form_sections'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => ((a['section_order'] as int?) ?? 0).compareTo(
              (b['section_order'] as int?) ?? 0,
            ),
          );
    final rawFields = (data['form_fields'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((f) {
          final vr = f['validation_rules'] as Map<String, dynamic>?;
          return vr == null || vr['_archived'] != true;
        })
        .toList();

    final childFields = rawFields
        .where((f) => f['parent_field_id'] != null)
        .toList();
    final topLevelFields = rawFields
        .where((f) => f['parent_field_id'] == null)
        .toList();

    final childrenByParent = <String, List<Map<String, dynamic>>>{};
    for (final cf in childFields) {
      final pid = cf['parent_field_id'] as String;
      childrenByParent.putIfAbsent(pid, () => []).add(cf);
    }

    final sections = rawSections.map((s) {
      final sFields =
          topLevelFields
              .where((f) => f['section_id'] == s['section_id'])
              .toList()
            ..sort(
              (a, b) => ((a['field_order'] as int?) ?? 0).compareTo(
                (b['field_order'] as int?) ?? 0,
              ),
            );

      return _BuilderSection(
        id: s['section_id'] as String,
        name: s['section_name'] as String? ?? 'Untitled Section',
        description: s['section_desc'] as String?,
        order: (s['section_order'] as int?) ?? 0,
        fields: sFields.map((f) {
          final rawOpts =
              (f['form_field_options'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>()
                ..sort(
                  (a, b) => ((a['option_order'] as int?) ?? 0).compareTo(
                    (b['option_order'] as int?) ?? 0,
                  ),
                );

          List<_BuilderColumn> columns = [];
          final fid = f['field_id'] as String;
          final ftype = f['field_type'] as String? ?? '';
          if ((ftype == 'member_table' || ftype == 'family_table') &&
              childrenByParent.containsKey(fid)) {
            final childList = childrenByParent[fid]!
              ..sort(
                (a, b) => ((a['field_order'] as int?) ?? 0).compareTo(
                  (b['field_order'] as int?) ?? 0,
                ),
              );
            columns = childList.map((cf) {
              final colOpts =
                  (cf['form_field_options'] as List<dynamic>? ?? [])
                      .cast<Map<String, dynamic>>()
                    ..sort(
                      (a, b) => ((a['option_order'] as int?) ?? 0).compareTo(
                        (b['option_order'] as int?) ?? 0,
                      ),
                    );
              final vr = cf['validation_rules'] as Map<String, dynamic>?;
              final ageFromCol = (vr?['age_from_column'] as String?)?.trim();
              return _BuilderColumn(
                id: cf['field_id'] as String,
                label: cf['field_label'] as String? ?? '',
                fieldName: cf['field_name'] as String? ?? '',
                type: FormFieldType.fromString(
                  cf['field_type'] as String? ?? 'text',
                ),
                order: (cf['field_order'] as int?) ?? 0,
                dbMapKey: vr?['db_map_key'] as String?,
                ageFromColumnId: (ageFromCol != null && ageFromCol.isNotEmpty)
                    ? ageFromCol
                    : null,
                options: colOpts
                    .map(
                      (o) => _BuilderOption(
                        id: o['option_id'] as String,
                        label: o['option_label'] as String? ?? '',
                        order: (o['option_order'] as int?) ?? 0,
                      ),
                    )
                    .toList(),
              );
            }).toList();
          }

          final vr = f['validation_rules'] as Map<String, dynamic>?;
          final ageFromField = (vr?['age_from_field'] as String?)?.trim();
          final rawConditions =
              (f['form_field_conditions'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
          Map<String, dynamic>? showCondition;
          for (final c in rawConditions) {
            if ((c['action'] as String? ?? 'show') == 'show') {
              showCondition = c;
              break;
            }
          }
          showCondition ??= rawConditions.isNotEmpty
              ? rawConditions.first
              : null;

          return _BuilderField(
            id: f['field_id'] as String,
            label: f['field_label'] as String? ?? '',
            fieldName: f['field_name'] as String? ?? '',
            type: FormFieldType.fromString(
              f['field_type'] as String? ?? 'text',
            ),
            isRequired: (f['is_required'] as bool?) ?? false,
            placeholder: f['placeholder'] as String?,
            canonicalFieldKey: f['field_type'] == 'signature'
                ? 'signature'
                : f['canonical_field_key'] as String?,
            order: (f['field_order'] as int?) ?? 0,
            columns: columns,
            formula: (vr?['formula'] as String?) ?? '',
            ageFromFieldId: (ageFromField != null && ageFromField.isNotEmpty)
                ? ageFromField
                : null,
            condition: _BuilderCondition(
              triggerFieldId:
                  (showCondition?['trigger_field_id'] as String?) ?? '',
              triggerValue: (showCondition?['trigger_value'] as String?) ?? '',
              action: (showCondition?['action'] as String?) ?? 'show',
            ),
            options: rawOpts
                .map(
                  (o) => _BuilderOption(
                    id: o['option_id'] as String,
                    label: o['option_label'] as String? ?? '',
                    order: (o['option_order'] as int?) ?? 0,
                  ),
                )
                .toList(),
          );
        }).toList(),
      );
    }).toList();

    setState(() {
      _activeTemplateId = templateId;
      _formName = data['form_name'] as String? ?? 'Untitled Form';
      _formDesc = data['form_desc'] as String? ?? '';
      _formCode = _sanitizeCode(
        data['form_code'] as String? ?? _slugify(_formName).toUpperCase(),
      );
      _referencePrefix = _sanitizeCode(
        data['reference_prefix'] as String? ?? _formCode,
      );
      _referenceFormat =
          (data['reference_format'] as String?)?.trim().isNotEmpty == true
          ? data['reference_format'] as String
          : '{FORMCODE}-{YYYY}-{MM}-{####}';
      _requiresReference = (data['requires_reference'] as bool?) ?? true;
      _formStatus = data['status'] as String? ?? 'draft';
      _sections = sections;
      // ── Load popup fields ──
      _popupEnabled = (data['popup_enabled'] as bool?) ?? false;
      _popupSubtitle = data['popup_subtitle'] as String? ?? '';
      _popupDescription = data['popup_description'] as String? ?? '';
      _activeSectionIdx = null;
      _activeFieldIdx = null;
      _hasUnsavedChanges = false;
      _isLoadingTemplate = false;
    });
  }

  // ── CRUD Operations ─────────────────────────────────────────
  Future<void> _createNewTemplate() async {
    const defaultFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
    final id = await _service.createTemplate(
      formName: 'Untitled Form',
      formDesc: '',
      createdBy: widget.cswd_id,
      formCode: 'UNTITLEDFORM',
      referencePrefix: 'UNTITLEDFORM',
      referenceFormat: defaultFormat,
      requiresReference: true,
    );
    if (id == null || !mounted) return;
    await _loadTemplateList();
    _clearCtrls();

    setState(() {
      _activeTemplateId = id;
      _formName = 'Untitled Form';
      _formDesc = '';
      _formCode = 'UNTITLEDFORM';
      _referencePrefix = 'UNTITLEDFORM';
      _referenceFormat = defaultFormat;
      _requiresReference = true;
      _formStatus = 'draft';
      // ── Reset popup fields ──
      _popupEnabled = false;
      _popupSubtitle = '';
      _popupDescription = '';
      _sections = [
        _BuilderSection(
          name: 'Section 1',
          order: 0,
          fields: [_BuilderField(label: 'Question 1', order: 0)],
        ),
      ];
      _activeSectionIdx = 0;
      _activeFieldIdx = 0;
      _hasUnsavedChanges = true;
      _isLoadingTemplate = false;
    });
  }

  Future<void> _saveTemplate() async {
    if (_activeTemplateId == null) return;
    setState(() => _isSaving = true);

    final dbSections = <Map<String, dynamic>>[];
    final dbFields = <Map<String, dynamic>>[];
    final dbOptions = <Map<String, dynamic>>[];
    final dbConditions = <Map<String, dynamic>>[];

    for (var si = 0; si < _sections.length; si++) {
      final section = _sections[si];
      dbSections.add({
        'section_id': section.id,
        'template_id': _activeTemplateId,
        'section_name': section.name,
        'section_desc': section.description,
        'section_order': si,
        'is_collapsible': false,
      });

      for (var fi = 0; fi < section.fields.length; fi++) {
        final field = section.fields[fi];
        final validationRules = <String, dynamic>{};
        if (field.type == FormFieldType.computed && field.formula.isNotEmpty) {
          validationRules['formula'] = field.formula;
        }
        if (field.type == FormFieldType.number &&
            field.ageFromFieldId != null &&
            field.ageFromFieldId!.isNotEmpty) {
          validationRules['age_from_field'] = field.ageFromFieldId;
        }
        dbFields.add({
          'field_id': field.id,
          'template_id': _activeTemplateId,
          'section_id': section.id,
          'field_name': field.fieldName,
          'field_label': field.label,
          'field_type': field.type.toDbString(),
          'is_required': field.isRequired,
          'placeholder': field.placeholder,
          'canonical_field_key': field.canonicalFieldKey,
          'field_order': fi,
          if (validationRules.isNotEmpty) 'validation_rules': validationRules,
        });
        if (field.type == FormFieldType.signature) {
          dbFields.last['canonical_field_key'] = 'signature';
        }

        if (field.type == FormFieldType.memberTable ||
            field.type == FormFieldType.familyTable) {
          for (var ci = 0; ci < field.columns.length; ci++) {
            final col = field.columns[ci];
            final colValidationRules = <String, dynamic>{};
            if (col.dbMapKey != null) {
              colValidationRules['db_map_key'] = col.dbMapKey;
            }
            if (col.type == FormFieldType.number &&
                col.ageFromColumnId != null &&
                col.ageFromColumnId!.isNotEmpty) {
              colValidationRules['age_from_column'] = col.ageFromColumnId;
            }
            dbFields.add({
              'field_id': col.id,
              'template_id': _activeTemplateId,
              'section_id': section.id,
              'field_name': col.fieldName,
              'field_label': col.label,
              'field_type': col.type.toDbString(),
              'is_required': false,
              'placeholder': null,
              'field_order': ci,
              'parent_field_id': field.id,
              if (colValidationRules.isNotEmpty)
                'validation_rules': colValidationRules,
            });

            if (col.type == FormFieldType.dropdown) {
              for (var oi = 0; oi < col.options.length; oi++) {
                final opt = col.options[oi];
                dbOptions.add({
                  'option_id': opt.id,
                  'field_id': col.id,
                  'option_value': _slugify(opt.label),
                  'option_label': opt.label,
                  'option_order': oi,
                  'is_default': false,
                });
              }
            }
          }
        }

        if (field.hasOptions) {
          for (var oi = 0; oi < field.options.length; oi++) {
            final opt = field.options[oi];
            dbOptions.add({
              'option_id': opt.id,
              'field_id': field.id,
              'option_value': _slugify(opt.label),
              'option_label': opt.label,
              'option_order': oi,
              'is_default': false,
            });
          }
        }

        if (field.condition.triggerFieldId.isNotEmpty &&
            field.condition.triggerValue.isNotEmpty) {
          dbConditions.add({
            'field_id': field.id,
            'trigger_field_id': field.condition.triggerFieldId,
            'trigger_value': field.condition.triggerValue,
            'action': field.condition.action,
          });
        }
      }
    }

    final normalizedCode = _sanitizeCode(
      _formCode.trim().isNotEmpty
          ? _formCode
          : _slugify(_formName).toUpperCase(),
    );
    final normalizedPrefix = _sanitizeCode(
      _referencePrefix.trim().isNotEmpty ? _referencePrefix : normalizedCode,
    );

    final success = await _service.saveTemplateStructure(
      templateId: _activeTemplateId!,
      formName: _formName,
      formDesc: _formDesc,
      formCode: normalizedCode,
      referencePrefix: normalizedPrefix,
      referenceFormat: _referenceFormat.trim().isNotEmpty
          ? _referenceFormat.trim()
          : '{FORMCODE}-{YYYY}-{MM}-{####}',
      requiresReference: _requiresReference,
      sections: dbSections,
      fields: dbFields,
      options: dbOptions,
      conditions: dbConditions,
    );

    // ── Save popup fields to form_templates directly ──────────
    // Popup data is template metadata, not a field row, so it is
    // written separately to form_templates after the main save.
    if (success) {
      try {
        await _service.savePopupMetadata(
          templateId: _activeTemplateId!,
          popupEnabled: _popupEnabled,
          popupSubtitle: _popupSubtitle,
          popupDescription: _popupDescription,
        );
      } catch (e) {
        debugPrint('Popup metadata save error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (success) _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Template saved'
              : 'Error saving template: ${_service.lastSaveError ?? "unknown"}',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _loadTemplateList();
  }

  Future<void> _publishTemplate() async {
    if (_activeTemplateId == null) return;

    final hasFields = _sections.any((s) => s.fields.isNotEmpty);
    if (!hasFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one section with a question before publishing.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_hasUnsavedChanges) await _saveTemplate();

    final confirmed = await _showConfirmDialog(
      title: 'Publish Form',
      message:
          'This will make the form visible to all admin users in their '
          '"Manage Forms" view. Continue?',
      confirmLabel: 'Publish',
      confirmColor: AppColors.highlight,
    );
    if (confirmed != true) return;

    final success = await _service.publishTemplate(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'published');
      await _loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplatePublished,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Form published ✓' : 'Error publishing'),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pushToMobile() async {
    if (_activeTemplateId == null) return;

    final confirmed = await _showConfirmDialog(
      title: 'Push to Mobile',
      message:
          'This will make the form available on the mobile app. '
          'Users will see it in their forms list. Continue?',
      confirmLabel: 'Push to Mobile',
      confirmColor: Colors.green,
    );
    if (confirmed != true) return;

    final success = await _service.pushToMobile(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'pushed_to_mobile');
      await _loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplatePushed,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Pushed to mobile ✓' : 'Error pushing'),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _archiveTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Archive Form',
      message:
          'This will remove the form from admins\' and mobile users\' '
          'view but keep all data intact for historical reference. Continue?',
      confirmLabel: 'Archive',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;

    final success = await _service.archiveTemplate(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'archived');
      await _loadTemplateList();

      await AuditLogService().log(
        actionType: kAuditTemplateArchived,
        category: kCategoryTemplate,
        severity: kSeverityWarning,
        actorId: widget.cswd_id,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Form archived ✓'
              : 'Error archiving: ${_service.lastActionError ?? "unknown error"}',
        ),
        backgroundColor: success ? Colors.orange : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _restoreTemplate() async {
    if (_activeTemplateId == null) return;
    final success = await _service.restoreTemplate(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'draft');
      await _loadTemplateList();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Form restored to draft ✓'
              : 'Error restoring: ${_service.lastActionError ?? "unknown error"}',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _unpublishTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Unpublish Form',
      message:
          'This will revert the form to draft status. It will no longer '
          'be visible to admins or mobile users. Continue?',
      confirmLabel: 'Unpublish',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;

    final success = await _service.unpublishTemplate(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'draft');
      await _loadTemplateList();
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Builder Actions ─────────────────────────────────────────
  void _addSection() {
    setState(() {
      _sections.add(
        _BuilderSection(
          name: 'Section ${_sections.length + 1}',
          order: _sections.length,
        ),
      );
      _hasUnsavedChanges = true;
    });
  }

  void _addField(int si) {
    final section = _sections[si];
    setState(() {
      section.fields.add(
        _BuilderField(
          label: 'Question ${section.fields.length + 1}',
          order: section.fields.length,
        ),
      );
      _activeSectionIdx = si;
      _activeFieldIdx = section.fields.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  static const _systemBlocks =
      <
        FormFieldType,
        ({String label, String fieldName, String desc, IconData icon})
      >{
        FormFieldType.membershipGroup: (
          label: 'Membership Group',
          fieldName: 'membership_group',
          desc: 'Solo Parent, PWD, 4Ps, PHIC checkboxes',
          icon: Icons.group_outlined,
        ),
        FormFieldType.computed: (
          label: 'Computed Field',
          fieldName: 'computed_field',
          desc: 'Auto-calculated value (income, expenses, etc.)',
          icon: Icons.calculate_outlined,
        ),
        FormFieldType.signature: (
          label: 'Signature',
          fieldName: 'signature',
          desc:
              'Applicant draws their signature on screen. Saved as a base64 image in field values.',
          icon: Icons.draw_outlined,
        ),
      };

  static const _familyTableCoreColumns =
      <({String label, String fieldName, String dbMapKey, FormFieldType type})>[
        (
          label: 'Name',
          fieldName: 'name',
          dbMapKey: 'name',
          type: FormFieldType.text,
        ),
        (
          label: 'Relationship',
          fieldName: 'relationship_of_relative',
          dbMapKey: 'relationship_of_relative',
          type: FormFieldType.text,
        ),
        (
          label: 'Birthdate',
          fieldName: 'birthdate',
          dbMapKey: 'birthdate',
          type: FormFieldType.date,
        ),
        (
          label: 'Age',
          fieldName: 'age',
          dbMapKey: 'age',
          type: FormFieldType.number,
        ),
        (
          label: 'Sex',
          fieldName: 'gender',
          dbMapKey: 'gender',
          type: FormFieldType.dropdown,
        ),
        (
          label: 'Civil Status',
          fieldName: 'civil_status',
          dbMapKey: 'civil_status',
          type: FormFieldType.dropdown,
        ),
        (
          label: 'Education',
          fieldName: 'education',
          dbMapKey: 'education',
          type: FormFieldType.dropdown,
        ),
        (
          label: 'Occupation',
          fieldName: 'occupation',
          dbMapKey: 'occupation',
          type: FormFieldType.text,
        ),
        (
          label: 'Allowance (₱)',
          fieldName: 'allowance',
          dbMapKey: 'allowance',
          type: FormFieldType.number,
        ),
      ];

  // ignore: unused_element
  void _addSystemField(int si, FormFieldType type) {
    final block = _systemBlocks[type];
    if (block == null) return;
    final section = _sections[si];

    final allFields = _sections.expand((s) => s.fields);
    if (const {
          FormFieldType.membershipGroup,
          FormFieldType.signature,
        }.contains(type) &&
        allFields.any((f) => f.type == type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A "${block.label}" block already exists in this form.',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    List<_BuilderColumn> columns = [];
    if (type == FormFieldType.familyTable) {
      columns = _familyTableCoreColumns
          .asMap()
          .entries
          .map(
            (e) => _BuilderColumn(
              label: e.value.label,
              fieldName: e.value.fieldName,
              type: e.value.type,
              order: e.key,
              dbMapKey: e.value.dbMapKey,
            ),
          )
          .toList();
    }

    setState(() {
      final generatedFieldName = type == FormFieldType.computed
          ? 'computed_${_generateUuid().substring(0, 8)}'
          : block.fieldName;
      section.fields.add(
        _BuilderField(
          label: block.label,
          fieldName: generatedFieldName,
          type: type,
          isRequired: false,
          canonicalFieldKey: type == FormFieldType.signature
              ? 'signature'
              : null,
          order: section.fields.length,
          options: [],
          columns: columns,
        ),
      );
      _activeSectionIdx = si;
      _activeFieldIdx = section.fields.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  void _showSystemBlockPicker() {
    final si = _controller.activeSectionIdx ?? (_controller.sections.isNotEmpty ? _controller.sections.length - 1 : null);
    if (si == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Intake Module',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'These are fixed system blocks with specialized rendering.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              ..._systemBlocks.entries.map((e) {
                final block = e.value;
                final exists = _controller.sections
                    .expand((s) => s.fields)
                    .any((f) => f.type == e.key);
                return ListTile(
                  leading: Icon(
                    block.icon,
                    color: exists ? AppColors.textMuted : AppColors.highlight,
                  ),
                  title: Text(
                    block.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: exists ? AppColors.textMuted : AppColors.textDark,
                    ),
                  ),
                  subtitle: e.key == FormFieldType.signature
                      ? Text(
                          exists ? 'Already added' : block.desc,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        )
                      : null,
                  enabled: !exists || e.key == FormFieldType.computed,
                  onTap: () {
                    Navigator.pop(ctx);
                    _controller.addSystemField(si, e.key);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _removeField(int si, int fi) {
    setState(() {
      _sections[si].fields.removeAt(fi);
      _activeFieldIdx = null;
      _hasUnsavedChanges = true;
    });
  }

  void _removeSection(int si) {
    setState(() {
      _sections.removeAt(si);
      _activeSectionIdx = null;
      _activeFieldIdx = null;
      _hasUnsavedChanges = true;
    });
  }

  void _duplicateField(int si, int fi) {
    final src = _sections[si].fields[fi];
    setState(() {
      _sections[si].fields.insert(
        fi + 1,
        _BuilderField(
          label: '${src.label} (copy)',
          type: src.type,
          isRequired: src.isRequired,
          placeholder: src.placeholder,
          canonicalFieldKey: src.canonicalFieldKey,
          ageFromFieldId: src.ageFromFieldId,
          order: fi + 1,
          options: src.options
              .map((o) => _BuilderOption(label: o.label))
              .toList(),
          condition: _BuilderCondition(
            triggerFieldId: src.condition.triggerFieldId,
            triggerValue: src.condition.triggerValue,
            action: src.condition.action,
          ),
        ),
      );
      _activeFieldIdx = fi + 1;
      _hasUnsavedChanges = true;
    });
  }

  void _moveField(int si, int fi, int dir) {
    final ni = fi + dir;
    if (ni < 0 || ni >= _sections[si].fields.length) return;
    setState(() {
      final f = _sections[si].fields.removeAt(fi);
      _sections[si].fields.insert(ni, f);
      _activeFieldIdx = ni;
      _hasUnsavedChanges = true;
    });
  }

  void _moveSection(int si, int dir) {
    final ni = si + dir;
    if (ni < 0 || ni >= _sections.length) return;
    setState(() {
      final s = _sections.removeAt(si);
      _sections.insert(ni, s);
      _activeSectionIdx = ni;
      _hasUnsavedChanges = true;
    });
  }

  void _moveColumn(_BuilderField field, int ci, int dir) {
    final ni = ci + dir;
    if (ni < 0 || ni >= field.columns.length) return;
    setState(() {
      final col = field.columns.removeAt(ci);
      field.columns.insert(ni, col);
      _hasUnsavedChanges = true;
    });
  }

  void _preserveScrollPosition(VoidCallback updateSelection) {
    _setStatePreserveCanvasScroll(updateSelection);
  }

  // ── Navigation ──────────────────────────────────────────────
  Future<bool> _confirmLeave() async {
    if (!_hasUnsavedChanges) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleLogout() async {
    if (!await _controller.confirmLeave()) return;
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ContentFadeRoute(page: const WorkerLoginScreen()),
      (route) => false,
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    if ((screenPath == 'Staff' ||
            screenPath == 'CreateStaff' ||
            screenPath == 'FormBuilder') &&
        widget.role != 'superadmin') {
      return;
    }
    Widget next;
    switch (screenPath) {
      case 'Dashboard':
        next = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
          onLogout: _handleLogout,
        );
        break;
      case 'Forms':
        next = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'Staff':
        next = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'CreateStaff':
        next = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'Applicants':
        next = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'AuditLogs':
        if (widget.role != 'superadmin') return;
        next = AuditLogsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      default:
        return;
    }
    _controller.confirmLeave().then((ok) {
      if (!ok || !mounted) return;
      Navigator.of(context).pushReplacement(ContentFadeRoute(page: next));
    });
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    _controller.attachContext(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return WebShell(
          activePath: 'FormBuilder',
          pageTitle: 'Form Builder',
          pageSubtitle: _controller.activeTemplateId != null
              ? '${_controller.formName}${_controller.hasUnsavedChanges ? '  •  unsaved changes' : ''}'
              : 'Create and manage form templates',
          role: widget.role,
          cswd_id: widget.cswd_id,
          displayName: widget.displayName,
          onLogout: _handleLogout,
          headerActions: _buildHeaderActions(),
          onNavigate: (path) => _navigateToScreen(context, path),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormBuilderTemplateListPanel(
                templates: _controller.templates,
                selectedTemplateId: _controller.activeTemplateId,
                isLoading: _controller.isLoadingList,
                filter: _controller.templateListFilter,
                onSelectTemplate: (id) async {
                  if (id == _controller.activeTemplateId) return;
                  if (!await _controller.confirmLeave()) return;
                  await _controller.loadTemplate(id);
                },
                onCreateNew: _controller.createNewTemplate,
                onFilterChanged: _controller.setTemplateListFilter,
              ),
              Expanded(
                child: _controller.activeTemplateId == null
                    ? _buildEmptyState()
                    : _controller.isLoadingTemplate
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.highlight,
                            ),
                          )
                        : _buildBuilderCanvas(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header Actions ──────────────────────────────────────────
  List<Widget> _buildHeaderActions() {
    if (_controller.activeTemplateId == null) return [];
    return [
      if (_controller.formStatus == 'draft') ...[
        FormBuilderHeaderButton(
          'Save Draft',
          Icons.save_outlined,
          onPressed: _controller.isSaving ? null : _controller.saveTemplate,
        ),
        const SizedBox(width: 8),
        FormBuilderHeaderButton(
          'Publish',
          Icons.publish,
          color: AppColors.highlight,
          onPressed: _controller.publishTemplate,
        ),
      ],
      if (_controller.formStatus == 'published') ...[
        FormBuilderHeaderButton(
          'Save',
          Icons.save_outlined,
          onPressed: _controller.isSaving ? null : _controller.saveTemplate,
        ),
        const SizedBox(width: 8),
        FormBuilderHeaderButton(
          'Push to Mobile',
          Icons.phone_android,
          color: Colors.green,
          onPressed: _controller.pushToMobile,
        ),
      ],
      if (_controller.formStatus == 'pushed_to_mobile') ...[
        FormBuilderHeaderButton(
          'Save',
          Icons.save_outlined,
          onPressed: _controller.isSaving ? null : _controller.saveTemplate,
        ),
      ],
      if (_controller.formStatus == 'archived') ...[
        FormBuilderHeaderButton(
          'Restore',
          Icons.restore,
          color: Colors.teal,
          onPressed: _controller.restoreTemplate,
        ),
      ],
    ];
  }

  // ═══════════════════════════════════════════════════════════
  // TEMPLATE LIST PANEL
  // ═══════════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildTemplateListPanel() {
    final visibleTemplates = _templates.where((t) {
      final status = (t['status'] as String?) ?? 'draft';
      final isArchived = status == 'archived';
      final isActive = (t['is_active'] as bool?) == true;

      return switch (_templateListFilter) {
        _TemplateListFilter.archived => isArchived,
        _TemplateListFilter.draft => status == 'draft',
        _TemplateListFilter.published => status == 'published',
        _TemplateListFilter.active => isActive && !isArchived,
        _TemplateListFilter.all => true,
      };
    }).toList();

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  color: AppColors.textDark,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My Templates',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _createNewTemplate,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.highlight,
                  tooltip: 'New Form',
                  iconSize: 22,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _templateListFilter == _TemplateListFilter.all,
                  onSelected: (_) {
                    setState(() {
                      _templateListFilter = _TemplateListFilter.all;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Active'),
                  selected: _templateListFilter == _TemplateListFilter.active,
                  onSelected: (_) {
                    setState(() {
                      _templateListFilter = _TemplateListFilter.active;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Draft'),
                  selected: _templateListFilter == _TemplateListFilter.draft,
                  onSelected: (_) {
                    setState(() {
                      _templateListFilter = _TemplateListFilter.draft;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Published'),
                  selected:
                      _templateListFilter == _TemplateListFilter.published,
                  onSelected: (_) {
                    setState(() {
                      _templateListFilter = _TemplateListFilter.published;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Archived'),
                  selected: _templateListFilter == _TemplateListFilter.archived,
                  onSelected: (_) {
                    setState(() {
                      _templateListFilter = _TemplateListFilter.archived;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingList
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.highlight,
                    ),
                  )
                : visibleTemplates.isEmpty
                ? _buildNoTemplates(filter: _templateListFilter)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: visibleTemplates.length,
                    itemBuilder: (_, i) =>
                        _buildTemplateListItem(visibleTemplates[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTemplates({required _TemplateListFilter filter}) {
    final emptyLabel = switch (filter) {
      _TemplateListFilter.archived => 'No archived templates',
      _TemplateListFilter.active => 'No active templates',
      _TemplateListFilter.draft => 'No draft templates',
      _TemplateListFilter.published => 'No published templates',
      _TemplateListFilter.all => 'No templates yet',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 48,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(emptyLabel, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _createNewTemplate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateListItem(Map<String, dynamic> t) {
    final id = t['template_id'] as String;
    final name = t['form_name'] as String? ?? 'Untitled';
    final status = t['status'] as String? ?? 'draft';
    final isActive = _activeTemplateId == id;

    final (Color statusClr, String statusLbl) = switch (status) {
      'published' => (Colors.blue, 'Published'),
      'pushed_to_mobile' => (Colors.green, 'Live'),
      'archived' => (Colors.grey, 'Archived'),
      _ => (Colors.orange, 'Draft'),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.highlight.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: AppColors.highlight.withOpacity(0.3))
            : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          Icons.description_outlined,
          color: isActive ? AppColors.highlight : AppColors.textMuted,
          size: 20,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: AppColors.textDark,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusClr,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(statusLbl, style: TextStyle(fontSize: 11, color: statusClr)),
          ],
        ),
        onTap: () async {
          if (id == _activeTemplateId) return;
          if (!await _confirmLeave()) return;
          _loadTemplate(id);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note,
            size: 80,
            color: AppColors.highlight.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          const Text(
            'Select a template or create a new one',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _createNewTemplate,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'New Form',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILDER CANVAS
  // ═══════════════════════════════════════════════════════════
  Widget _buildBuilderCanvas() {
    final activeSectionName = _controller.activeSectionIdx != null && _controller.activeSectionIdx! < _controller.sections.length
        ? _controller.sections[_controller.activeSectionIdx!].name
        : (_controller.sections.isNotEmpty ? _controller.sections.last.name : null);

    return PageStorage(
      bucket: _canvasStorageBucket,
      child: Container(
        color: AppColors.pageBg,
        child: Column(
          children: [
            FormBuilderCanvasToolbar(
              activeSectionName: activeSectionName,
              onAddQuestion: () {
                final targetSi = _controller.activeSectionIdx ?? (_controller.sections.isNotEmpty ? _controller.sections.length - 1 : null);
                if (targetSi != null) {
                  _controller.addField(targetSi);
                }
              },
              onAddIntakeModule: () => _showSystemBlockPicker(),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('form_builder_canvas_scroll'),
                controller: _scrollCtrl,
                primary: false,
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 680,
                    child: Column(
                      children: [
                        FormBuilderTitleCard(controller: _controller),
                        const SizedBox(height: 12),
                        for (var si = 0; si < _controller.sections.length; si++) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              children: [
                                FormBuilderSectionHeader(
                                  section: _controller.sections[si],
                                  sectionIndex: si,
                                  isActive: _controller.activeSectionIdx == si,
                                  sectionCount: _controller.sections.length,
                                  onTap: () => _setStatePreserveCanvasScroll(() => _controller.setActiveSectionAndField(si, null)),
                                  onMoveUp: () => _controller.moveSection(si, -1),
                                  onMoveDown: () => _controller.moveSection(si, 1),
                                  onDelete: () => _controller.removeSection(si),
                                  onChanged: _controller.markDirty,
                                  ctrl: _controller.ctrlLookup,
                                ),
                                for (var fi = 0; fi < _controller.sections[si].fields.length; fi++)
                                  FormBuilderFieldCard(
                                    field: _controller.sections[si].fields[fi],
                                    sectionIndex: si,
                                    fieldIndex: fi,
                                    isActive: _controller.activeSectionIdx == si && _controller.activeFieldIdx == fi,
                                    allSections: _controller.sections,
                                    availableCanonicalKeys: _controller.availableCanonicalKeys,
                                    isLoadingCanonicalKeys: _controller.isLoadingCanonicalKeys,
                                    onTap: () => _setStatePreserveCanvasScroll(() => _controller.setActiveSectionAndField(si, fi)),
                                    onDuplicate: () => _controller.duplicateField(si, fi),
                                    onDelete: () => _controller.removeField(si, fi),
                                    onMoveUp: () => _controller.moveField(si, fi, -1),
                                    onMoveDown: () => _controller.moveField(si, fi, 1),
                                    ctrlLookup: _controller.ctrlLookup,
                                    onFieldChanged: _controller.markDirty,
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FormBuilderAddSectionButton(onPressed: _controller.addSection),
                        const SizedBox(height: 16),
                        FormBuilderStatusCard(
                          formStatus: _controller.formStatus,
                          onUnpublish: _controller.unpublishTemplate,
                          onArchive: _controller.archiveTemplate,
                          onRestore: _controller.restoreTemplate,
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCanvasToolbar() {
    final targetSi =
        _activeSectionIdx ??
        (_sections.isNotEmpty ? _sections.length - 1 : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: targetSi != null ? () => _addField(targetSi) : null,
            icon: const Icon(
              Icons.add_circle_outline,
              size: 18,
              color: Colors.white,
            ),
            label: const Text(
              'Add Question',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: targetSi != null ? () => _showSystemBlockPicker() : null,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
            label: const Text(
              'Add Intake Module',
              style: TextStyle(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: const BorderSide(color: AppColors.highlight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const Spacer(),
          if (_activeSectionIdx != null)
            Text(
              'Active: ${_sections[_activeSectionIdx!].name}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TITLE CARD  (includes the popup section at the bottom)
  // ═══════════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildTitleCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Form name ──────────────────────────────────
            TextField(
              controller: _ctrl('formName', _formName),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: AppColors.textDark,
              ),
              decoration: const InputDecoration(
                hintText: 'Untitled Form',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.highlight, width: 2),
                ),
              ),
              onChanged: (v) {
                _formName = v;
                _hasUnsavedChanges = true;
              },
            ),
            const SizedBox(height: 8),
            // ── Description ────────────────────────────────
            TextField(
              controller: _ctrl('formDesc', _formDesc),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
              decoration: const InputDecoration(
                hintText: 'Form description',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.highlight, width: 1),
                ),
              ),
              onChanged: (v) {
                _formDesc = v;
                _hasUnsavedChanges = true;
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl('formCode', _formCode),
                    scrollPadding: EdgeInsets.zero,
                    decoration: InputDecoration(
                      labelText: 'Form Code',
                      hintText: 'GIS',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      _formCode = _sanitizeCode(v);
                      if (_referencePrefix.trim().isEmpty) {
                        _referencePrefix = _formCode;
                        _ctrl('referencePrefix', _referencePrefix).text =
                            _referencePrefix;
                      }
                      _hasUnsavedChanges = true;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ctrl('referencePrefix', _referencePrefix),
                    scrollPadding: EdgeInsets.zero,
                    decoration: InputDecoration(
                      labelText: 'Reference Prefix',
                      hintText: 'GIS',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      _referencePrefix = _sanitizeCode(v);
                      _hasUnsavedChanges = true;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 170,
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Needs Ref',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    value: _requiresReference,
                    onChanged: (v) {
                      setState(() {
                        _requiresReference = v;
                        _hasUnsavedChanges = true;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Reference Format ───────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reference Format',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _referenceFormatParts().isEmpty
                        ? const [
                            Text(
                              'No format tokens yet. Add tokens below.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ]
                        : List.generate(_referenceFormatParts().length, (i) {
                            final part = _referenceFormatParts()[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    part == ' ' ? 'space' : part,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _removeReferencePartAt(i),
                                    child: const Padding(
                                      padding: EdgeInsets.all(1),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._referenceTokenGroups.map((group) {
              final groupTokens = _referenceTokens
                  .where((t) => t.group == group)
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: groupTokens
                          .map(
                            (t) => OutlinedButton(
                              onPressed: () => _appendReferenceToken(t.token),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryBlue,
                                side: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                t.label,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Separators',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sep in const ['-', '/', '_', '.', ' '])
                  OutlinedButton(
                    onPressed: () => _appendReferenceSeparator(sep),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.cardBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      sep == ' ' ? 'space' : sep,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Reference preview ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _requiresReference
                          ? _referencePreview()
                          : 'Reference disabled for this form',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _requiresReference
                            ? AppColors.primaryBlue
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ══════════════════════════════════════════════
            // FORM INTRODUCTION POPUP SECTION
            // Sits at the bottom of the title card so it
            // feels like part of the form's metadata, not
            // a field. Saved to form_templates, not form_fields.
            // ══════════════════════════════════════════════
            const SizedBox(height: 16),
            const Divider(color: AppColors.cardBorder),
            const SizedBox(height: 4),

            // ── Toggle row ────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _popupEnabled
                        ? AppColors.primaryBlue.withOpacity(0.1)
                        : AppColors.pageBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: _popupEnabled
                        ? AppColors.primaryBlue
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Form Introduction Popup',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _popupEnabled
                              ? AppColors.textDark
                              : AppColors.textMuted,
                        ),
                      ),
                      Text(
                        _popupEnabled
                            ? 'Shown on mobile before the user scans the QR'
                            : 'Disabled — mobile goes straight to QR scan',
                        style: TextStyle(
                          fontSize: 11,
                          color: _popupEnabled
                              ? AppColors.primaryBlue.withOpacity(0.75)
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _popupEnabled,
                  activeColor: AppColors.primaryBlue,
                  onChanged: (v) => setState(() {
                    _popupEnabled = v;
                    _hasUnsavedChanges = true;
                  }),
                ),
              ],
            ),

            // ── Editable fields (shown only when enabled) ─
            if (_popupEnabled) ...[
              const SizedBox(height: 14),

              // Subtitle
              TextField(
                controller: _ctrl('popupSubtitle', _popupSubtitle),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(
                  labelText: 'Subtitle',
                  hintText: 'e.g. Before you proceed…',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.pageBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primaryBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (v) {
                  _popupSubtitle = v;
                  _hasUnsavedChanges = true;
                },
              ),
              const SizedBox(height: 10),

              // Description (multiline)
              TextField(
                controller: _ctrl('popupDesc', _popupDescription),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText:
                      'Explain what this form is for, what data is '
                      'being collected, and how it will be used…',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.pageBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primaryBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  alignLabelWithHint: true,
                ),
                onChanged: (v) {
                  _popupDescription = v;
                  _hasUnsavedChanges = true;
                },
              ),
              const SizedBox(height: 10),

              // ── Live preview badge ─────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.phone_android,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Preview  ',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: _formName.trim().isEmpty
                                  ? 'Untitled Form'
                                  : _formName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                            if (_popupSubtitle.trim().isNotEmpty)
                              TextSpan(text: '  ·  ${_popupSubtitle.trim()}'),
                            if (_popupDescription.trim().isNotEmpty)
                              TextSpan(
                                text:
                                    '\n${_popupDescription.trim().length > 100 ? '${_popupDescription.trim().substring(0, 100)}…' : _popupDescription.trim()}',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ── END POPUP SECTION ─────────────────────────
          ],
        ),
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────
  // ignore: unused_element
  List<Widget> _buildAllSections() {
    final items = <Widget>[];
    for (var si = 0; si < _sections.length; si++) {
      final section = _sections[si];
      final isSectionActive = _activeSectionIdx == si;
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              _buildSectionHeader(section, si, isSectionActive),
              ...List.generate(section.fields.length, (fi) {
                final isFieldActive =
                    _activeSectionIdx == si && _activeFieldIdx == fi;
                return _buildFieldCard(
                  section.fields[fi],
                  si,
                  fi,
                  isFieldActive,
                );
              }),
            ],
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildSectionHeader(_BuilderSection section, int si, bool isActive) {
    return GestureDetector(
      onTap: () => _preserveScrollPosition(() {
        _activeSectionIdx = si;
        _activeFieldIdx = null;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.highlight : AppColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            if (isActive)
              Container(
                width: 3,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.highlight,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isActive ? 13 : 16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActive)
                      TextField(
                        controller: _ctrl('sec_${section.id}', section.name),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Section Title',
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.highlight,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          section.name = v;
                          _hasUnsavedChanges = true;
                        },
                      )
                    else
                      Text(
                        section.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                      ),
                    if (isActive)
                      TextField(
                        controller: _ctrl(
                          'sec_desc_${section.id}',
                          section.description ?? '',
                        ),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Section description (optional)',
                          hintStyle: TextStyle(fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onChanged: (v) {
                          section.description = v.isEmpty ? null : v;
                          _hasUnsavedChanges = true;
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (isActive) ...[
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: si > 0 ? () => _moveSection(si, -1) : null,
                tooltip: 'Move up',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: si < _sections.length - 1
                    ? () => _moveSection(si, 1)
                    : null,
                tooltip: 'Move down',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.red,
                ),
                onPressed: () => _removeSection(si),
                tooltip: 'Delete section',
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FIELD CARD
  // ═══════════════════════════════════════════════════════════
  Widget _buildFieldCard(_BuilderField field, int si, int fi, bool isActive) {
    return GestureDetector(
      onTap: () => _preserveScrollPosition(() {
        _activeSectionIdx = si;
        _activeFieldIdx = fi;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.highlight : AppColors.cardBorder,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isActive)
                Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(isActive ? 18 : 24, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isActive)
                        _buildFieldHeaderActive(field)
                      else
                        _buildFieldHeaderInactive(field),
                      const SizedBox(height: 12),
                      _buildFieldContent(field, isActive),
                      if (isActive) ...[
                        const SizedBox(height: 8),
                        const Divider(color: AppColors.cardBorder),
                        _buildFieldToolbar(field, si, fi),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldHeaderActive(_BuilderField field) {
    final isSignatureField = field.type == FormFieldType.signature;
    final canLinkCanonicalKey =
        _canonicalKeyEligibleTypes.contains(field.type) || isSignatureField;
    final selectedCanonicalKey = isSignatureField
        ? 'signature'
        : field.canonicalFieldKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _ctrl('fld_${field.id}', field.label),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 15, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Question',
                  filled: true,
                  fillColor: AppColors.pageBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.highlight),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onChanged: (v) {
                  field.label = v;
                  _hasUnsavedChanges = true;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child:
                    field.type.isSystemType ||
                        field.type == FormFieldType.computed
                    ? Row(
                        children: [
                          Icon(
                            _systemTypeIcons[field.type] ?? Icons.help_outline,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'System: ${_systemTypeLabels[field.type] ?? field.type.toDbString()}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<FormFieldType>(
                          value: field.type,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                          items: _typeLabels.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Row(
                                children: [
                                  Icon(
                                    _typeIcons[e.key],
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            if (v == FormFieldType.signature) {
                              final hasOtherSignature = _sections
                                  .expand((s) => s.fields)
                                  .any(
                                    (f) =>
                                        f.type == FormFieldType.signature &&
                                        f.id != field.id,
                                  );
                              if (hasOtherSignature) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'A "Signature" block already exists in this form.',
                                    ),
                                    backgroundColor: Colors.orange.shade700,
                                  ),
                                );
                                return;
                              }
                            }
                            _setStatePreserveCanvasScroll(() {
                              field.type = v;
                              if (v == FormFieldType.signature) {
                                field.canonicalFieldKey = 'signature';
                              }
                              if (v != FormFieldType.number) {
                                field.ageFromFieldId = null;
                              }
                              if (field.hasOptions && field.options.isEmpty) {
                                field.options.add(
                                  _BuilderOption(label: 'Option 1'),
                                );
                              }
                              _hasUnsavedChanges = true;
                            });
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (canLinkCanonicalKey) ...[
          const SizedBox(height: 10),
          const Text(
            'Autofill Key (cross-form)',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedCanonicalKey,
                isExpanded: true,
                hint: const Text(
                  'Link to known field (optional)',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                items: [
                  if (!isSignatureField)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— None —'),
                    ),
                  ...(isSignatureField
                          ? const [(key: 'signature', label: 'Signature')]
                          : _availableCanonicalKeys)
                      .map(
                        (entry) => DropdownMenuItem<String?>(
                          value: entry.key,
                          child: Text(
                            entry.key == entry.label
                                ? entry.key
                                : '${entry.label}  (${entry.key})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                ],
                onChanged: (value) {
                  setState(() {
                    field.canonicalFieldKey = isSignatureField
                        ? 'signature'
                        : value;
                    _hasUnsavedChanges = true;
                  });
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFieldHeaderInactive(_BuilderField field) {
    return Row(
      children: [
        Icon(
          (field.type.isSystemType
                  ? _systemTypeIcons[field.type]
                  : _typeIcons[field.type]) ??
              Icons.help_outline,
          size: 16,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (field.canonicalFieldKey != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.highlight.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    '⟷ ${field.canonicalFieldKey}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.highlight,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (field.isRequired)
          const Text(
            ' *',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }

  Widget _buildFieldToolbar(_BuilderField field, int si, int fi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVisibilityConditionRow(field),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 0,
          runSpacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.content_copy, size: 18),
              tooltip: 'Duplicate',
              onPressed: () => _duplicateField(si, fi),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              tooltip: 'Delete',
              onPressed: () => _removeField(si, fi),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.cardBorder),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: 'Move up',
              onPressed: fi > 0 ? () => _moveField(si, fi, -1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              tooltip: 'Move down',
              onPressed: fi < _sections[si].fields.length - 1
                  ? () => _moveField(si, fi, 1)
                  : null,
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.cardBorder),
            const SizedBox(width: 4),
            const Text(
              'Required',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            Switch(
              value: field.isRequired,
              activeColor: AppColors.highlight,
              onChanged: (v) => setState(() {
                field.isRequired = v;
                _hasUnsavedChanges = true;
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisibilityConditionRow(_BuilderField field) {
    final triggerCandidates = _sections
        .expand((s) => s.fields)
        .where(
          (f) =>
              f.id != field.id &&
              (f.type == FormFieldType.boolean ||
                  f.type == FormFieldType.radio ||
                  f.type == FormFieldType.dropdown ||
                  f.type == FormFieldType.checkbox ||
                  f.type == FormFieldType.membershipGroup),
        )
        .toList();

    final hasCondition = field.condition.triggerFieldId.isNotEmpty;

    _BuilderField? triggerField;
    for (final f in triggerCandidates) {
      if (f.id == field.condition.triggerFieldId) {
        triggerField = f;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasCondition
            ? Colors.orange.withOpacity(0.06)
            : AppColors.pageBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasCondition
              ? Colors.orange.withOpacity(0.4)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.device_hub_outlined,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              const Text(
                'Show only if…',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const Spacer(),
              Switch(
                value: hasCondition,
                activeColor: Colors.orange,
                onChanged: triggerCandidates.isEmpty
                    ? null
                    : (v) => setState(() {
                        if (!v) {
                          field.condition.triggerFieldId = '';
                          field.condition.triggerValue = '';
                        } else {
                          field.condition.triggerFieldId =
                              triggerCandidates.first.id;
                          field.condition.triggerValue = '';
                          field.condition.action = 'show';
                        }
                        _hasUnsavedChanges = true;
                      }),
              ),
            ],
          ),
          if (hasCondition) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: field.condition.triggerFieldId.isEmpty
                            ? null
                            : field.condition.triggerFieldId,
                        isExpanded: true,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                        ),
                        hint: const Text(
                          'Pick a field',
                          style: TextStyle(fontSize: 12),
                        ),
                        items: triggerCandidates.map((f) {
                          return DropdownMenuItem<String>(
                            value: f.id,
                            child: Text(
                              f.label.isNotEmpty ? f.label : f.fieldName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() {
                          field.condition.triggerFieldId = v ?? '';
                          field.condition.triggerValue = '';
                          field.condition.action = 'show';
                          _hasUnsavedChanges = true;
                        }),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '=',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child:
                      triggerField != null &&
                          (triggerField.hasOptions ||
                              triggerField.type == FormFieldType.boolean ||
                              triggerField.type ==
                                  FormFieldType.membershipGroup)
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: field.condition.triggerValue.isEmpty
                                  ? null
                                  : field.condition.triggerValue,
                              isExpanded: true,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDark,
                              ),
                              hint: const Text(
                                'Pick a value',
                                style: TextStyle(fontSize: 12),
                              ),
                              items: triggerField.type == FormFieldType.boolean
                                  ? const [
                                      DropdownMenuItem(
                                        value: 'yes',
                                        child: Text('Yes'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'no',
                                        child: Text('No'),
                                      ),
                                    ]
                                  : triggerField.type ==
                                        FormFieldType.membershipGroup
                                  ? const [
                                      DropdownMenuItem(
                                        value: 'solo_parent',
                                        child: Text('Solo Parent'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'pwd',
                                        child: Text('PWD'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'four_ps_member',
                                        child: Text('4Ps Member'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'phic_member',
                                        child: Text('PHIC Member'),
                                      ),
                                    ]
                                  : triggerField.options.map((o) {
                                      return DropdownMenuItem<String>(
                                        value: _slugify(o.label),
                                        child: Text(
                                          o.label,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      );
                                    }).toList(),
                              onChanged: (v) => setState(() {
                                field.condition.triggerValue = v ?? '';
                                field.condition.action = 'show';
                                _hasUnsavedChanges = true;
                              }),
                            ),
                          ),
                        )
                      : TextField(
                          controller: _ctrl(
                            'cond_val_${field.id}',
                            field.condition.triggerValue,
                          ),
                          scrollPadding: EdgeInsets.zero,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Type value...',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.orange,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (v) => setState(() {
                            field.condition.triggerValue = v;
                            field.condition.action = 'show';
                            _hasUnsavedChanges = true;
                          }),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              field.condition.triggerValue.isEmpty
                  ? 'Pick a value to complete the condition.'
                  : 'This field shows when "${triggerField?.label ?? "?"}" = "${field.condition.triggerValue}"',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
          if (!hasCondition && triggerCandidates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Add a Yes/No, radio, dropdown, checkbox, or Membership Group field first to use this.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FIELD TYPE CONTENT
  // ═══════════════════════════════════════════════════════════
  Widget _buildFieldContent(_BuilderField field, bool isActive) {
    switch (field.type) {
      case FormFieldType.text:
        return _textPreview('Short answer text');
      case FormFieldType.paragraph:
        return _textPreview('Long answer text');
      case FormFieldType.number:
        return _buildNumberEditor(field, isActive);
      case FormFieldType.radio:
      case FormFieldType.checkbox:
      case FormFieldType.dropdown:
        return _buildOptionsEditor(field, isActive);
      case FormFieldType.date:
        return _iconPreview('Month, Day, Year', Icons.calendar_today);
      case FormFieldType.time:
        return _iconPreview('Time', Icons.access_time);
      case FormFieldType.linearScale:
        return _buildLinearScaleEditor(field, isActive);
      case FormFieldType.memberTable:
        return _buildColumnEditor(field, isActive);
      case FormFieldType.familyTable:
        return _buildSystemTableColumnEditor(field, isActive);
      case FormFieldType.computed:
        return _buildFormulaEditor(field, isActive);
      case FormFieldType.conditional:
        return _buildConditionEditor(field, isActive);
      case FormFieldType.boolean:
        return Column(
          children: [
            _optionRow(Icons.radio_button_unchecked, 'Yes'),
            _optionRow(Icons.radio_button_unchecked, 'No'),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildNumberEditor(_BuilderField field, bool isActive) {
    if (!isActive) return _textPreview('Number');

    final dateCandidates = _sections
        .expand((s) => s.fields)
        .where((f) => f.id != field.id && f.type == FormFieldType.date)
        .toList();
    final hasLink =
        field.ageFromFieldId != null && field.ageFromFieldId!.isNotEmpty;
    final selectedValid =
        hasLink && dateCandidates.any((f) => f.id == field.ageFromFieldId);
    final selectedValue = selectedValid ? field.ageFromFieldId : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auto-compute from field',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Enable',
                style: TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
              const SizedBox(width: 8),
              Switch(
                value: hasLink,
                activeColor: AppColors.highlight,
                onChanged: (v) => setState(() {
                  if (!v) {
                    field.ageFromFieldId = null;
                  } else {
                    field.ageFromFieldId = dateCandidates.isNotEmpty
                        ? dateCandidates.first.id
                        : null;
                  }
                  _hasUnsavedChanges = true;
                }),
              ),
            ],
          ),
          if (hasLink) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedValue,
                  isExpanded: true,
                  hint: const Text(
                    'Select date field',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDark,
                  ),
                  items: dateCandidates
                      .map(
                        (f) => DropdownMenuItem<String>(
                          value: f.id,
                          child: Text(
                            f.label.isNotEmpty ? f.label : f.fieldName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: dateCandidates.isEmpty
                      ? null
                      : (v) => setState(() {
                          field.ageFromFieldId = v;
                          _hasUnsavedChanges = true;
                        }),
                ),
              ),
            ),
            if (dateCandidates.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Add at least one Date field to link this Age field.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnAutoComputeEditor(
    _BuilderField tableField,
    _BuilderColumn col,
  ) {
    final dateColumns = tableField.columns
        .where((c) => c.id != col.id && c.type == FormFieldType.date)
        .toList();
    final hasLink =
        col.ageFromColumnId != null && col.ageFromColumnId!.isNotEmpty;
    final selectedValid =
        hasLink && dateColumns.any((c) => c.id == col.ageFromColumnId);
    final selectedValue = selectedValid ? col.ageFromColumnId : null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.highlight.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.highlight.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 14,
                color: AppColors.highlight,
              ),
              const SizedBox(width: 6),
              const Text(
                'Auto-compute from column',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Switch(
                value: hasLink,
                activeColor: AppColors.highlight,
                onChanged: (v) => setState(() {
                  if (!v) {
                    col.ageFromColumnId = null;
                  } else {
                    col.ageFromColumnId = dateColumns.isNotEmpty
                        ? dateColumns.first.id
                        : null;
                  }
                  _hasUnsavedChanges = true;
                }),
              ),
            ],
          ),
          if (hasLink) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedValue,
                  isExpanded: true,
                  hint: const Text(
                    'Select date column',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDark,
                  ),
                  items: dateColumns
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(
                            c.label.isNotEmpty ? c.label : c.fieldName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: dateColumns.isEmpty
                      ? null
                      : (v) => setState(() {
                          col.ageFromColumnId = v;
                          _hasUnsavedChanges = true;
                        }),
                ),
              ),
            ),
            if (dateColumns.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Add a Date column to this table first.',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _textPreview(String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          hint,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _iconPreview(String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Text(
            hint,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const Spacer(),
          Icon(icon, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _optionRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildLinearScaleEditor(_BuilderField field, bool isActive) {
    if (!isActive) {
      return Row(
        children: [
          Text(
            '${field.scaleMin}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.cardBorder,
            ),
          ),
          Text(
            '${field.scaleMax}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Text(
          'From:',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMin,
          items: [
            0,
            1,
          ].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
          onChanged: (v) => setState(() {
            field.scaleMin = v!;
            _hasUnsavedChanges = true;
          }),
        ),
        const SizedBox(width: 24),
        const Text(
          'To:',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMax,
          items: List.generate(
            9,
            (i) => i + 2,
          ).map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
          onChanged: (v) => setState(() {
            field.scaleMax = v!;
            _hasUnsavedChanges = true;
          }),
        ),
      ],
    );
  }

  Widget _buildColumnEditor(_BuilderField field, bool isActive) {
    const columnTypes = <FormFieldType, String>{
      FormFieldType.text: 'Text',
      FormFieldType.number: 'Number',
      FormFieldType.date: 'Date',
      FormFieldType.dropdown: 'Dropdown',
    };

    if (!isActive) {
      if (field.columns.isEmpty) {
        return const Text(
          'No columns defined',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${field.columns.length} column(s) defined',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: field.columns.map((c) {
              return Chip(
                label: Text(
                  '${c.label} (${columnTypes[c.type] ?? c.type.toDbString()})',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Table Columns',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        ...field.columns.asMap().entries.map((entry) {
          final ci = entry.key;
          final col = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: ci > 0
                              ? () => _moveColumn(field, ci, -1)
                              : null,
                          tooltip: 'Move up',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: ci < field.columns.length - 1
                              ? () => _moveColumn(field, ci, 1)
                              : null,
                          tooltip: 'Move down',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ctrl('col_${col.id}', col.label),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Column name',
                          filled: true,
                          fillColor: AppColors.pageBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (v) {
                          col.label = v;
                          col.fieldName = _slugify(v);
                          _hasUnsavedChanges = true;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<FormFieldType>(
                            value: col.type,
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark,
                            ),
                            items: columnTypes.entries.map((e) {
                              return DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              _setStatePreserveCanvasScroll(() {
                                col.type = v;
                                if (v != FormFieldType.number) {
                                  col.ageFromColumnId = null;
                                }
                                if (v == FormFieldType.dropdown &&
                                    col.options.isEmpty) {
                                  col.options.add(
                                    _BuilderOption(label: 'Option 1'),
                                  );
                                }
                                _hasUnsavedChanges = true;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setState(() {
                        field.columns.removeAt(ci);
                        _hasUnsavedChanges = true;
                      }),
                    ),
                  ],
                ),
                if (col.type == FormFieldType.number) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: _buildColumnAutoComputeEditor(field, col),
                  ),
                ],
              ],
            ),
          );
        }),
        ...field.columns
            .where((c) => c.type == FormFieldType.dropdown)
            .map(
              (col) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Options for "${col.label}":',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    ...col.options.asMap().entries.map((oe) {
                      final opt = oe.value;
                      return Row(
                        children: [
                          const Icon(
                            Icons.arrow_right,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _ctrl('colopt_${opt.id}', opt.label),
                              scrollPadding: EdgeInsets.zero,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Option',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              onChanged: (v) {
                                opt.label = v;
                                _hasUnsavedChanges = true;
                              },
                            ),
                          ),
                          if (col.options.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () => setState(() {
                                col.options.removeAt(oe.key);
                                _hasUnsavedChanges = true;
                              }),
                            ),
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        col.options.add(
                          _BuilderOption(
                            label: 'Option ${col.options.length + 1}',
                          ),
                        );
                        _hasUnsavedChanges = true;
                      }),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Add option',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        TextButton.icon(
          onPressed: () => setState(() {
            field.columns.add(
              _BuilderColumn(
                label: 'Column ${field.columns.length + 1}',
                order: field.columns.length,
              ),
            );
            _hasUnsavedChanges = true;
          }),
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSystemTableColumnEditor(_BuilderField field, bool isActive) {
    const columnTypes = <FormFieldType, String>{
      FormFieldType.text: 'Text',
      FormFieldType.number: 'Number',
      FormFieldType.date: 'Date',
      FormFieldType.dropdown: 'Dropdown',
    };

    if (!isActive) {
      if (field.columns.isEmpty) {
        return const Text(
          'No columns defined',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${field.columns.length} column(s) defined',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: field.columns.map((c) {
              return Chip(
                label: Text(
                  '${c.label} (${columnTypes[c.type] ?? c.type.toDbString()})',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Table Columns',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Edit, rename, or remove any column. '
          'Pre-populated columns map to the database when present.',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        ...field.columns.asMap().entries.map((entry) {
          final ci = entry.key;
          final col = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: ci > 0
                              ? () => _moveColumn(field, ci, -1)
                              : null,
                          tooltip: 'Move up',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: ci < field.columns.length - 1
                              ? () => _moveColumn(field, ci, 1)
                              : null,
                          tooltip: 'Move down',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ctrl('col_${col.id}', col.label),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Column name',
                          filled: true,
                          fillColor: AppColors.pageBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (v) {
                          col.label = v;
                          if (col.dbMapKey == null) col.fieldName = _slugify(v);
                          _hasUnsavedChanges = true;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<FormFieldType>(
                            value: col.type,
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark,
                            ),
                            items: columnTypes.entries.map((e) {
                              return DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              _setStatePreserveCanvasScroll(() {
                                col.type = v;
                                if (v != FormFieldType.number) {
                                  col.ageFromColumnId = null;
                                }
                                if (v == FormFieldType.dropdown &&
                                    col.options.isEmpty) {
                                  col.options.add(
                                    _BuilderOption(label: 'Option 1'),
                                  );
                                }
                                _hasUnsavedChanges = true;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setState(() {
                        field.columns.removeAt(ci);
                        _hasUnsavedChanges = true;
                      }),
                    ),
                  ],
                ),
                if (col.type == FormFieldType.number) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: _buildColumnAutoComputeEditor(field, col),
                  ),
                ],
              ],
            ),
          );
        }),
        ...field.columns
            .where((c) => c.type == FormFieldType.dropdown)
            .map(
              (col) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Options for "${col.label}":',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    ...col.options.asMap().entries.map((oe) {
                      final opt = oe.value;
                      return Row(
                        children: [
                          const Icon(
                            Icons.arrow_right,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _ctrl('colopt_${opt.id}', opt.label),
                              scrollPadding: EdgeInsets.zero,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Option',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              onChanged: (v) {
                                opt.label = v;
                                _hasUnsavedChanges = true;
                              },
                            ),
                          ),
                          if (col.options.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () => setState(() {
                                col.options.removeAt(oe.key);
                                _hasUnsavedChanges = true;
                              }),
                            ),
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        col.options.add(
                          _BuilderOption(
                            label: 'Option ${col.options.length + 1}',
                          ),
                        );
                        _hasUnsavedChanges = true;
                      }),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Add option',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        TextButton.icon(
          onPressed: () => setState(() {
            field.columns.add(
              _BuilderColumn(
                label: 'Column ${field.columns.length + 1}',
                order: field.columns.length,
              ),
            );
            _hasUnsavedChanges = true;
          }),
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildOptionsEditor(_BuilderField field, bool isActive) {
    final isRadio = field.type == FormFieldType.radio;
    final isCheckbox = field.type == FormFieldType.checkbox;
    final optIcon = isRadio
        ? Icons.radio_button_unchecked
        : isCheckbox
        ? Icons.check_box_outline_blank
        : Icons.arrow_right;

    return Column(
      children: [
        ...List.generate(field.options.length, (oi) {
          final opt = field.options[oi];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(optIcon, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                if (isActive)
                  Expanded(
                    child: TextField(
                      controller: _ctrl('opt_${opt.id}', opt.label),
                      scrollPadding: EdgeInsets.zero,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Option',
                        border: InputBorder.none,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.highlight),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        opt.label = v;
                        _hasUnsavedChanges = true;
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      opt.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                if (isActive && field.options.length > 1)
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() {
                      field.options.removeAt(oi);
                      _hasUnsavedChanges = true;
                    }),
                  ),
              ],
            ),
          );
        }),
        if (isActive)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  optIcon,
                  size: 20,
                  color: AppColors.textMuted.withOpacity(0.4),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => setState(() {
                    field.options.add(
                      _BuilderOption(
                        label: 'Option ${field.options.length + 1}',
                        order: field.options.length,
                      ),
                    );
                    _hasUnsavedChanges = true;
                  }),
                  child: const Text('Add option'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<String> _formulaTokens(_BuilderField field) =>
      field.formula.trim().isEmpty
      ? []
      : field.formula.trim().split(RegExp(r'\s+'));

  void _appendFormulaToken(_BuilderField field, String token) {
    final tokens = _formulaTokens(field);
    tokens.add(token);
    setState(() {
      field.formula = tokens.join(' ');
      _hasUnsavedChanges = true;
    });
  }

  void _removeFormulaToken(_BuilderField field, int index) {
    final tokens = _formulaTokens(field);
    tokens.removeAt(index);
    setState(() {
      field.formula = tokens.join(' ');
      _hasUnsavedChanges = true;
    });
  }

  void _showSumColumnPicker(_BuilderField field) {
    // Find all member-table fields in the form
    final tableFields = _sections
        .expand((s) => s.fields)
        .where((f) => f.type == FormFieldType.memberTable)
        .toList();

    if (tableFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No table fields found in the form.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Step 1: Show table picker modal
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Table Field',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose the table you want to sum.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              ...tableFields.map((tableField) {
                final tableKey = tableField.fieldName;
                final tableLabel = tableField.label.isNotEmpty
                    ? tableField.label
                    : tableField.fieldName;

                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.table_chart,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  title: Text(tableLabel),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showColumnPicker(field, tableKey, tableField.columns);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showColumnPicker(
    _BuilderField field,
    String tableKey,
    List<_BuilderColumn> columns,
  ) {
    final List<_BuilderColumn> cols = columns;

    if (cols.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No columns found for this table.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Column',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose which column to sum.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final col in cols)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.pin,
                            size: 18,
                            color: AppColors.primaryBlue,
                          ),
                          title: Text(
                            '${col.label} (${(col.dbMapKey?.isNotEmpty == true ? col.dbMapKey : col.fieldName)})',
                          ),
                          subtitle: Text(
                            col.dbMapKey?.isNotEmpty == true
                                ? col.dbMapKey!
                                : col.fieldName,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            final columnKey = col.dbMapKey?.isNotEmpty == true
                                ? col.dbMapKey!
                                : col.fieldName;
                            final formula =
                                'SUM_COLUMN($tableKey, "$columnKey")';
                            _appendFormulaToken(field, formula);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormulaEditor(_BuilderField field, bool isActive) {
    final tokens = _formulaTokens(field);
    final numericFields = _sections
        .expand((s) => s.fields)
        .where(
          (f) =>
              f.id != field.id &&
              (f.type == FormFieldType.number ||
                  f.type == FormFieldType.computed),
        )
        .toList();

    final fieldLabelMap = {
      for (final f
          in _sections.expand((s) => s.fields).where((f) => f.id != field.id))
        f.fieldName: (f.label.isNotEmpty ? f.label : f.fieldName),
    };

    if (!isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.buttonOutlineBlue.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calculate_outlined,
              size: 14,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tokens.isEmpty
                    ? 'No formula set'
                    : tokens.map((t) => fieldLabelMap[t] ?? t).join(' '),
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.isEmpty
                      ? AppColors.textMuted
                      : AppColors.primaryBlue,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Formula',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap field names and operators below to build the formula. Tap × on a token to remove it.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.buttonOutlineBlue.withOpacity(0.4),
            ),
          ),
          child: tokens.isEmpty
              ? const Text(
                  'Empty — add fields and operators below',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tokens.asMap().entries.map((e) {
                    final i = e.key;
                    final tok = e.value;
                    final isOp = const {
                      '+',
                      '-',
                      '*',
                      '/',
                      '(',
                      ')',
                    }.contains(tok);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOp ? const Color(0xFFE8EEFF) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isOp
                              ? AppColors.primaryBlue.withOpacity(0.3)
                              : AppColors.buttonOutlineBlue,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isOp ? tok : (fieldLabelMap[tok] ?? tok),
                            style: TextStyle(
                              fontSize: isOp ? 14 : 12,
                              fontFamily: 'monospace',
                              fontWeight: isOp
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeFormulaToken(field, i),
                            child: const Icon(
                              Icons.close,
                              size: 13,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (numericFields.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Available fields:',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: numericFields.map((f) {
              return ElevatedButton.icon(
                onPressed: () => _appendFormulaToken(field, f.fieldName),
                icon: const Icon(Icons.add, size: 14),
                label: Text(
                  f.label.isNotEmpty ? f.label : f.fieldName,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(
                      color: AppColors.buttonOutlineBlue,
                      width: 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Aggregate Functions:',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: () => _showSumColumnPicker(field),
          icon: const Icon(Icons.functions, size: 14),
          label: const Text(
            'SUM_COLUMN',
            style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEEF5FF),
            foregroundColor: AppColors.primaryBlue,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: AppColors.primaryBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sums any column across all rows of a table field.',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Operators:',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['+', '-', '*', '/', '(', ')'].map((op) {
            return ElevatedButton(
              onPressed: () => _appendFormulaToken(field, op),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8EEFF),
                foregroundColor: AppColors.primaryBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size(36, 32),
              ),
              child: Text(
                op,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConditionEditor(_BuilderField field, bool isActive) {
    final allFields = _sections
        .expand((s) => s.fields)
        .where((f) => f.id != field.id)
        .toList();

    _BuilderField? triggerField;
    for (final f in allFields) {
      if (f.id == field.condition.triggerFieldId) {
        triggerField = f;
        break;
      }
    }

    if (!isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.device_hub_outlined,
              size: 14,
              color: Colors.orange,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                field.condition.triggerFieldId.isEmpty
                    ? 'No condition set'
                    : 'Show if "${triggerField?.label ?? field.condition.triggerFieldId}" = "${field.condition.triggerValue}"',
                style: TextStyle(
                  fontSize: 12,
                  color: field.condition.triggerFieldId.isEmpty
                      ? AppColors.textMuted
                      : Colors.orange.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Condition',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'This field will only be visible when the selected field equals the specified value.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: field.condition.triggerFieldId.isEmpty
                  ? null
                  : field.condition.triggerFieldId,
              isExpanded: true,
              hint: const Text(
                'Select trigger field',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              items: allFields
                  .map(
                    (f) => DropdownMenuItem<String>(
                      value: f.id,
                      child: Text(
                        f.label.isNotEmpty ? f.label : f.fieldName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  field.condition.triggerFieldId = value;
                  field.condition.action = 'show';
                  _hasUnsavedChanges = true;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl(
            'cond_val_${field.id}',
            field.condition.triggerValue,
          ),
          scrollPadding: EdgeInsets.zero,
          decoration: InputDecoration(
            hintText: 'Trigger value (exact match)',
            filled: true,
            fillColor: AppColors.pageBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.highlight),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (v) {
            field.condition.triggerValue = v;
            field.condition.action = 'show';
            _hasUnsavedChanges = true;
          },
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildAddSectionButton() {
    return OutlinedButton.icon(
      onPressed: _addSection,
      icon: const Icon(Icons.playlist_add, size: 20),
      label: const Text('Add Section'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.highlight,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: BorderSide(color: AppColors.highlight.withOpacity(0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatusCard() {
    final (
      Color clr,
      String label,
      String desc,
      IconData icon,
    ) = switch (_formStatus) {
      'published' => (
        Colors.blue,
        'PUBLISHED',
        'Visible to admin staff in Manage Forms',
        Icons.visibility,
      ),
      'pushed_to_mobile' => (
        Colors.green,
        'LIVE ON MOBILE',
        'Users can fill this form on the mobile app',
        Icons.phone_android,
      ),
      'archived' => (
        Colors.grey,
        'ARCHIVED',
        'Hidden from admins & mobile. Data preserved.',
        Icons.archive_outlined,
      ),
      _ => (
        Colors.orange,
        'DRAFT',
        'Only you can see this template',
        Icons.edit_note,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: clr.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: clr.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: clr, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: $label',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: clr,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(color: clr.withOpacity(0.8), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_formStatus != 'archived') ...[
            if (_formStatus != 'draft')
              TextButton(
                onPressed: _unpublishTemplate,
                child: const Text('Revert to Draft'),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _archiveTemplate,
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Archive'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
            ),
          ],
          if (_formStatus == 'archived') ...[
            ElevatedButton.icon(
              onPressed: _restoreTemplate,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore to Draft'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
