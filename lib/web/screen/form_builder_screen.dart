// Form Builder Screen
// Dashboard-style interface for superadmins to create/edit form templates.
//
// Layout: Template list panel (left) + Toolbar + Builder canvas (center)
// Supports: Multiple choice, checkboxes, dropdown, short answer, paragraph,
//           linear scale, date, time, number, yes/no field types.
// Workflow: Draft → Publish (to admins) → Push to Mobile

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/form_builder_service.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';

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
  FormFieldType.membershipGroup: 'Membership Group',
  FormFieldType.familyTable: 'Family Table',
  FormFieldType.supportingFamilyTable: 'Supporting Family Table',
  FormFieldType.signature: 'Signature',
  FormFieldType.unknown: 'Unknown',
};

const _systemTypeIcons = <FormFieldType, IconData>{
  FormFieldType.computed: Icons.calculate_outlined,
  FormFieldType.membershipGroup: Icons.group_outlined,
  FormFieldType.familyTable: Icons.table_chart_outlined,
  FormFieldType.supportingFamilyTable: Icons.table_chart_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.unknown: Icons.help_outline,
};

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
  FormFieldType type; // text, number, date, dropdown
  int order;
  List<_BuilderOption> options; // only for dropdown columns

  /// For familyTable core columns only. Maps this UI column to a specific
  /// column in the `family_composition` DB table (e.g. "relationship_of_relative").
  /// Null for custom (non-core) columns added by the superadmin.
  String? dbMapKey;

  _BuilderColumn({
    String? id,
    this.label = 'Column',
    String? fieldName,
    this.type = FormFieldType.text,
    this.order = 0,
    List<_BuilderOption>? options,
    this.dbMapKey,
  })  : id = id ?? _generateUuid(),
        fieldName = fieldName ?? 'col_${_generateUuid().substring(0, 8)}',
        options = options ?? [];

  /// Whether this column has a DB mapping. Used by the interceptor for
  /// best-effort routing — no longer prevents deletion or editing in the UI.
  bool get isCoreColumn => dbMapKey != null;
}

class _BuilderField {
  String id;
  String label;
  String fieldName;
  FormFieldType type;
  bool isRequired;
  String? placeholder;
  int order;
  List<_BuilderOption> options;
  List<_BuilderColumn> columns; // for memberTable
  int scaleMin;
  int scaleMax;

  _BuilderField({
    String? id,
    this.label = 'Untitled Question',
    String? fieldName,
    this.type = FormFieldType.radio,
    this.isRequired = false,
    this.placeholder,
    this.order = 0,
    List<_BuilderOption>? options,
    List<_BuilderColumn>? columns,
    this.scaleMin = 1,
    this.scaleMax = 5,
  })  : id = id ?? _generateUuid(),
        fieldName = fieldName ?? 'field_${_generateUuid().substring(0, 8)}',
        options = options ?? [_BuilderOption(label: 'Option 1', order: 0)],
        columns = columns ?? [];

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
  })  : id = id ?? _generateUuid(),
        fields = fields ?? [];
}

// ═══════════════════════════════════════════════════════════════
// FORM BUILDER SCREEN
// ═══════════════════════════════════════════════════════════════
class FormBuilderScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String? editTemplateId;

  const FormBuilderScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.editTemplateId,
  });

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  final _service = FormBuilderService();
  final _supabase = Supabase.instance.client;
  final _scrollCtrl = ScrollController();

  // Template list
  List<Map<String, dynamic>> _templates = [];
  bool _isLoadingList = true;

  // Active builder state
  String? _activeTemplateId;
  String _formName = '';
  String _formDesc = '';
  String _formStatus = 'draft';
  List<_BuilderSection> _sections = [];

  // Selection tracking
  int? _activeSectionIdx;
  int? _activeFieldIdx;

  // Flags
  bool _isSaving = false;
  bool _isLoadingTemplate = false;
  bool _hasUnsavedChanges = false;

  // Text controller cache (prevents cursor jump on rebuild)
  final Map<String, TextEditingController> _ctrls = {};

  TextEditingController _ctrl(String key, String initial) {
    return _ctrls.putIfAbsent(
        key, () => TextEditingController(text: initial));
  }

  void _clearCtrls() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
  }

  @override
  void initState() {
    super.initState();
    _loadTemplateList().then((_) {
      if (widget.editTemplateId != null) {
        _loadTemplate(widget.editTemplateId!);
      }
    });
  }

  @override
  void dispose() {
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

  Future<void> _loadTemplate(String templateId) async {
    setState(() => _isLoadingTemplate = true);
    _clearCtrls();

    final data = await _service.fetchTemplateWithStructure(templateId);
    if (!mounted) return;
    if (data == null) {
      setState(() => _isLoadingTemplate = false);
      return;
    }

    // Parse sections & fields into builder models
    final rawSections = (data['form_sections'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
      ..sort((a, b) => ((a['section_order'] as int?) ?? 0)
          .compareTo((b['section_order'] as int?) ?? 0));
    final rawFields = (data['form_fields'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((f) {
      final vr = f['validation_rules'] as Map<String, dynamic>?;
      return vr == null || vr['_archived'] != true;
    }).toList();

    // Separate child column-definition fields from top-level fields
    final childFields = rawFields
        .where((f) => f['parent_field_id'] != null)
        .toList();
    final topLevelFields = rawFields
        .where((f) => f['parent_field_id'] == null)
        .toList();

    // Group children by parent_field_id
    final childrenByParent = <String, List<Map<String, dynamic>>>{};
    for (final cf in childFields) {
      final pid = cf['parent_field_id'] as String;
      childrenByParent.putIfAbsent(pid, () => []).add(cf);
    }

    final sections = rawSections.map((s) {
      final sFields = topLevelFields
          .where((f) => f['section_id'] == s['section_id'])
          .toList()
        ..sort((a, b) => ((a['field_order'] as int?) ?? 0)
            .compareTo((b['field_order'] as int?) ?? 0));

      return _BuilderSection(
        id: s['section_id'] as String,
        name: s['section_name'] as String? ?? 'Untitled Section',
        description: s['section_desc'] as String?,
        order: (s['section_order'] as int?) ?? 0,
        fields: sFields.map((f) {
          final rawOpts =
              (f['form_field_options'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>()
                ..sort((a, b) => ((a['option_order'] as int?) ?? 0)
                    .compareTo((b['option_order'] as int?) ?? 0));

          // Parse columns for member_table and family_table fields
          List<_BuilderColumn> columns = [];
          final fid = f['field_id'] as String;
          final ftype = f['field_type'] as String? ?? '';
          if ((ftype == 'member_table' || ftype == 'family_table') &&
              childrenByParent.containsKey(fid)) {
            final childList = childrenByParent[fid]!
              ..sort((a, b) => ((a['field_order'] as int?) ?? 0)
                  .compareTo((b['field_order'] as int?) ?? 0));
            columns = childList.map((cf) {
              final colOpts =
                  (cf['form_field_options'] as List<dynamic>? ?? [])
                      .cast<Map<String, dynamic>>()
                    ..sort((a, b) => ((a['option_order'] as int?) ?? 0)
                        .compareTo((b['option_order'] as int?) ?? 0));
              // Read db_map_key from validation_rules for system table cols
              final vr = cf['validation_rules'] as Map<String, dynamic>?;
              return _BuilderColumn(
                id: cf['field_id'] as String,
                label: cf['field_label'] as String? ?? '',
                fieldName: cf['field_name'] as String? ?? '',
                type: FormFieldType.fromString(
                    cf['field_type'] as String? ?? 'text'),
                order: (cf['field_order'] as int?) ?? 0,
                dbMapKey: vr?['db_map_key'] as String?,
                options: colOpts
                    .map((o) => _BuilderOption(
                          id: o['option_id'] as String,
                          label: o['option_label'] as String? ?? '',
                          order: (o['option_order'] as int?) ?? 0,
                        ))
                    .toList(),
              );
            }).toList();
          }

          return _BuilderField(
            id: f['field_id'] as String,
            label: f['field_label'] as String? ?? '',
            fieldName: f['field_name'] as String? ?? '',
            type: FormFieldType.fromString(
                f['field_type'] as String? ?? 'text'),
            isRequired: (f['is_required'] as bool?) ?? false,
            placeholder: f['placeholder'] as String?,
            order: (f['field_order'] as int?) ?? 0,
            columns: columns,
            options: rawOpts
                .map((o) => _BuilderOption(
                      id: o['option_id'] as String,
                      label: o['option_label'] as String? ?? '',
                      order: (o['option_order'] as int?) ?? 0,
                    ))
                .toList(),
          );
        }).toList(),
      );
    }).toList();

    setState(() {
      _activeTemplateId = templateId;
      _formName = data['form_name'] as String? ?? 'Untitled Form';
      _formDesc = data['form_desc'] as String? ?? '';
      _formStatus = data['status'] as String? ?? 'draft';
      _sections = sections;
      _activeSectionIdx = null;
      _activeFieldIdx = null;
      _hasUnsavedChanges = false;
      _isLoadingTemplate = false;
    });
  }

  // ── CRUD Operations ─────────────────────────────────────────
  Future<void> _createNewTemplate() async {
    final id = await _service.createTemplate(
      formName: 'Untitled Form',
      formDesc: '',
      createdBy: widget.cswd_id,
    );
    if (id == null || !mounted) return;
    await _loadTemplateList();
    _clearCtrls();

    // Start with one section and one question
    setState(() {
      _activeTemplateId = id;
      _formName = 'Untitled Form';
      _formDesc = '';
      _formStatus = 'draft';
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

    // Build DB payloads from builder state
    final dbSections = <Map<String, dynamic>>[];
    final dbFields = <Map<String, dynamic>>[];
    final dbOptions = <Map<String, dynamic>>[];

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
        dbFields.add({
          'field_id': field.id,
          'template_id': _activeTemplateId,
          'section_id': section.id,
          'field_name': field.fieldName,
          'field_label': field.label,
          'field_type': field.type.toDbString(),
          'is_required': field.isRequired,
          'placeholder': field.placeholder,
          'field_order': fi,
        });

        // Serialize member table columns as child fields
        if (field.type == FormFieldType.memberTable ||
            field.type == FormFieldType.familyTable) {
          for (var ci = 0; ci < field.columns.length; ci++) {
            final col = field.columns[ci];
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
              // Persist db_map_key so the interceptor knows which DB
              // column this UI column maps to.
              if (col.dbMapKey != null)
                'validation_rules': {'db_map_key': col.dbMapKey},
            });

            // Column options (for dropdown columns)
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
      }
    }

    final success = await _service.saveTemplateStructure(
      templateId: _activeTemplateId!,
      formName: _formName,
      formDesc: _formDesc,
      sections: dbSections,
      fields: dbFields,
      options: dbOptions,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (success) _hasUnsavedChanges = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'Template saved'
          : 'Error saving template: ${_service.lastSaveError ?? "unknown"}'),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
    await _loadTemplateList();
  }

  Future<void> _publishTemplate() async {
    if (_activeTemplateId == null) return;

    // Validate: must have at least one section with one field
    final hasFields = _sections.any((s) => s.fields.isNotEmpty);
    if (!hasFields) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add at least one section with a question before publishing.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (_hasUnsavedChanges) await _saveTemplate();

    final confirmed = await _showConfirmDialog(
      title: 'Publish Form',
      message: 'This will make the form visible to all admin users in their '
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
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Form published ✓' : 'Error publishing'),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pushToMobile() async {
    if (_activeTemplateId == null) return;

    final confirmed = await _showConfirmDialog(
      title: 'Push to Mobile',
      message: 'This will make the form available on the mobile app. '
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
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Pushed to mobile ✓' : 'Error pushing'),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _deleteTemplate() async {
    if (_activeTemplateId == null) return;

    // First check for submissions
    final result = await _service.deleteTemplate(_activeTemplateId!);
    if (!mounted) return;

    if (result['success'] == true) {
      _clearCtrls();
      setState(() {
        _activeTemplateId = null;
        _sections.clear();
        _formName = '';
        _formDesc = '';
        _hasUnsavedChanges = false;
      });
      await _loadTemplateList();
      return;
    }

    // Has submissions — offer archive or force-delete
    final subCount = result['submissionCount'] as int? ?? 0;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cannot Delete'),
        content: Text(
          '$subCount submission(s) reference this form.\n\n'
          'You can Archive it (preserves data) or Force Delete '
          '(permanently removes the form and all submissions).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'archive'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Archive',
                style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'force'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Force Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (choice == 'archive') {
      await _archiveTemplate();
    } else if (choice == 'force') {
      final confirm2 = await _showConfirmDialog(
        title: 'Force Delete — Are you sure?',
        message: 'This will permanently destroy the template AND all '
            '$subCount submission(s). This cannot be undone.',
        confirmLabel: 'Delete Everything',
        confirmColor: Colors.red,
      );
      if (confirm2 != true || !mounted) return;
      final ok = await _service.forceDeleteTemplate(_activeTemplateId!);
      if (!mounted) return;
      if (ok) {
        _clearCtrls();
        setState(() {
          _activeTemplateId = null;
          _sections.clear();
          _formName = '';
          _formDesc = '';
          _hasUnsavedChanges = false;
        });
        await _loadTemplateList();
      }
    }
  }

  Future<void> _archiveTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Archive Form',
      message: 'This will remove the form from admins\' and mobile users\' '
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
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Form archived ✓' : 'Error archiving'),
      backgroundColor: success ? Colors.orange : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _restoreTemplate() async {
    if (_activeTemplateId == null) return;
    final success = await _service.restoreTemplate(_activeTemplateId!);
    if (!mounted) return;
    if (success) {
      setState(() => _formStatus = 'draft');
      await _loadTemplateList();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Form restored to draft ✓' : 'Error restoring'),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _unpublishTemplate() async {
    if (_activeTemplateId == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Unpublish Form',
      message: 'This will revert the form to draft status. It will no longer '
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
            child:
                Text(confirmLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Builder Actions ─────────────────────────────────────────
  void _addSection() {
    setState(() {
      _sections.add(_BuilderSection(
        name: 'Section ${_sections.length + 1}',
        order: _sections.length,
      ));
      _hasUnsavedChanges = true;
    });
  }

  void _addField(int si) {
    final section = _sections[si];
    setState(() {
      section.fields.add(_BuilderField(
        label: 'Question ${section.fields.length + 1}',
        order: section.fields.length,
      ));
      _activeSectionIdx = si;
      _activeFieldIdx = section.fields.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  // ── System block definitions ───────────────────────────────
  static const _systemBlocks = <FormFieldType, ({String label, String fieldName, String desc, IconData icon})>{
    FormFieldType.membershipGroup: (
      label: 'Membership Group',
      fieldName: 'membership_group',
      desc: 'Solo Parent, PWD, 4Ps, PHIC checkboxes',
      icon: Icons.group_outlined,
    ),
    FormFieldType.familyTable: (
      label: 'Family Composition',
      fieldName: 'family_composition',
      desc: 'Table for household members',
      icon: Icons.table_chart_outlined,
    ),
    FormFieldType.supportingFamilyTable: (
      label: 'Supporting Family Members',
      fieldName: 'supporting_family_members',
      desc: 'Table for supporting relatives',
      icon: Icons.table_chart_outlined,
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
      desc: 'Applicant draws their signature on screen. Saved as a base64 image in field values.',
      icon: Icons.draw_outlined,
    ),
  };

  // The 9 core columns of the family_composition DB table.
  // Each entry: (label, fieldName, dbMapKey, type)
  static const _familyTableCoreColumns = <({
    String label,
    String fieldName,
    String dbMapKey,
    FormFieldType type,
  })>[
    (label: 'Name',           fieldName: 'name',                       dbMapKey: 'name',                       type: FormFieldType.text),
    (label: 'Relationship',   fieldName: 'relationship_of_relative',   dbMapKey: 'relationship_of_relative',   type: FormFieldType.text),
    (label: 'Birthdate',      fieldName: 'birthdate',                  dbMapKey: 'birthdate',                  type: FormFieldType.date),
    (label: 'Age',            fieldName: 'age',                        dbMapKey: 'age',                        type: FormFieldType.number),
    (label: 'Sex',            fieldName: 'gender',                     dbMapKey: 'gender',                     type: FormFieldType.dropdown),
    (label: 'Civil Status',   fieldName: 'civil_status',               dbMapKey: 'civil_status',               type: FormFieldType.dropdown),
    (label: 'Education',      fieldName: 'education',                  dbMapKey: 'education',                  type: FormFieldType.dropdown),
    (label: 'Occupation',     fieldName: 'occupation',                 dbMapKey: 'occupation',                 type: FormFieldType.text),
    (label: 'Allowance (₱)',  fieldName: 'allowance',                  dbMapKey: 'allowance',                  type: FormFieldType.number),
  ];

  void _addSystemField(int si, FormFieldType type) {
    final block = _systemBlocks[type];
    if (block == null) return;
    final section = _sections[si];

    // Prevent duplicates for one-per-form blocks
    final allFields = _sections.expand((s) => s.fields);
    if (const {
      FormFieldType.membershipGroup,
      FormFieldType.familyTable,
      FormFieldType.supportingFamilyTable,
      FormFieldType.signature,
    }.contains(type) && allFields.any((f) => f.type == type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A "${block.label}" block already exists in this form.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    // Pre-populate familyTable with its 9 core DB-mapped columns
    List<_BuilderColumn> columns = [];
    if (type == FormFieldType.familyTable) {
      columns = _familyTableCoreColumns
          .asMap()
          .entries
          .map((e) => _BuilderColumn(
                label: e.value.label,
                fieldName: e.value.fieldName,
                type: e.value.type,
                order: e.key,
                dbMapKey: e.value.dbMapKey,
              ))
          .toList();
    }

    setState(() {
      section.fields.add(_BuilderField(
        label: block.label,
        fieldName: block.fieldName,
        type: type,
        isRequired: false,
        order: section.fields.length,
        options: [],
        columns: columns,
      ));
      _activeSectionIdx = si;
      _activeFieldIdx = section.fields.length - 1;
      _hasUnsavedChanges = true;
    });
  }

  void _showSystemBlockPicker(int si) {
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
                final exists = _sections
                    .expand((s) => s.fields)
                    .any((f) => f.type == e.key);
                return ListTile(
                  leading: Icon(block.icon,
                      color: exists ? AppColors.textMuted : AppColors.highlight),
                  title: Text(block.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: exists ? AppColors.textMuted : AppColors.textDark,
                      )),
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
                    _addSystemField(si, e.key);
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
          order: fi + 1,
          options: src.options
              .map((o) => _BuilderOption(label: o.label))
              .toList(),
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
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleLogout() async {
    if (!await _confirmLeave()) return;
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ContentFadeRoute(page: const WorkerLoginScreen()),
      (route) => false,
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    if ((screenPath == 'Staff' || screenPath == 'CreateStaff' ||
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
            onLogout: _handleLogout);
        break;
      case 'Forms':
        next = ManageFormsScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      case 'Staff':
        next = ManageStaffScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      case 'CreateStaff':
        next = CreateStaffScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      case 'Applicants':
        next = ApplicantsScreen(
            cswd_id: widget.cswd_id, role: widget.role);
        break;
      default:
        return;
    }
    _confirmLeave().then((ok) {
      if (!ok || !mounted) return;
      Navigator.of(context).pushReplacement(ContentFadeRoute(page: next));
    });
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'FormBuilder',
      pageTitle: 'Form Builder',
      pageSubtitle: _activeTemplateId != null
          ? '$_formName${_hasUnsavedChanges ? '  •  unsaved changes' : ''}'
          : 'Create and manage form templates',
      role: widget.role,
      onLogout: _handleLogout,
      headerActions: _buildHeaderActions(),
      onNavigate: (path) => _navigateToScreen(context, path),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTemplateListPanel(),
          Expanded(
            child: _activeTemplateId == null
                ? _buildEmptyState()
                : _isLoadingTemplate
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.highlight))
                    : _buildBuilderCanvas(),
          ),
        ],
      ),
    );
  }

  // ── Header Actions ──────────────────────────────────────────
  List<Widget> _buildHeaderActions() {
    if (_activeTemplateId == null) return [];
    return [
      if (_formStatus == 'draft') ...[
        _headerBtn('Save Draft', Icons.save_outlined,
            onPressed: _isSaving ? null : _saveTemplate),
        const SizedBox(width: 8),
        _headerBtn('Publish', Icons.publish,
            color: AppColors.highlight, onPressed: _publishTemplate),
      ],
      if (_formStatus == 'published') ...[
        _headerBtn('Save', Icons.save_outlined,
            onPressed: _isSaving ? null : _saveTemplate),
        const SizedBox(width: 8),
        _headerBtn('Push to Mobile', Icons.phone_android,
            color: Colors.green, onPressed: _pushToMobile),
      ],
      if (_formStatus == 'pushed_to_mobile') ...[
        _headerBtn('Save', Icons.save_outlined,
            onPressed: _isSaving ? null : _saveTemplate),
      ],
      if (_formStatus == 'archived') ...[
        _headerBtn('Restore', Icons.restore,
            color: Colors.teal, onPressed: _restoreTemplate),
      ],
    ];
  }

  Widget _headerBtn(String label, IconData icon,
      {VoidCallback? onPressed, Color? color}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: _isSaving && icon == Icons.save_outlined
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Icon(icon, color: Colors.white, size: 18),
      label: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? AppColors.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TEMPLATE LIST PANEL (left sidebar)
  // ═══════════════════════════════════════════════════════════
  Widget _buildTemplateListPanel() {
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
                const Icon(Icons.description_outlined,
                    color: AppColors.textDark, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('My Templates',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textDark)),
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
          Expanded(
            child: _isLoadingList
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.highlight))
                : _templates.isEmpty
                    ? _buildNoTemplates()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _templates.length,
                        itemBuilder: (_, i) => _buildTemplateListItem(_templates[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTemplates() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_add_outlined,
              size: 48, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text('No templates yet',
              style: TextStyle(color: AppColors.textMuted)),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.description_outlined,
            color: isActive ? AppColors.highlight : AppColors.textMuted,
            size: 20),
        title: Text(name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: AppColors.textDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: statusClr, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(statusLbl,
                style: TextStyle(fontSize: 11, color: statusClr)),
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
          Icon(Icons.edit_note,
              size: 80, color: AppColors.highlight.withOpacity(0.3)),
          const SizedBox(height: 24),
          const Text('Select a template or create a new one',
              style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _createNewTemplate,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('New Form',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
    return Container(
      color: AppColors.pageBg,
      child: Column(
        children: [
          // ── Static toolbar ──
          _buildCanvasToolbar(),
          // ── Scrollable canvas ──
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 680,
                  child: Column(
                    children: [
                      _buildTitleCard(),
                      const SizedBox(height: 12),
                      ..._buildAllSections(),
                      const SizedBox(height: 16),
                      _buildAddSectionButton(),
                      const SizedBox(height: 16),
                      _buildStatusCard(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Canvas Toolbar (static, top of builder area) ──────────
  Widget _buildCanvasToolbar() {
    // Determine the section index to add to: use active section, or last section
    final targetSi = _activeSectionIdx ?? (_sections.isNotEmpty ? _sections.length - 1 : null);

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
            icon: const Icon(Icons.add_circle_outline, size: 18,
                color: Colors.white),
            label: const Text('Add Question',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: targetSi != null
                ? () => _showSystemBlockPicker(targetSi)
                : null,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
            label: const Text('Add Intake Module',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              side: const BorderSide(color: AppColors.highlight),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const Spacer(),
          if (_activeSectionIdx != null)
            Text(
              'Active: ${_sections[_activeSectionIdx!].name}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  // ── Title Card ──────────────────────────────────────────────
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
            // Form name
            TextField(
              controller: _ctrl('formName', _formName),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textDark),
              decoration: const InputDecoration(
                hintText: 'Untitled Form',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.cardBorder)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.highlight, width: 2)),
              ),
              onChanged: (v) {
                _formName = v;
                _hasUnsavedChanges = true;
              },
            ),
            const SizedBox(height: 8),
            // Description
            TextField(
              controller: _ctrl('formDesc', _formDesc),
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textMuted),
              decoration: const InputDecoration(
                hintText: 'Form description',
                hintStyle:
                    TextStyle(color: AppColors.textMuted, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.transparent)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.highlight, width: 1)),
              ),
              onChanged: (v) {
                _formDesc = v;
                _hasUnsavedChanges = true;
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────
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
                    section.fields[fi], si, fi, isFieldActive);
              }),
            ],
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildSectionHeader(
      _BuilderSection section, int si, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() {
        _activeSectionIdx = si;
        _activeFieldIdx = null;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive ? AppColors.highlight : AppColors.cardBorder),
        ),
        child: Row(
          children: [
            // Thin left accent for active state only
            if (isActive)
              Container(
                width: 3,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.highlight,
                  borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(8)),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    isActive ? 13 : 16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActive)
                      TextField(
                        controller: _ctrl('sec_${section.id}', section.name),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textDark),
                        decoration: const InputDecoration(
                          hintText: 'Section Title',
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.cardBorder)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.highlight, width: 2)),
                        ),
                        onChanged: (v) {
                          section.name = v;
                          _hasUnsavedChanges = true;
                        },
                      )
                    else
                      Text(section.name,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textDark)),
                    if (isActive)
                      TextField(
                        controller: _ctrl(
                            'sec_desc_${section.id}',
                            section.description ?? ''),
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted),
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
                onPressed:
                    si > 0 ? () => _moveSection(si, -1) : null,
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
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
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
  Widget _buildFieldCard(
      _BuilderField field, int si, int fi, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() {
        _activeSectionIdx = si;
        _activeFieldIdx = fi;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive ? AppColors.highlight : AppColors.cardBorder),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thin left accent for active state only
              if (isActive)
                Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(8)),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      isActive ? 18 : 24, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Label + Type selector ──
                      if (isActive)
                        _buildFieldHeaderActive(field)
                      else
                        _buildFieldHeaderInactive(field),
                      const SizedBox(height: 12),
                      // ── Type-specific content ──
                      _buildFieldContent(field, isActive),
                      // ── Bottom toolbar ──
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _ctrl('fld_${field.id}', field.label),
            style: const TextStyle(
                fontSize: 15, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'Question',
              filled: true,
              fillColor: AppColors.pageBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.highlight)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
            onChanged: (v) {
              field.label = v;
              field.fieldName = _slugify(v);
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
            child: field.type.isSystemType
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
                    fontSize: 13, color: AppColors.textDark),
                items: _typeLabels.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Row(
                      children: [
                        Icon(_typeIcons[e.key],
                            size: 18, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(e.value,
                                overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;

                  if (v == FormFieldType.signature) {
                    final hasOtherSignature = _sections
                        .expand((s) => s.fields)
                        .any((f) => f.type == FormFieldType.signature && f.id != field.id);
                    if (hasOtherSignature) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                              'A "Signature" block already exists in this form.'),
                          backgroundColor: Colors.orange.shade700,
                        ),
                      );
                      return;
                    }
                  }

                  setState(() {
                    field.type = v;
                    if (field.hasOptions && field.options.isEmpty) {
                      field.options
                          .add(_BuilderOption(label: 'Option 1'));
                    }
                    _hasUnsavedChanges = true;
                  });
                },
              ),
            ),
          ),
        ),
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
            size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(field.label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textDark)),
        ),
        if (field.isRequired)
          const Text(' *',
              style: TextStyle(
                  color: Colors.red, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFieldToolbar(_BuilderField field, int si, int fi) {
    return Wrap(
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
          icon:
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
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
        const Text('Required',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Switch(
          value: field.isRequired,
          activeColor: AppColors.highlight,
          onChanged: (v) => setState(() {
            field.isRequired = v;
            _hasUnsavedChanges = true;
          }),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FIELD TYPE CONTENT (type-specific editors/previews)
  // ═══════════════════════════════════════════════════════════
  Widget _buildFieldContent(_BuilderField field, bool isActive) {
    switch (field.type) {
      case FormFieldType.text:
        return _textPreview('Short answer text');
      case FormFieldType.paragraph:
        return _textPreview('Long answer text');
      case FormFieldType.number:
        return _textPreview('Number');
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

  Widget _textPreview(String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(hint,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 13)),
      ),
    );
  }

  Widget _iconPreview(String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Text(hint,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
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
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textDark)),
        ],
      ),
    );
  }

  // ── Linear Scale Editor ─────────────────────────────────────
  Widget _buildLinearScaleEditor(_BuilderField field, bool isActive) {
    if (!isActive) {
      return Row(
        children: [
          Text('${field.scaleMin}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted)),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.cardBorder,
            ),
          ),
          Text('${field.scaleMax}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted)),
        ],
      );
    }
    return Row(
      children: [
        const Text('From:',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMin,
          items: [0, 1]
              .map((v) =>
                  DropdownMenuItem(value: v, child: Text('$v')))
              .toList(),
          onChanged: (v) => setState(() {
            field.scaleMin = v!;
            _hasUnsavedChanges = true;
          }),
        ),
        const SizedBox(width: 24),
        const Text('To:',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMax,
          items: List.generate(9, (i) => i + 2)
              .map((v) =>
                  DropdownMenuItem(value: v, child: Text('$v')))
              .toList(),
          onChanged: (v) => setState(() {
            field.scaleMax = v!;
            _hasUnsavedChanges = true;
          }),
        ),
      ],
    );
  }

  // ── Column Editor (member table) ──────────────────────────────
  Widget _buildColumnEditor(_BuilderField field, bool isActive) {
    const columnTypes = <FormFieldType, String>{
      FormFieldType.text: 'Text',
      FormFieldType.number: 'Number',
      FormFieldType.date: 'Date',
      FormFieldType.dropdown: 'Dropdown',
    };

    if (!isActive) {
      if (field.columns.isEmpty) {
        return const Text('No columns defined',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${field.columns.length} column(s) defined',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: field.columns.map((c) {
              return Chip(
                label: Text(
                    '${c.label} (${columnTypes[c.type] ?? c.type.toDbString()})',
                    style: const TextStyle(fontSize: 11)),
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
        const Text('Table Columns',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
        const SizedBox(height: 8),
        ...field.columns.asMap().entries.map((entry) {
          final ci = entry.key;
          final col = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ctrl('col_${col.id}', col.label),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Column name',
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
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
                            fontSize: 12, color: AppColors.textDark),
                        items: columnTypes.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            col.type = v;
                            if (v == FormFieldType.dropdown &&
                                col.options.isEmpty) {
                              col.options
                                  .add(_BuilderOption(label: 'Option 1'));
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
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() {
                    field.columns.removeAt(ci);
                    _hasUnsavedChanges = true;
                  }),
                ),
              ],
            ),
          );
        }),

        // Dropdown options sub-editors
        ...field.columns
            .where((c) => c.type == FormFieldType.dropdown)
            .map((col) => Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Options for "${col.label}":',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                      ...col.options.asMap().entries.map((oe) {
                        final opt = oe.value;
                        return Row(
                          children: [
                            const Icon(Icons.arrow_right,
                                size: 16, color: AppColors.textMuted),
                            Expanded(
                              child: TextField(
                                controller:
                                    _ctrl('colopt_${opt.id}', opt.label),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'Option',
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 6),
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
                          col.options.add(_BuilderOption(
                              label: 'Option ${col.options.length + 1}'));
                          _hasUnsavedChanges = true;
                        }),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add option',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                )),

        // Add column button
        TextButton.icon(
          onPressed: () => setState(() {
            field.columns.add(_BuilderColumn(
              label: 'Column ${field.columns.length + 1}',
              order: field.columns.length,
            ));
            _hasUnsavedChanges = true;
          }),
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── System Table Column Editor (familyTable) ───────────────
  // Fully dynamic: all columns (including pre-populated DB-mapped ones)
  // can be relabeled, retyped, or deleted. Staff can also add new columns.
  // The backend interceptor uses best-effort mapping via db_map_key.
  Widget _buildSystemTableColumnEditor(_BuilderField field, bool isActive) {
    const columnTypes = <FormFieldType, String>{
      FormFieldType.text: 'Text',
      FormFieldType.number: 'Number',
      FormFieldType.date: 'Date',
      FormFieldType.dropdown: 'Dropdown',
    };

    if (!isActive) {
      if (field.columns.isEmpty) {
        return const Text('No columns defined',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${field.columns.length} column(s) defined',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: field.columns.map((c) {
              return Chip(
                label: Text(
                    '${c.label} (${columnTypes[c.type] ?? c.type.toDbString()})',
                    style: const TextStyle(fontSize: 11)),
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
        const Text('Table Columns',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
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
            child: Row(
              children: [
                // Editable label
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ctrl('col_${col.id}', col.label),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Column name',
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                    onChanged: (v) {
                      col.label = v;
                      // Only auto-slug columns without a db_map_key
                      if (col.dbMapKey == null) col.fieldName = _slugify(v);
                      _hasUnsavedChanges = true;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Column type: editable for all columns
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
                            fontSize: 12, color: AppColors.textDark),
                        items: columnTypes.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            col.type = v;
                            if (v == FormFieldType.dropdown &&
                                col.options.isEmpty) {
                              col.options
                                  .add(_BuilderOption(label: 'Option 1'));
                            }
                            _hasUnsavedChanges = true;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Delete button: available for ALL columns
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() {
                    field.columns.removeAt(ci);
                    _hasUnsavedChanges = true;
                  }),
                ),
              ],
            ),
          );
        }),

        // Dropdown options sub-editors (same as _buildColumnEditor)
        ...field.columns
            .where((c) => c.type == FormFieldType.dropdown)
            .map((col) => Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Options for "${col.label}":',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                      ...col.options.asMap().entries.map((oe) {
                        final opt = oe.value;
                        return Row(
                          children: [
                            const Icon(Icons.arrow_right,
                                size: 16, color: AppColors.textMuted),
                            Expanded(
                              child: TextField(
                                controller:
                                    _ctrl('colopt_${opt.id}', opt.label),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'Option',
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 6),
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
                          col.options.add(_BuilderOption(
                              label: 'Option ${col.options.length + 1}'));
                          _hasUnsavedChanges = true;
                        }),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add option',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                )),

        // Add column button
        TextButton.icon(
          onPressed: () => setState(() {
            field.columns.add(_BuilderColumn(
              label: 'Column ${field.columns.length + 1}',
              order: field.columns.length,
            ));
            _hasUnsavedChanges = true;
          }),
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Options Editor (radio/checkbox/dropdown) ────────────────
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
                      controller:
                          _ctrl('opt_${opt.id}', opt.label),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textDark),
                      decoration: const InputDecoration(
                        hintText: 'Option',
                        border: InputBorder.none,
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: AppColors.cardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: AppColors.highlight)),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        opt.label = v;
                        _hasUnsavedChanges = true;
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Text(opt.label,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textDark)),
                  ),
                if (isActive && field.options.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textMuted),
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
                Icon(optIcon,
                    size: 20,
                    color: AppColors.textMuted.withOpacity(0.4)),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => setState(() {
                    field.options.add(_BuilderOption(
                      label: 'Option ${field.options.length + 1}',
                      order: field.options.length,
                    ));
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

  // ── Add Section Button ─────────────────────────────────────
  Widget _buildAddSectionButton() {
    return OutlinedButton.icon(
      onPressed: _addSection,
      icon: const Icon(Icons.playlist_add, size: 20),
      label: const Text('Add Section'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.highlight,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: BorderSide(color: AppColors.highlight.withOpacity(0.5)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Status Card ─────────────────────────────────────────────
  Widget _buildStatusCard() {
    final (Color clr, String label, String desc, IconData icon) =
        switch (_formStatus) {
      'published' => (
        Colors.blue,
        'PUBLISHED',
        'Visible to admin staff in Manage Forms',
        Icons.visibility
      ),
      'pushed_to_mobile' => (
        Colors.green,
        'LIVE ON MOBILE',
        'Users can fill this form on the mobile app',
        Icons.phone_android
      ),
      'archived' => (
        Colors.grey,
        'ARCHIVED',
        'Hidden from admins & mobile. Data preserved.',
        Icons.archive_outlined
      ),
      _ => (
        Colors.orange,
        'DRAFT',
        'Only you can see this template',
        Icons.edit_note
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
                Text('Status: $label',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: clr,
                        fontSize: 13)),
                Text(desc,
                    style: TextStyle(
                        color: clr.withOpacity(0.8), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Archive action (available for draft, published, pushed_to_mobile)
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
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _deleteTemplate,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
                foregroundColor: Colors.red,
                elevation: 0,
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
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _deleteTemplate,
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('Delete Permanently'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
                foregroundColor: Colors.red,
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
