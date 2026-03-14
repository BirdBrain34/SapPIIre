// Dynamic Field Widgets
// Renders individual form fields based on field type.
// Supports text, number, date, dropdown, radio, boolean, computed fields,
// family composition table, supporting family table, membership group, and signature.
//
// Used by DynamicFormRenderer to build the complete form UI.
// Handles both mobile (with checkboxes) and web (read-only) modes.

import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/mobile/widgets/date_picker_helper.dart';

// ── Top-level dispatcher ──────────────────────────────────────
class DynamicFieldWidget extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  final bool showCheckbox;

  const DynamicFieldWidget({
    super.key,
    required this.field,
    required this.controller,
    this.isReadOnly = false,
    this.showCheckbox = false,
  });

  @override
  Widget build(BuildContext context) {
    final checkKey = field.checkKey;

    Widget fieldWidget;
    switch (field.fieldType) {
      case FormFieldType.text:
        fieldWidget = _TextField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.date:
        fieldWidget = _DateField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.number:
        fieldWidget = _NumberField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.computed:
        fieldWidget = _ComputedField(field: field, controller: controller);
        break;
      case FormFieldType.dropdown:
        fieldWidget = _DropdownField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.radio:
        fieldWidget = _RadioField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.boolean:
        fieldWidget = _BooleanField(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.membershipGroup:
        fieldWidget = _MembershipGroupField(
            controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.familyTable:
        fieldWidget = _FamilyTableField(
            controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.supportingFamilyTable:
        fieldWidget = _SupportingFamilyField(
            controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.memberTable:
        fieldWidget = _MemberTableWidget(
            field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.signature:
        fieldWidget =
            _SignatureField(controller: controller, isReadOnly: isReadOnly);
        break;
      default:
        return const SizedBox();
    }

    if (!showCheckbox) return fieldWidget;

    final skipCheckbox = field.fieldType == FormFieldType.computed ||
        field.fieldType == FormFieldType.supportingFamilyTable;
    if (skipCheckbox) return fieldWidget;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: controller.fieldChecks[checkKey] ?? false,
          onChanged: (v) {
            controller.fieldChecks[checkKey] = v ?? false;
            controller.notifyListeners();
          },
          activeColor: AppColors.primaryBlue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(child: fieldWidget),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────

InputDecoration _inputDeco(
        {String? hint, bool readOnly = false, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF5F5F8) : Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDDDDEE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDDDDEE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      suffixIcon: suffix,
    );

// ── Field label ───────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  const _FieldLabel({required this.label, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF555577)),
          children: [
            if (isRequired)
              const TextSpan(
                  text: ' *', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ── Text field ────────────────────────────────────────────────
class _TextField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _TextField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl =
        controller.textControllers[field.fieldName] ?? TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        TextFormField(
          controller: ctrl,
          readOnly: isReadOnly,
          decoration:
              _inputDeco(hint: field.placeholder, readOnly: isReadOnly),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => controller.setValue(field.fieldName, v),
        ),
      ],
    );
  }
}

// ── Number field ──────────────────────────────────────────────
class _NumberField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _NumberField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl =
        controller.textControllers[field.fieldName] ?? TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        TextFormField(
          controller: ctrl,
          readOnly: isReadOnly,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDeco(hint: '0.00', readOnly: isReadOnly),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => controller.setValue(field.fieldName, v),
        ),
      ],
    );
  }
}

// ── Computed (read-only) field ────────────────────────────────
class _ComputedField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  const _ComputedField({required this.field, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller.textControllers[field.fieldName];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel),
        TextFormField(
          controller: ctrl,
          readOnly: true,
          decoration: _inputDeco(readOnly: true),
          style: const TextStyle(
              fontSize: 13,
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── Date field ────────────────────────────────────────────────
class _DateField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _DateField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl =
        controller.textControllers[field.fieldName] ?? TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        GestureDetector(
          onTap: isReadOnly
              ? null
              : () async {
                  DateTime? initial;
                  try {
                    initial = DateTime.parse(ctrl.text);
                  } catch (_) {
                    initial = DateTime.now();
                  }
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: AppColors.primaryBlue,
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    controller.setValue(field.fieldName,
                        DatePickerHelper.formatDate(picked));
                  }
                },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isReadOnly ? const Color(0xFFF5F5F8) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDDDEE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  ctrl.text.isEmpty
                      ? (field.placeholder ?? 'Select date')
                      : ctrl.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: ctrl.text.isEmpty
                        ? Colors.black38
                        : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Dropdown field ────────────────────────────────────────────
class _DropdownField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _DropdownField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final current = controller.getValue(field.fieldName)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isReadOnly ? const Color(0xFFF5F5F8) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDDDEE)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: field.options.any((o) => o.value == current)
                  ? current
                  : null,
              hint: Text(field.placeholder ?? 'Select...',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black38)),
              isExpanded: true,
              items: field.options
                  .map((o) => DropdownMenuItem(
                      value: o.value,
                      child: Text(o.label,
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: isReadOnly
                  ? null
                  : (v) => controller.setValue(field.fieldName, v),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Radio field ───────────────────────────────────────────────
class _RadioField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _RadioField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final current = controller.getValue(field.fieldName)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: field.options.map((o) {
            final selected = current == o.value;
            return GestureDetector(
              onTap: isReadOnly
                  ? null
                  : () {
                      if (field.fieldName == 'housing_status') {
                        controller.housingStatus = o.value;
                      }
                      controller.setValue(field.fieldName, o.value);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFFF0F0F8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryBlue
                        : const Color(0xFFDDDDEE),
                  ),
                ),
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Boolean field — Switch widget ─────────────────────────────
class _BooleanField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _BooleanField(
      {required this.field,
      required this.controller,
      required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    bool current;
    if (field.fieldName == 'has_support') {
      current = controller.hasSupport;
    } else {
      current = (controller.getValue(field.fieldName) as bool?) ?? false;
    }
    return Row(
      children: [
        Switch(
          value: current,
          onChanged: isReadOnly
              ? null
              : (v) {
                  if (field.fieldName == 'has_support') {
                    controller.hasSupport = v;
                  }
                  controller.setValue(field.fieldName, v);
                },
          activeColor: AppColors.primaryBlue,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            field.fieldLabel,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// ── Membership group ──────────────────────────────────────────
class _MembershipGroupField extends StatelessWidget {
  final FormStateController controller;
  final bool isReadOnly;
  const _MembershipGroupField(
      {required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('solo_parent', 'Solo Parent'),
      ('pwd', 'PWD'),
      ('four_ps_member', '4Ps Member'),
      ('phic_member', 'PHIC Member'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Membership Group'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.map((item) {
            final selected = controller.membershipData[item.$1] ?? false;
            return GestureDetector(
              onTap: isReadOnly
                  ? null
                  : () {
                      controller.membershipData[item.$1] = !selected;
                      controller.notifyListeners();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFFF0F0F8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryBlue
                        : const Color(0xFFDDDDEE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: selected ? Colors.white : Colors.black45,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Family Composition table ──────────────────────────────────
class _FamilyTableField extends StatefulWidget {
  final FormStateController controller;
  final bool isReadOnly;
  const _FamilyTableField(
      {required this.controller, required this.isReadOnly});

  @override
  State<_FamilyTableField> createState() => _FamilyTableFieldState();
}

class _FamilyTableFieldState extends State<_FamilyTableField> {
  static const _cols = [
    'name', 'relationship', 'birthdate', 'age',
    'gender', 'civil_status', 'education', 'occupation', 'allowance',
  ];
  static const _headers = [
    'Name', 'Relationship', 'Birthdate', 'Age',
    'Sex', 'Civil Status', 'Education', 'Occupation', 'Allowance (₱)',
  ];

  // ── Look up options from the template by field_name ───────
  // For 'gender': the GIS template stores Sex options on the
  // 'sex' field (Section A). We fall back to 'sex' when 'gender'
  // is not a standalone field in the template.
  List<FieldOption> _optionsFor(String fieldName) {
    final lookupNames = fieldName == 'gender'
        ? ['gender', 'sex']   // prefer explicit 'gender', fall back to 'sex'
        : [fieldName];

    for (final name in lookupNames) {
      try {
        final field = widget.controller.template.allFields
            .firstWhere((f) => f.fieldName == name);
        if (field.options.isNotEmpty) return field.options;
      } catch (_) {}
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.controller.familyMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _FieldLabel(label: 'Family Composition'),
            if (!widget.isReadOnly)
              TextButton.icon(
                onPressed: () {
                  widget.controller.familyMembers = [
                    ...members,
                    {for (final c in _cols) c: ''}
                  ];
                  widget.controller.notifyListeners();
                  setState(() {});
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Member',
                    style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No family members added.',
                style: TextStyle(color: Colors.black45, fontSize: 12)),
          ),
        ...members.asMap().entries.map((entry) {
          final i = entry.key;
          final m = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFEEEEF5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ..._cols.asMap().entries.map((col) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(_headers[col.key],
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54)),
                          ),
                          Expanded(
                            child: widget.isReadOnly
                                ? Text(m[col.value]?.toString() ?? '—',
                                    style: const TextStyle(fontSize: 13))
                                : _buildEditCell(
                                    context, i, m, col.value),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (!widget.isReadOnly)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          widget.controller.familyMembers =
                              List.from(members)..removeAt(i);
                          widget.controller.recomputeFromFamilyChange();
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline,
                            size: 14, color: Colors.red),
                        label: const Text('Remove',
                            style: TextStyle(
                                fontSize: 11, color: Colors.red)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEditCell(BuildContext context, int i,
      Map<String, dynamic> m, String col) {
    switch (col) {

      // ── Birthdate → auto-calculates age ─────────────────
      case 'birthdate':
        final raw = m['birthdate']?.toString() ?? '';
        return GestureDetector(
          onTap: () async {
            DateTime? initial;
            try {
              initial = DateTime.parse(raw);
            } catch (_) {
              initial = DateTime(DateTime.now().year - 18);
            }
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.primaryBlue,
                    onPrimary: Colors.white,
                    onSurface: Colors.black87,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              final formatted = DatePickerHelper.formatDate(picked);
              final today = DateTime.now();
              int age = today.year - picked.year;
              if (today.month < picked.month ||
                  (today.month == picked.month &&
                      today.day < picked.day)) {
                age--;
              }
              widget.controller.familyMembers[i]['birthdate'] = formatted;
              widget.controller.familyMembers[i]['age'] = age.toString();
              widget.controller.fieldChecks['Family Composition'] = true;
              widget.controller.notifyListeners();
              setState(() {});
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDDDEE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppColors.primaryBlue),
                const SizedBox(width: 6),
                Text(
                  raw.isEmpty ? 'Select date' : raw,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        raw.isEmpty ? Colors.black38 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );

      // ── Age — key-bound so it rebuilds when birthdate sets it ─
      case 'age':
        return TextFormField(
          key: ValueKey('age_${i}_${m['age']}'),
          initialValue: m['age']?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: _inputDeco(hint: '0').copyWith(isDense: true),
          style: const TextStyle(fontSize: 12),
          onChanged: (v) {
            widget.controller.familyMembers[i]['age'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
          },
        );

      // ── Gender: radio chips — options from 'sex' field ───
      case 'gender':
        final opts = _optionsFor('gender'); // falls back to 'sex'
        final current = m['gender']?.toString() ?? '';
        if (opts.isEmpty) {
          return TextFormField(
            initialValue: current,
            decoration: _inputDeco().copyWith(isDense: true),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) {
              widget.controller.familyMembers[i]['gender'] = v;
              widget.controller.fieldChecks['Family Composition'] = true;
            },
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: opts.map((opt) {
            final isSelected = current == opt.value;
            return GestureDetector(
              onTap: () {
                widget.controller.familyMembers[i]['gender'] = opt.value;
                widget.controller.fieldChecks['Family Composition'] = true;
                widget.controller.notifyListeners();
                setState(() {});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryBlue
                      : const Color(0xFFF0F0F8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : const Color(0xFFDDDDEE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 13,
                      color: isSelected ? Colors.white : Colors.black45,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      // ── Civil Status: dropdown — options from 'civil_status' field ─
      case 'civil_status':
        return _inlineDropdown(
          opts: _optionsFor('civil_status'),
          current: m['civil_status']?.toString() ?? '',
          fallbackHint: 'Civil Status',
          onFallbackChange: (v) {
            widget.controller.familyMembers[i]['civil_status'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
          },
          onDropdownChange: (v) {
            widget.controller.familyMembers[i]['civil_status'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
            widget.controller.notifyListeners();
            setState(() {});
          },
        );

      // ── Education: dropdown — options from 'education' field ─
      case 'education':
        return _inlineDropdown(
          opts: _optionsFor('education'),
          current: m['education']?.toString() ?? '',
          fallbackHint: 'Education',
          onFallbackChange: (v) {
            widget.controller.familyMembers[i]['education'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
          },
          onDropdownChange: (v) {
            widget.controller.familyMembers[i]['education'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
            widget.controller.notifyListeners();
            setState(() {});
          },
        );

      // ── Allowance — triggers B recompute on every keystroke ─
      case 'allowance':
        return TextFormField(
          initialValue: m['allowance']?.toString() ?? '',
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDeco(hint: '0.00').copyWith(isDense: true),
          style: const TextStyle(fontSize: 12),
          onChanged: (v) {
            widget.controller.familyMembers[i]['allowance'] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
            // recomputeFromFamilyChange calls _recomputeFields (which
            // sums B) then notifyListeners so computed fields update.
            widget.controller.recomputeFromFamilyChange();
          },
        );

      // ── Default: plain text ──────────────────────────────
      default:
        return TextFormField(
          initialValue: m[col]?.toString() ?? '',
          decoration: _inputDeco().copyWith(isDense: true),
          style: const TextStyle(fontSize: 12),
          onChanged: (v) {
            widget.controller.familyMembers[i][col] = v;
            widget.controller.fieldChecks['Family Composition'] = true;
          },
        );
    }
  }

  // ── Inline dropdown with text fallback when no options ────
  Widget _inlineDropdown({
    required List<FieldOption> opts,
    required String current,
    required String fallbackHint,
    required void Function(String) onFallbackChange,
    required void Function(String) onDropdownChange,
  }) {
    if (opts.isEmpty) {
      return TextFormField(
        initialValue: current,
        decoration: _inputDeco(hint: fallbackHint).copyWith(isDense: true),
        style: const TextStyle(fontSize: 12),
        onChanged: onFallbackChange,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDDDEE)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: opts.any((o) => o.value == current) ? current : null,
          hint: const Text('Select...',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
          isExpanded: true,
          items: opts
              .map((o) => DropdownMenuItem(
                  value: o.value,
                  child:
                      Text(o.label, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) {
            if (v != null) onDropdownChange(v);
          },
        ),
      ),
    );
  }
}

// ── Supporting Family table ───────────────────────────────────
class _SupportingFamilyField extends StatefulWidget {
  final FormStateController controller;
  final bool isReadOnly;
  const _SupportingFamilyField(
      {required this.controller, required this.isReadOnly});

  @override
  State<_SupportingFamilyField> createState() =>
      _SupportingFamilyFieldState();
}

class _SupportingFamilyFieldState extends State<_SupportingFamilyField> {
  @override
  Widget build(BuildContext context) {
    final members = widget.controller.supportingFamily;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _FieldLabel(label: 'Supporting Family Members'),
            if (!widget.isReadOnly)
              TextButton.icon(
                onPressed: () {
                  widget.controller.supportingFamily = [
                    ...members,
                    {
                      'name': '',
                      'relationship': '',
                      'regular_sustento': ''
                    }
                  ];
                  widget.controller.notifyListeners();
                  setState(() {});
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        ...members.asMap().entries.map((entry) {
          final i = entry.key;
          final m = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFEEEEF5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: widget.isReadOnly
                        ? Text(
                            '${m['name']} (${m['relationship']}) — ₱${m['regular_sustento']}',
                            style: const TextStyle(fontSize: 13))
                        : Column(
                            children: [
                              TextFormField(
                                initialValue:
                                    m['name']?.toString() ?? '',
                                decoration: _inputDeco(hint: 'Name')
                                    .copyWith(isDense: true),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (v) => widget.controller
                                    .supportingFamily[i]['name'] = v,
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        m['relationship']?.toString() ??
                                            '',
                                    decoration:
                                        _inputDeco(hint: 'Relationship')
                                            .copyWith(isDense: true),
                                    style:
                                        const TextStyle(fontSize: 12),
                                    onChanged: (v) => widget.controller
                                        .supportingFamily[i]
                                        ['relationship'] = v,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: m['regular_sustento']
                                            ?.toString() ??
                                        '',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration:
                                        _inputDeco(hint: 'Monthly Amt')
                                            .copyWith(isDense: true),
                                    style:
                                        const TextStyle(fontSize: 12),
                                    onChanged: (v) => widget.controller
                                        .supportingFamily[i]
                                        ['regular_sustento'] = v,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                  ),
                  if (!widget.isReadOnly) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      onPressed: () {
                        widget.controller.supportingFamily =
                            List.from(members)..removeAt(i);
                        widget.controller.notifyListeners();
                        setState(() {});
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ── Signature field ───────────────────────────────────────────
// PERFORMANCE FIX: Completely isolated from parent rebuilds.
// Drawing happens in local state only. Controller is updated only on Save.
class _SignatureField extends StatefulWidget {
  final FormStateController controller;
  final bool isReadOnly;
  const _SignatureField(
      {required this.controller, required this.isReadOnly});

  @override
  State<_SignatureField> createState() => _SignatureFieldState();
}

class _SignatureFieldState extends State<_SignatureField> {
  final List<Offset?> _points = [];
  bool _showPad = false;

  @override
  void initState() {
    super.initState();
    final sig = widget.controller.signatureBase64;
    _showPad = (sig == null || sig.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    // Always read from controller for latest signature
    final savedSignature = widget.controller.signatureBase64;
    final hasSignature = savedSignature != null && savedSignature.isNotEmpty;
    
        debugPrint('Signature widget build: hasSignature=$hasSignature, _showPad=$_showPad, sigLength=${savedSignature?.length ?? 0}');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Signature'),
        if (widget.isReadOnly)
          _buildReadOnlyView(savedSignature)
        else if (hasSignature)
          _buildSavedView(savedSignature)
        else
          _buildSignaturePad(),
      ],
    );
  }

  Widget _buildSavedView(String signature) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDDDEE)),
          ),
          child: _renderSig(signature),
        ),
        TextButton(
          onPressed: () {
            _points.clear();
            widget.controller.signatureBase64 = null;
            widget.controller.signaturePoints = null;
            widget.controller.notifyListeners();
            setState(() {
              _showPad = true;
            });
          },
          child: const Text('Clear', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildReadOnlyView(String? signature) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDDDEE)),
      ),
      child: signature != null && signature.isNotEmpty
          ? _renderSig(signature)
          : const Center(
              child: Text('No signature',
                  style: TextStyle(color: Colors.black38))),
    );
  }

  Widget _renderSig(String sig) {
    try {
      final b64 = sig.contains(',') ? sig.split(',').last : sig;
      return Image.memory(base64Decode(b64), fit: BoxFit.contain);
    } catch (_) {
      return const Center(
          child: Text('Invalid signature',
              style: TextStyle(color: Colors.black38)));
    }
  }

  Widget _buildSignaturePad() {
    return Column(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDDDEE)),
          ),
          child: GestureDetector(
            onPanStart: (d) {
              _points.add(d.localPosition);
              setState(() {});
            },
            onPanUpdate: (d) {
              _points.add(d.localPosition);
              setState(() {});
            },
            onPanEnd: (_) async {
              _points.add(null);
              setState(() {});
              
              if (_points.whereType<Offset>().length >= 2) {
                final b64 = await _convertToBase64(_points);
                if (b64 != null) {
                  widget.controller.signatureBase64 = b64;
                  widget.controller.signaturePoints = List.from(_points);
                  widget.controller.fieldChecks['Signature'] = true;
                  widget.controller.notifyListeners();
                }
              }
            },
            child: CustomPaint(
              painter: _SignaturePainter(_points),
              child: Container(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _points.clear()),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
  }

  Future<String?> _convertToBase64(List<Offset?> points) async {
    final realPoints = points.whereType<Offset>().toList();
    if (realPoints.length < 2) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, 200),
      Paint()..color = Colors.white,
    );

    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, pen);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(300, 200);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

// ── Member Table (generic, column-driven) ─────────────────────
class _MemberTableWidget extends StatefulWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;
  const _MemberTableWidget({
    required this.field,
    required this.controller,
    required this.isReadOnly,
  });

  @override
  State<_MemberTableWidget> createState() => _MemberTableWidgetState();
}

class _MemberTableWidgetState extends State<_MemberTableWidget> {
  List<FormFieldModel> get _columns => widget.field.columns;

  @override
  Widget build(BuildContext context) {
    final rows = widget.controller.getMemberTableRows(widget.field.fieldName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: label + Add Row button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FieldLabel(
              label: widget.field.fieldLabel,
              isRequired: widget.field.isRequired,
            ),
            if (!widget.isReadOnly)
              TextButton.icon(
                onPressed: () {
                  widget.controller.addMemberTableRow(
                    widget.field.fieldName,
                    _columns,
                  );
                  setState(() {});
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Row', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),

        // Empty state
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No rows added.',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),

        // Rows as cards
        ...rows.asMap().entries.map((entry) {
          final rowIdx = entry.key;
          final rowData = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFEEEEF5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ..._columns.map((col) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              col.fieldLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          Expanded(
                            child: widget.isReadOnly
                                ? Text(
                                    rowData[col.fieldName]?.toString() ?? '',
                                    style: const TextStyle(fontSize: 13),
                                  )
                                : _buildCellEditor(col, rowData, rowIdx),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (!widget.isReadOnly)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          widget.controller.removeMemberTableRow(
                            widget.field.fieldName,
                            rowIdx,
                          );
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline,
                            size: 14, color: Colors.red),
                        label: const Text('Remove',
                            style: TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCellEditor(
      FormFieldModel col, Map<String, dynamic> rowData, int rowIdx) {
    final currentValue = rowData[col.fieldName]?.toString() ?? '';

    switch (col.fieldType) {
      case FormFieldType.text:
      case FormFieldType.number:
        return TextFormField(
          key: ValueKey('${widget.field.fieldName}_${rowIdx}_${col.fieldName}'),
          initialValue: currentValue,
          keyboardType: col.fieldType == FormFieldType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: _inputDeco(hint: col.placeholder ?? col.fieldLabel),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            widget.controller.updateMemberTableCell(
              widget.field.fieldName, rowIdx, col.fieldName, v,
            );
          },
        );

      case FormFieldType.date:
        return GestureDetector(
          onTap: () async {
            DateTime initial;
            try {
              initial = DateTime.parse(currentValue);
            } catch (_) {
              initial = DateTime.now();
            }
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              builder: DatePickerHelper.themedBuilder,
            );
            if (picked != null) {
              widget.controller.updateMemberTableCell(
                widget.field.fieldName, rowIdx, col.fieldName,
                DatePickerHelper.formatDate(picked),
              );
              setState(() {});
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDDDEE)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentValue.isEmpty ? 'Select date' : currentValue,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          currentValue.isEmpty ? Colors.black38 : Colors.black,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today,
                    size: 16, color: Colors.black38),
              ],
            ),
          ),
        );

      case FormFieldType.dropdown:
        return DropdownButtonFormField<String>(
          value: currentValue.isEmpty ? null : currentValue,
          items: col.options.map((opt) {
            return DropdownMenuItem(
              value: opt.value,
              child: Text(opt.label, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          decoration: _inputDeco(hint: 'Select...'),
          onChanged: (v) {
            widget.controller.updateMemberTableCell(
              widget.field.fieldName, rowIdx, col.fieldName, v ?? '',
            );
            setState(() {});
          },
        );

      default:
        return TextFormField(
          key: ValueKey('${widget.field.fieldName}_${rowIdx}_${col.fieldName}'),
          initialValue: currentValue,
          decoration: _inputDeco(hint: col.fieldLabel),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            widget.controller.updateMemberTableCell(
              widget.field.fieldName, rowIdx, col.fieldName, v,
            );
          },
        );
    }
  }
}