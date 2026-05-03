import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/form_builder_service.dart';

String _generateUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes.sublist(start, end).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

String _slugify(String label) => label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

const typeLabels = <FormFieldType, String>{
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

const typeIcons = <FormFieldType, IconData>{
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

const systemTypeLabels = <FormFieldType, String>{
  FormFieldType.computed: 'Computed',
  FormFieldType.conditional: 'Conditional',
  FormFieldType.membershipGroup: 'Membership Group',
  FormFieldType.familyTable: 'Family Table',
  FormFieldType.supportingFamilyTable: 'Supporting Family Table',
  FormFieldType.signature: 'Signature',
  FormFieldType.unknown: 'Unknown',
};

const systemTypeIcons = <FormFieldType, IconData>{
  FormFieldType.computed: Icons.calculate_outlined,
  FormFieldType.conditional: Icons.device_hub_outlined,
  FormFieldType.membershipGroup: Icons.group_outlined,
  FormFieldType.familyTable: Icons.table_chart_outlined,
  FormFieldType.supportingFamilyTable: Icons.table_chart_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.unknown: Icons.help_outline,
};

const standardProfileCanonicalKeys = <({String key, String label})>[
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
  (key: 'house_number_street_name_phase_purok', label: 'House No. / Street / Purok'),
  (key: 'barangay', label: 'Barangay'),
  (key: 'subdivison_', label: 'Subdivision'),
  (key: 'signature', label: 'Signature'),
];

const canonicalKeyEligibleTypes = <FormFieldType>{
  FormFieldType.text,
  FormFieldType.number,
  FormFieldType.date,
  FormFieldType.dropdown,
  FormFieldType.radio,
  FormFieldType.boolean,
};

class ReferenceToken {
  final String label;
  final String token;
  final String hint;
  final String group;

  const ReferenceToken(this.label, this.token, this.hint, this.group);
}

const referenceTokens = <ReferenceToken>[
  ReferenceToken('Form Code', '{FORMCODE}', 'GIS', 'Form Info'),
  ReferenceToken('Year (2026)', '{YYYY}', '2026', 'Date'),
  ReferenceToken('Year Short (26)', '{YY}', '26', 'Date'),
  ReferenceToken('Month Number (03)', '{MM}', '03', 'Date'),
  ReferenceToken('Month Short (MAR)', '{MON}', 'MAR', 'Date'),
  ReferenceToken('Day (26)', '{DD}', '26', 'Date'),
  ReferenceToken('Day of Year (085)', '{DDD}', '085', 'Date'),
  ReferenceToken('Quarter (1)', '{Q}', '1', 'Date'),
  ReferenceToken('Week Number (13)', '{WW}', '13', 'Date'),
  ReferenceToken('ISO Week (13)', '{IW}', '13', 'Date'),
  ReferenceToken('Hour (14)', '{HH24}', '14', 'Time'),
  ReferenceToken('Minute (30)', '{MI}', '30', 'Time'),
  ReferenceToken('Second (00)', '{SS}', '00', 'Time'),
  ReferenceToken('Counter 8-digit (00000001)', '{########}', '00000001', 'Counter'),
  ReferenceToken('Counter 6-digit (000001)', '{######}', '000001', 'Counter'),
  ReferenceToken('Counter 4-digit (0001)', '{####}', '0001', 'Counter'),
  ReferenceToken('Counter 3-digit (001)', '{###}', '001', 'Counter'),
  ReferenceToken('Counter 2-digit (01)', '{##}', '01', 'Counter'),
  ReferenceToken('Counter (1)', '{#}', '1', 'Counter'),
];

const referenceTokenGroups = <String>['Form Info', 'Date', 'Time', 'Counter'];

class BuilderOption {
  String id;
  String label;
  int order;

  BuilderOption({String? id, this.label = 'Option', this.order = 0}) : id = id ?? _generateUuid();
}

class BuilderColumn {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  int order;
  List<BuilderOption> options;
  String? dbMapKey;
  String? ageFromColumnId;

  BuilderColumn({
    String? id,
    this.label = 'Column',
    String? fieldName,
    this.type = FormFieldType.text,
    this.order = 0,
    List<BuilderOption>? options,
    this.dbMapKey,
    this.ageFromColumnId,
  }) : id = id ?? _generateUuid(),
       fieldName = fieldName ?? 'col_${_generateUuid().substring(0, 8)}',
       options = options ?? [];

  bool get isCoreColumn => dbMapKey != null;
}

class BuilderCondition {
  String triggerFieldId;
  String triggerValue;
  String action;

  BuilderCondition({this.triggerFieldId = '', this.triggerValue = '', this.action = 'show'});
}

class BuilderField {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  bool isRequired;
  String? placeholder;
  String? canonicalFieldKey;
  int order;
  List<BuilderOption> options;
  List<BuilderColumn> columns;
  int scaleMin;
  int scaleMax;
  String formula;
  String? ageFromFieldId;
  BuilderCondition condition;

  BuilderField({
    String? id,
    this.label = 'Untitled Question',
    String? fieldName,
    this.type = FormFieldType.radio,
    this.isRequired = false,
    this.placeholder,
    this.canonicalFieldKey,
    this.order = 0,
    List<BuilderOption>? options,
    List<BuilderColumn>? columns,
    this.scaleMin = 1,
    this.scaleMax = 5,
    this.formula = '',
    this.ageFromFieldId,
    BuilderCondition? condition,
  }) : id = id ?? _generateUuid(),
       fieldName = fieldName ?? 'field_${_generateUuid().substring(0, 8)}',
       options = options ?? [BuilderOption(label: 'Option 1', order: 0)],
       columns = columns ?? [],
       condition = condition ?? BuilderCondition();

  bool get hasOptions => type == FormFieldType.radio || type == FormFieldType.checkbox || type == FormFieldType.dropdown;
}

class BuilderSection {
  String id;
  String name;
  String? description;
  int order;
  List<BuilderField> fields;

  BuilderSection({String? id, this.name = 'Untitled Section', this.description, this.order = 0, List<BuilderField>? fields})
      : id = id ?? _generateUuid(),
        fields = fields ?? [];
}

enum TemplateListFilter { all, active, draft, published, archived }

class FormBuilderController extends ChangeNotifier {
  FormBuilderController({
    required String cswdId,
    required String role,
    required String displayName,
    String? editTemplateId,
  })  : _cswdId = cswdId,
        _role = role,
        _displayName = displayName,
        _editTemplateId = editTemplateId;

  final String _cswdId;
  final String _role;
  final String _displayName;
  final String? _editTemplateId;
  final _service = FormBuilderService();
  final Map<String, TextEditingController> _ctrls = {};
  BuildContext? _context;

  List<Map<String, dynamic>> _templates = [];
  bool _isLoadingList = true;
  TemplateListFilter _templateListFilter = TemplateListFilter.all;
  String? _activeTemplateId;
  String _formName = '';
  String _formDesc = '';
  String _formCode = '';
  String _referencePrefix = '';
  String _referenceFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
  bool _requiresReference = true;
  String _formStatus = 'draft';
  List<BuilderSection> _sections = [];
  bool _popupEnabled = false;
  String _popupSubtitle = '';
  String _popupDescription = '';
  int? _activeSectionIdx;
  int? _activeFieldIdx;
  bool _isSaving = false;
  bool _isLoadingTemplate = false;
  bool _hasUnsavedChanges = false;
  List<({String key, String label})> _availableCanonicalKeys = const [];
  bool _isLoadingCanonicalKeys = false;

  void attachContext(BuildContext context) {
    _context = context;
  }

  Future<void> init() async {
    await _loadCanonicalKeys();
    await _loadTemplateList();
    final editTemplateId = _editTemplateId;
    if (editTemplateId != null) {
      await _loadTemplate(editTemplateId);
    }
  }

  List<Map<String, dynamic>> get templates => _templates;
  bool get isLoadingList => _isLoadingList;
  TemplateListFilter get templateListFilter => _templateListFilter;
  String? get activeTemplateId => _activeTemplateId;
  String get formName => _formName;
  String get formDesc => _formDesc;
  String get formCode => _formCode;
  String get referencePrefix => _referencePrefix;
  String get referenceFormat => _referenceFormat;
  bool get requiresReference => _requiresReference;
  String get formStatus => _formStatus;
  List<BuilderSection> get sections => _sections;
  bool get popupEnabled => _popupEnabled;
  String get popupSubtitle => _popupSubtitle;
  String get popupDescription => _popupDescription;
  int? get activeSectionIdx => _activeSectionIdx;
  int? get activeFieldIdx => _activeFieldIdx;
  bool get isSaving => _isSaving;
  bool get isLoadingTemplate => _isLoadingTemplate;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  List<({String key, String label})> get availableCanonicalKeys => _availableCanonicalKeys;
  bool get isLoadingCanonicalKeys => _isLoadingCanonicalKeys;

  void setTemplateListFilter(TemplateListFilter value) {
    _templateListFilter = value;
    notifyListeners();
  }

  void setActiveSectionAndField(int? sectionIdx, int? fieldIdx) {
    _activeSectionIdx = sectionIdx;
    _activeFieldIdx = fieldIdx;
    notifyListeners();
  }

  void setFormName(String value) {
    _formName = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setFormDesc(String value) {
    _formDesc = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setFormCode(String value) {
    _formCode = _sanitizeCode(value);
    if (_referencePrefix.trim().isEmpty) {
      _referencePrefix = _formCode;
      _ctrl('referencePrefix', _referencePrefix).text = _referencePrefix;
    }
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setReferencePrefix(String value) {
    _referencePrefix = _sanitizeCode(value);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setRequiresReference(bool value) {
    _requiresReference = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setPopupEnabled(bool value) {
    _popupEnabled = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setPopupSubtitle(String value) {
    _popupSubtitle = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setPopupDescription(String value) {
    _popupDescription = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void markDirty() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  TextEditingController _ctrl(String key, String initial) {
    return _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  TextEditingController ctrlLookup(String key, String initial) => _ctrl(key, initial);

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

  List<String> referenceFormatParts() {
    if (_referenceFormat.isEmpty) return const [];
    return RegExp(r'(\{[^{}]+\}|.)').allMatches(_referenceFormat).map((m) => m.group(0)!).toList();
  }

  void appendReferenceToken(String token) {
    _referenceFormat = '$_referenceFormat$token';
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void appendReferenceSeparator(String separator) {
    _referenceFormat = '$_referenceFormat$separator';
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void removeReferencePartAt(int index) {
    final parts = referenceFormatParts();
    if (index < 0 || index >= parts.length) return;
    parts.removeAt(index);
    _referenceFormat = parts.join();
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  String referencePreview() {
    final now = DateTime.now();
    var ref = _referenceFormat;
    final prefix = _referencePrefix.trim().isNotEmpty
        ? _referencePrefix.trim().toUpperCase()
        : (_formCode.trim().isNotEmpty ? _formCode.trim().toUpperCase() : 'FORM');
    String pad(int v, int n) => v.toString().padLeft(n, '0');
    final yearStart = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(yearStart).inDays + 1;
    final quarter = ((now.month - 1) ~/ 3) + 1;

    ref = ref.replaceAll('{FORMCODE}', prefix);
    ref = ref.replaceAll('{YYYY}', now.year.toString());
    ref = ref.replaceAll('{YY}', now.year.toString().substring(2));
    ref = ref.replaceAll('{MM}', pad(now.month, 2));
    ref = ref.replaceAll('{MON}', const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][now.month - 1]);
    ref = ref.replaceAll('{MONTH}', const ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'][now.month - 1]);
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

  List<String> formulaTokens(BuilderField field) => field.formula.trim().isEmpty ? [] : field.formula.trim().split(RegExp(r'\s+'));

  void appendFormulaToken(BuilderField field, String token) {
    final tokens = formulaTokens(field);
    tokens.add(token);
    field.formula = tokens.join(' ');
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void removeFormulaToken(BuilderField field, int index) {
    final tokens = formulaTokens(field);
    tokens.removeAt(index);
    field.formula = tokens.join(' ');
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  Future<void> _loadTemplateList() async {
    _isLoadingList = true;
    notifyListeners();
    _templates = await _service.fetchAllTemplates();
    _isLoadingList = false;
    notifyListeners();
  }

  Future<void> _loadCanonicalKeys() async {
    _isLoadingCanonicalKeys = true;
    notifyListeners();
    try {
      final dbKeys = (await _service.fetchCanonicalFieldKeys()).toSet();
      for (final s in standardProfileCanonicalKeys) {
        dbKeys.add(s.key);
      }
      final labelMap = {for (final s in standardProfileCanonicalKeys) s.key: s.label};
      final merged = dbKeys.map((k) => (key: k, label: labelMap[k] ?? k)).toList()..sort((a, b) => a.key.compareTo(b.key));
      _availableCanonicalKeys = merged;
    } catch (e) {
      debugPrint('_loadCanonicalKeys error: $e');
      _availableCanonicalKeys = List.of(standardProfileCanonicalKeys);
    }
    _isLoadingCanonicalKeys = false;
    notifyListeners();
  }

  Future<void> _loadTemplate(String templateId) async {
    _isLoadingTemplate = true;
    _clearCtrls();
    notifyListeners();

    final data = await _service.fetchTemplateWithStructure(templateId);
    if (data == null) {
      _isLoadingTemplate = false;
      notifyListeners();
      return;
    }

    final rawSections = (data['form_sections'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()..sort((a, b) => ((a['section_order'] as int?) ?? 0).compareTo((b['section_order'] as int?) ?? 0));
    final rawFields = (data['form_fields'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>().where((f) {
      final vr = f['validation_rules'] as Map<String, dynamic>?;
      return vr == null || vr['_archived'] != true;
    }).toList();

    final childFields = rawFields.where((f) => f['parent_field_id'] != null).toList();
    final topLevelFields = rawFields.where((f) => f['parent_field_id'] == null).toList();
    final childrenByParent = <String, List<Map<String, dynamic>>>{};
    for (final cf in childFields) {
      final pid = cf['parent_field_id'] as String;
      childrenByParent.putIfAbsent(pid, () => []).add(cf);
    }

    final sections = rawSections.map((s) {
      final sFields = topLevelFields.where((f) => f['section_id'] == s['section_id']).toList()..sort((a, b) => ((a['field_order'] as int?) ?? 0).compareTo((b['field_order'] as int?) ?? 0));
      return BuilderSection(
        id: s['section_id'] as String,
        name: s['section_name'] as String? ?? 'Untitled Section',
        description: s['section_desc'] as String?,
        order: (s['section_order'] as int?) ?? 0,
        fields: sFields.map((f) {
          final rawOpts = (f['form_field_options'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()..sort((a, b) => ((a['option_order'] as int?) ?? 0).compareTo((b['option_order'] as int?) ?? 0));
          List<BuilderColumn> columns = [];
          final fid = f['field_id'] as String;
          final ftype = f['field_type'] as String? ?? '';
          if ((ftype == 'member_table' || ftype == 'family_table') && childrenByParent.containsKey(fid)) {
            final childList = childrenByParent[fid]!..sort((a, b) => ((a['field_order'] as int?) ?? 0).compareTo((b['field_order'] as int?) ?? 0));
            columns = childList.map((cf) {
              final colOpts = (cf['form_field_options'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()..sort((a, b) => ((a['option_order'] as int?) ?? 0).compareTo((b['option_order'] as int?) ?? 0));
              final vr = cf['validation_rules'] as Map<String, dynamic>?;
              final ageFromCol = (vr?['age_from_column'] as String?)?.trim();
              return BuilderColumn(
                id: cf['field_id'] as String,
                label: cf['field_label'] as String? ?? '',
                fieldName: cf['field_name'] as String? ?? '',
                type: FormFieldType.fromString(cf['field_type'] as String? ?? 'text'),
                order: (cf['field_order'] as int?) ?? 0,
                dbMapKey: vr?['db_map_key'] as String?,
                ageFromColumnId: (ageFromCol != null && ageFromCol.isNotEmpty) ? ageFromCol : null,
                options: colOpts.map((o) => BuilderOption(id: o['option_id'] as String, label: o['option_label'] as String? ?? '', order: (o['option_order'] as int?) ?? 0)).toList(),
              );
            }).toList();
          }

          final vr = f['validation_rules'] as Map<String, dynamic>?;
          final ageFromField = (vr?['age_from_field'] as String?)?.trim();
          final rawConditions = (f['form_field_conditions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          Map<String, dynamic>? showCondition;
          for (final c in rawConditions) {
            if ((c['action'] as String? ?? 'show') == 'show') {
              showCondition = c;
              break;
            }
          }
          showCondition ??= rawConditions.isNotEmpty ? rawConditions.first : null;

          return BuilderField(
            id: f['field_id'] as String,
            label: f['field_label'] as String? ?? '',
            fieldName: f['field_name'] as String? ?? '',
            type: FormFieldType.fromString(f['field_type'] as String? ?? 'text'),
            isRequired: (f['is_required'] as bool?) ?? false,
            placeholder: f['placeholder'] as String?,
            canonicalFieldKey: f['field_type'] == 'signature' ? 'signature' : f['canonical_field_key'] as String?,
            order: (f['field_order'] as int?) ?? 0,
            columns: columns,
            formula: (vr?['formula'] as String?) ?? '',
            ageFromFieldId: (ageFromField != null && ageFromField.isNotEmpty) ? ageFromField : null,
            condition: BuilderCondition(
              triggerFieldId: (showCondition?['trigger_field_id'] as String?) ?? '',
              triggerValue: (showCondition?['trigger_value'] as String?) ?? '',
              action: (showCondition?['action'] as String?) ?? 'show',
            ),
            options: rawOpts.map((o) => BuilderOption(id: o['option_id'] as String, label: o['option_label'] as String? ?? '', order: (o['option_order'] as int?) ?? 0)).toList(),
          );
        }).toList(),
      );
    }).toList();

    _activeTemplateId = templateId;
    _formName = data['form_name'] as String? ?? 'Untitled Form';
    _formDesc = data['form_desc'] as String? ?? '';
    _formCode = _sanitizeCode(data['form_code'] as String? ?? _slugify(_formName).toUpperCase());
    _referencePrefix = _sanitizeCode(data['reference_prefix'] as String? ?? _formCode);
    _referenceFormat = (data['reference_format'] as String?)?.trim().isNotEmpty == true ? data['reference_format'] as String : '{FORMCODE}-{YYYY}-{MM}-{####}';
    _requiresReference = (data['requires_reference'] as bool?) ?? true;
    _formStatus = data['status'] as String? ?? 'draft';
    _sections = sections;
    _popupEnabled = (data['popup_enabled'] as bool?) ?? false;
    _popupSubtitle = data['popup_subtitle'] as String? ?? '';
    _popupDescription = data['popup_description'] as String? ?? '';
    _activeSectionIdx = null;
    _activeFieldIdx = null;
    _hasUnsavedChanges = false;
    _isLoadingTemplate = false;
    notifyListeners();
  }

  Future<void> loadTemplate(String templateId) => _loadTemplate(templateId);

  Future<void> createNewTemplate() async {
    const defaultFormat = '{FORMCODE}-{YYYY}-{MM}-{####}';
    final id = await _service.createTemplate(
      formName: 'Untitled Form',
      formDesc: '',
      createdBy: _cswdId,
      formCode: 'UNTITLEDFORM',
      referencePrefix: 'UNTITLEDFORM',
      referenceFormat: defaultFormat,
      requiresReference: true,
    );
    if (id == null) return;
    await _loadTemplateList();
    _clearCtrls();
    _activeTemplateId = id;
    _formName = 'Untitled Form';
    _formDesc = '';
    _formCode = 'UNTITLEDFORM';
    _referencePrefix = 'UNTITLEDFORM';
    _referenceFormat = defaultFormat;
    _requiresReference = true;
    _formStatus = 'draft';
    _popupEnabled = false;
    _popupSubtitle = '';
    _popupDescription = '';
    _sections = [BuilderSection(name: 'Section 1', order: 0, fields: [BuilderField(label: 'Question 1', order: 0)])];
    _activeSectionIdx = 0;
    _activeFieldIdx = 0;
    _hasUnsavedChanges = true;
    _isLoadingTemplate = false;
    notifyListeners();
  }

  Future<void> saveTemplate() async {
    if (_activeTemplateId == null) return;
    _isSaving = true;
    notifyListeners();

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
        if (field.type == FormFieldType.number && field.ageFromFieldId != null && field.ageFromFieldId!.isNotEmpty) {
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

        if (field.type == FormFieldType.memberTable || field.type == FormFieldType.familyTable) {
          for (var ci = 0; ci < field.columns.length; ci++) {
            final col = field.columns[ci];
            final colValidationRules = <String, dynamic>{};
            if (col.dbMapKey != null) {
              colValidationRules['db_map_key'] = col.dbMapKey;
            }
            if (col.type == FormFieldType.number && col.ageFromColumnId != null && col.ageFromColumnId!.isNotEmpty) {
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
              if (colValidationRules.isNotEmpty) 'validation_rules': colValidationRules,
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

        if (field.condition.triggerFieldId.isNotEmpty && field.condition.triggerValue.isNotEmpty) {
          dbConditions.add({
            'field_id': field.id,
            'trigger_field_id': field.condition.triggerFieldId,
            'trigger_value': field.condition.triggerValue,
            'action': field.condition.action,
          });
        }
      }
    }

    final normalizedCode = _sanitizeCode(_formCode.trim().isNotEmpty ? _formCode : _slugify(_formName).toUpperCase());
    final normalizedPrefix = _sanitizeCode(_referencePrefix.trim().isNotEmpty ? _referencePrefix : normalizedCode);

    final success = await _service.saveTemplateStructure(
      templateId: _activeTemplateId!,
      formName: _formName,
      formDesc: _formDesc,
      formCode: normalizedCode,
      referencePrefix: normalizedPrefix,
      referenceFormat: _referenceFormat.trim().isNotEmpty ? _referenceFormat.trim() : '{FORMCODE}-{YYYY}-{MM}-{####}',
      requiresReference: _requiresReference,
      sections: dbSections,
      fields: dbFields,
      options: dbOptions,
      conditions: dbConditions,
    );

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

    _isSaving = false;
    if (success) _hasUnsavedChanges = false;
    notifyListeners();

    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(success ? 'Template saved' : 'Error saving template: ${_service.lastSaveError ?? "unknown"}'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    await _loadTemplateList();
  }

  Future<bool?> _showConfirmDialog({required String title, required String message, required String confirmLabel, required Color confirmColor}) {
    final context = _context;
    if (context == null) return Future.value(false);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> publishTemplate() async {
    if (_activeTemplateId == null) return;
    final hasFields = _sections.any((s) => s.fields.isNotEmpty);
    if (!hasFields) {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('Add at least one section with a question before publishing.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (_hasUnsavedChanges) await saveTemplate();
    final confirmed = await _showConfirmDialog(
      title: 'Publish Form',
      message: 'This will make the form visible to all admin users in their "Manage Forms" view. Continue?',
      confirmLabel: 'Publish',
      confirmColor: AppColors.highlight,
    );
    if (confirmed != true) return;

    final success = await _service.publishTemplate(_activeTemplateId!);
    if (success) {
      _formStatus = 'published';
      notifyListeners();
      await _loadTemplateList();
      await AuditLogService().log(
        actionType: kAuditTemplatePublished,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: _cswdId,
        actorName: _displayName,
        actorRole: _role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(success ? 'Form published ✓' : 'Error publishing'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> pushToMobile() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Push to Mobile',
      message: 'This will make the form available on the mobile app. Users will see it in their forms list. Continue?',
      confirmLabel: 'Push to Mobile',
      confirmColor: Colors.green,
    );
    if (confirmed != true) return;

    final success = await _service.pushToMobile(_activeTemplateId!);
    if (success) {
      _formStatus = 'pushed_to_mobile';
      notifyListeners();
      await _loadTemplateList();
      await AuditLogService().log(
        actionType: kAuditTemplatePushed,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: _cswdId,
        actorName: _displayName,
        actorRole: _role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(success ? 'Pushed to mobile ✓' : 'Error pushing'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> archiveTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Archive Form',
      message: 'This will remove the form from admins\' and mobile users\' view but keep all data intact for historical reference. Continue?',
      confirmLabel: 'Archive',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;

    final success = await _service.archiveTemplate(_activeTemplateId!);
    if (success) {
      _formStatus = 'archived';
      notifyListeners();
      await _loadTemplateList();
      await AuditLogService().log(
        actionType: kAuditTemplateArchived,
        category: kCategoryTemplate,
        severity: kSeverityWarning,
        actorId: _cswdId,
        actorName: _displayName,
        actorRole: _role,
        targetType: 'form_template',
        targetId: _activeTemplateId,
        targetLabel: _formName,
      );
    }
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(success ? 'Form archived ✓' : 'Error archiving: ${_service.lastActionError ?? "unknown error"}'),
          backgroundColor: success ? Colors.orange : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> restoreTemplate() async {
    if (_activeTemplateId == null) return;
    final success = await _service.restoreTemplate(_activeTemplateId!);
    if (success) {
      _formStatus = 'draft';
      notifyListeners();
      await _loadTemplateList();
    }
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(success ? 'Form restored to draft ✓' : 'Error restoring: ${_service.lastActionError ?? "unknown error"}'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> unpublishTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Unpublish Form',
      message: 'This will revert the form to draft status. It will no longer be visible to admins or mobile users. Continue?',
      confirmLabel: 'Unpublish',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;

    final success = await _service.unpublishTemplate(_activeTemplateId!);
    if (success) {
      _formStatus = 'draft';
      notifyListeners();
      await _loadTemplateList();
    }
  }

  Future<bool> confirmLeave() async {
    if (!_hasUnsavedChanges) return true;
    final confirmed = await _showConfirmDialog(
      title: 'Unsaved Changes',
      message: 'You have unsaved changes. Leave without saving?',
      confirmLabel: 'Leave',
      confirmColor: Colors.red,
    );
    return confirmed == true;
  }

  void addSection() {
    _sections.add(BuilderSection(name: 'Section ${_sections.length + 1}', order: _sections.length));
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void removeSection(int si) {
    _sections.removeAt(si);
    _activeSectionIdx = null;
    _activeFieldIdx = null;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void moveSection(int si, int dir) {
    final ni = si + dir;
    if (ni < 0 || ni >= _sections.length) return;
    final s = _sections.removeAt(si);
    _sections.insert(ni, s);
    _activeSectionIdx = ni;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void addField(int si) {
    final section = _sections[si];
    section.fields.add(BuilderField(label: 'Question ${section.fields.length + 1}', order: section.fields.length));
    _activeSectionIdx = si;
    _activeFieldIdx = section.fields.length - 1;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  static const _systemBlocks = <FormFieldType, ({String label, String fieldName, String desc, IconData icon})>{
    FormFieldType.membershipGroup: (label: 'Membership Group', fieldName: 'membership_group', desc: 'Solo Parent, PWD, 4Ps, PHIC checkboxes', icon: Icons.group_outlined),
    FormFieldType.computed: (label: 'Computed Field', fieldName: 'computed_field', desc: 'Auto-calculated value (income, expenses, etc.)', icon: Icons.calculate_outlined),
    FormFieldType.signature: (label: 'Signature', fieldName: 'signature', desc: 'Applicant draws their signature on screen. Saved as a base64 image in field values.', icon: Icons.draw_outlined),
  };

  static const _familyTableCoreColumns = <({String label, String fieldName, String dbMapKey, FormFieldType type})>[
    (label: 'Name', fieldName: 'name', dbMapKey: 'name', type: FormFieldType.text),
    (label: 'Relationship', fieldName: 'relationship_of_relative', dbMapKey: 'relationship_of_relative', type: FormFieldType.text),
    (label: 'Birthdate', fieldName: 'birthdate', dbMapKey: 'birthdate', type: FormFieldType.date),
    (label: 'Age', fieldName: 'age', dbMapKey: 'age', type: FormFieldType.number),
    (label: 'Sex', fieldName: 'gender', dbMapKey: 'gender', type: FormFieldType.dropdown),
    (label: 'Civil Status', fieldName: 'civil_status', dbMapKey: 'civil_status', type: FormFieldType.dropdown),
    (label: 'Education', fieldName: 'education', dbMapKey: 'education', type: FormFieldType.dropdown),
    (label: 'Occupation', fieldName: 'occupation', dbMapKey: 'occupation', type: FormFieldType.text),
    (label: 'Allowance (₱)', fieldName: 'allowance', dbMapKey: 'allowance', type: FormFieldType.number),
  ];

  void addSystemField(int si, FormFieldType type) {
    final block = _systemBlocks[type];
    if (block == null) return;
    final section = _sections[si];
    final allFields = _sections.expand((s) => s.fields);
    if (const {FormFieldType.membershipGroup, FormFieldType.signature}.contains(type) && allFields.any((f) => f.type == type)) {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(SnackBar(content: Text('A "${block.label}" block already exists in this form.'), backgroundColor: Colors.orange.shade700));
      }
      return;
    }

    List<BuilderColumn> columns = [];
    if (type == FormFieldType.familyTable) {
      columns = _familyTableCoreColumns.asMap().entries.map((e) => BuilderColumn(label: e.value.label, fieldName: e.value.fieldName, type: e.value.type, order: e.key, dbMapKey: e.value.dbMapKey)).toList();
    }

    final generatedFieldName = type == FormFieldType.computed ? 'computed_${_generateUuid().substring(0, 8)}' : block.fieldName;
    section.fields.add(BuilderField(label: block.label, fieldName: generatedFieldName, type: type, isRequired: false, canonicalFieldKey: type == FormFieldType.signature ? 'signature' : null, order: section.fields.length, options: [], columns: columns));
    _activeSectionIdx = si;
    _activeFieldIdx = section.fields.length - 1;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void removeField(int si, int fi) {
    _sections[si].fields.removeAt(fi);
    _activeFieldIdx = null;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void duplicateField(int si, int fi) {
    final src = _sections[si].fields[fi];
    _sections[si].fields.insert(fi + 1, BuilderField(label: '${src.label} (copy)', type: src.type, isRequired: src.isRequired, placeholder: src.placeholder, canonicalFieldKey: src.canonicalFieldKey, ageFromFieldId: src.ageFromFieldId, order: fi + 1, options: src.options.map((o) => BuilderOption(label: o.label)).toList(), condition: BuilderCondition(triggerFieldId: src.condition.triggerFieldId, triggerValue: src.condition.triggerValue, action: src.condition.action)));
    _activeFieldIdx = fi + 1;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void moveField(int si, int fi, int dir) {
    final ni = fi + dir;
    if (ni < 0 || ni >= _sections[si].fields.length) return;
    final f = _sections[si].fields.removeAt(fi);
    _sections[si].fields.insert(ni, f);
    _activeFieldIdx = ni;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void moveColumn(BuilderField field, int ci, int dir) {
    final ni = ci + dir;
    if (ni < 0 || ni >= field.columns.length) return;
    final col = field.columns.removeAt(ci);
    field.columns.insert(ni, col);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearCtrls();
    super.dispose();
  }
}
