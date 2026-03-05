// lib/widgets/dynamic_form/dynamic_field_widgets.dart
// One widget per FormFieldType — the renderer dispatches here.

import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';

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
    final checkKey = _checkKeyFor(field);

    Widget fieldWidget;
    switch (field.fieldType) {
      case FormFieldType.text:
        fieldWidget = _TextField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.date:
        fieldWidget = _DateField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.number:
        fieldWidget = _NumberField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.computed:
        fieldWidget = _ComputedField(field: field, controller: controller);
        break;
      case FormFieldType.dropdown:
        fieldWidget = _DropdownField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.radio:
        fieldWidget = _RadioField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.boolean:
        fieldWidget = _BooleanField(field: field, controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.membershipGroup:
        fieldWidget = _MembershipGroupField(controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.familyTable:
        fieldWidget = _FamilyTableField(controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.supportingFamilyTable:
        fieldWidget = _SupportingFamilyField(controller: controller, isReadOnly: isReadOnly);
        break;
      case FormFieldType.signature:
        fieldWidget = _SignatureField(controller: controller, isReadOnly: isReadOnly);
        break;
      default:
        return const SizedBox();
    }

    if (!showCheckbox) return fieldWidget;

    // Mobile: wrap with leading checkbox
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
        ),
        Expanded(child: fieldWidget),
      ],
    );
  }

  String _checkKeyFor(FormFieldModel f) {
    if (f.fieldType == FormFieldType.familyTable) return 'Family Composition';
    if (f.fieldType == FormFieldType.signature) return 'Signature';
    if (f.fieldType == FormFieldType.membershipGroup) return 'Membership Group';
    return f.fieldName;
  }
}

// ── Shared label widget ───────────────────────────────────────
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
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared input decoration ───────────────────────────────────
InputDecoration _inputDeco({String? hint, bool readOnly = false, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF5F5F8) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      suffixIcon: suffix,
    );

// ── Text field ────────────────────────────────────────────────
class _TextField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;

  const _TextField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller.textControllers[field.fieldName] ??
        TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        TextFormField(
          controller: ctrl,
          readOnly: isReadOnly,
          decoration: _inputDeco(hint: field.placeholder, readOnly: isReadOnly),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            controller.setValue(field.fieldName, v);
          },
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

  const _NumberField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller.textControllers[field.fieldName] ??
        TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        TextFormField(
          controller: ctrl,
          readOnly: isReadOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

  const _DateField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller.textControllers[field.fieldName] ??
        TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        TextFormField(
          controller: ctrl,
          readOnly: true,
          decoration: _inputDeco(
            hint: 'MM-DD-YYYY',
            readOnly: isReadOnly,
            suffix: isReadOnly ? null : const Icon(Icons.calendar_today, size: 18),
          ),
          style: const TextStyle(fontSize: 13),
          onTap: isReadOnly
              ? null
              : () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                            primary: AppColors.primaryBlue),
                      ),
                      child: child!,
                    ),
                  );
                  if (date != null) {
                    final formatted =
                        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}';
                    ctrl.text = formatted;
                    controller.setValue(field.fieldName, formatted);
                    // Auto-fill age if this is DOB
                    if (field.fieldName == 'date_of_birth') {
                      final age = DateTime.now().year - date.year;
                      final ageCtrl = controller.textControllers['age'];
                      if (ageCtrl != null) {
                        ageCtrl.text = age.toString();
                        controller.setValue('age', age.toString(), notify: false);
                      }
                    }
                    controller.notifyListeners();
                  }
                },
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

  const _DropdownField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final current = controller.getValue(field.fieldName)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        IgnorePointer(
          ignoring: isReadOnly,
          child: Container(
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
                    style: const TextStyle(fontSize: 13, color: Colors.black38)),
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

  const _RadioField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final current = controller.getValue(field.fieldName)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: field.fieldLabel, isRequired: field.isRequired),
        Wrap(
          spacing: 8,
          children: field.options.map((o) {
            final selected = current == o.value;
            return GestureDetector(
              onTap: isReadOnly
                  ? null
                  : () {
                      controller.setValue(field.fieldName, o.value);
                      if (field.fieldName == 'housing_status') {
                        controller.housingStatus = o.value;
                        controller.notifyListeners();
                      }
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

// ── Boolean (single toggle) field ────────────────────────────
class _BooleanField extends StatelessWidget {
  final FormFieldModel field;
  final FormStateController controller;
  final bool isReadOnly;

  const _BooleanField({required this.field, required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    bool current = false;
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
          child: Text(field.fieldLabel,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// ── Membership group (Solo Parent / PWD / 4Ps / PHIC) ────────
class _MembershipGroupField extends StatelessWidget {
  final FormStateController controller;
  final bool isReadOnly;

  const _MembershipGroupField(
      {required this.controller, required this.isReadOnly});

  @override
  Widget build(BuildContext context) {
    final items = [
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
            final selected =
                controller.membershipData[item.$1] ?? false;
            return GestureDetector(
              onTap: isReadOnly
                  ? null
                  : () {
                      controller.membershipData[item.$1] = !selected;
                      controller.notifyListeners();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                        color:
                            selected ? Colors.white : Colors.black87,
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
    'Sex', 'Civil Status', 'Education', 'Occupation', 'Allowance',
  ];

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
            margin: const EdgeInsets.only(bottom: 8),
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
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(_headers[col.key],
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black54)),
                          ),
                          Expanded(
                            child: widget.isReadOnly
                                ? Text(
                                    m[col.value]?.toString() ?? '—',
                                    style: const TextStyle(fontSize: 13),
                                  )
                                : TextFormField(
                                    initialValue:
                                        m[col.value]?.toString() ?? '',
                                    decoration:
                                        _inputDeco().copyWith(isDense: true),
                                    style: const TextStyle(fontSize: 12),
                                    onChanged: (v) {
                                      widget.controller.familyMembers[i]
                                          [col.value] = v;
                                      widget.controller.fieldChecks[
                                          'Family Composition'] = true;
                                    },
                                  ),
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
                          widget.controller.notifyListeners();
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline,
                            size: 14, color: Colors.red),
                        label: const Text('Remove',
                            style:
                                TextStyle(fontSize: 11, color: Colors.red)),
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
                    {'name': '', 'relationship': '', 'regular_sustento': ''}
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
                                initialValue: m['name']?.toString() ?? '',
                                decoration: _inputDeco(hint: 'Name')
                                    .copyWith(isDense: true),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (v) =>
                                    widget.controller.supportingFamily[i]
                                        ['name'] = v,
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        m['relationship']?.toString() ?? '',
                                    decoration:
                                        _inputDeco(hint: 'Relationship')
                                            .copyWith(isDense: true),
                                    style: const TextStyle(fontSize: 12),
                                    onChanged: (v) =>
                                        widget.controller
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
                                    decoration:
                                        _inputDeco(hint: '₱ Sustento')
                                            .copyWith(isDense: true),
                                    keyboardType:
                                        TextInputType.number,
                                    style: const TextStyle(fontSize: 12),
                                    onChanged: (v) =>
                                        widget.controller
                                            .supportingFamily[i]
                                            ['regular_sustento'] = v,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                  ),
                  if (!widget.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: Colors.red),
                      onPressed: () {
                        widget.controller.supportingFamily =
                            List.from(members)..removeAt(i);
                        widget.controller.notifyListeners();
                        setState(() {});
                      },
                    ),
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
  final _repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final hasSignature = widget.controller.signatureBase64 != null &&
        widget.controller.signatureBase64!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Signature'),
        const SizedBox(height: 8),

        // Preview or placeholder
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDDDEE)),
          ),
          child: hasSignature
              ? Image.memory(
                  base64Decode(widget.controller.signatureBase64!
                      .replaceFirst('data:image/png;base64,', '')),
                  fit: BoxFit.contain,
                )
              : const Center(
                  child: Text('No signature yet',
                      style: TextStyle(
                          color: Colors.black38, fontSize: 12))),
        ),

        if (!widget.isReadOnly) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _showPad = true),
                icon: const Icon(Icons.draw, size: 14),
                label: const Text('Sign', style: TextStyle(fontSize: 12)),
              ),
              if (hasSignature) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    widget.controller.signatureBase64 = null;
                    widget.controller.signaturePoints = null;
                    widget.controller.notifyListeners();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear, size: 14, color: Colors.red),
                  label: const Text('Clear',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ],
            ],
          ),
        ],

        // Inline signature pad
        if (_showPad && !widget.isReadOnly)
          _buildSignaturePad(),
      ],
    );
  }

  Widget _buildSignaturePad() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primaryBlue, width: 1.5),
          ),
          child: GestureDetector(
            onPanStart: (d) {
              _points.add(d.localPosition);
              (_repaintKey.currentContext?.findRenderObject() as RenderBox?)?.markNeedsPaint();
            },
            onPanUpdate: (d) {
              _points.add(d.localPosition);
              (_repaintKey.currentContext?.findRenderObject() as RenderBox?)?.markNeedsPaint();
            },
            onPanEnd: (d) {
              _points.add(null);
              (_repaintKey.currentContext?.findRenderObject() as RenderBox?)?.markNeedsPaint();
            },
            child: RepaintBoundary(
              key: _repaintKey,
              child: CustomPaint(
                painter: _SignaturePainter(_points),
                child: Container(),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                _points.clear();
                setState(() {});
              },
              child: const Text('Clear',
                  style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () async {
                final b64 = await _convertToBase64(_points);
                if (b64 != null) {
                  widget.controller.signatureBase64 = b64;
                  widget.controller.signaturePoints = List.from(_points);
                  widget.controller.fieldChecks['Signature'] = true;
                  widget.controller.notifyListeners();
                }
                setState(() => _showPad = false);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue),
              child: const Text('Save',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _convertToBase64(List<Offset?> points) async {
    if (points.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 200), bgPaint);
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
  bool shouldRepaint(_SignaturePainter old) => old.points != points;
}
