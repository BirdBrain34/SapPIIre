// Renders any FormTemplate dynamically.
// mobile: paginated sections | web: single scrollable column

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/dynamic_form/dynamic_field_widgets.dart';


class DynamicFormRenderer extends StatefulWidget {
  final FormTemplate template;
  final FormStateController controller;
  final String mode; // 'mobile' | 'web'
  final bool isReadOnly;
  final bool showCheckboxes; // mobile: show field-select checkboxes

  const DynamicFormRenderer({
    super.key,
    required this.template,
    required this.controller,
    this.mode = 'web',
    this.isReadOnly = false,
    this.showCheckboxes = false,
  });

  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  int _currentSection = 0;

  FormStateController get _ctrl => widget.controller;
  List<FormSection> get _sections => widget.template.sections;

  @override
  void didUpdateWidget(covariant DynamicFormRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset page when switching templates to avoid RangeError
    if (widget.template.templateId != oldWidget.template.templateId) {
      _currentSection = 0;
    }
    // Clamp if sections shrunk
    if (_currentSection >= _sections.length && _sections.isNotEmpty) {
      _currentSection = _sections.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        if (widget.mode == 'mobile') {
          return _buildMobileLayout();
        } else {
          return _buildWebLayout();
        }
      },
    );
  }

  // ── MOBILE: one section at a time ─────────────────────
  Widget _buildMobileLayout() {
    if (_sections.isEmpty) return const SizedBox();
    // Clamp index to valid range
    if (_currentSection >= _sections.length) {
      _currentSection = _sections.length - 1;
    }
    final section = _sections[_currentSection];

    return Column(
      children: [
        // ── Pagination header ─────────────────────────────
        if (_sections.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: _currentSection > 0 ? 1.0 : 0.0,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    color: AppColors.primaryBlue,
                    onPressed: _currentSection > 0
                        ? () => setState(() => _currentSection--)
                        : null,
                  ),
                ),
                Text(
                  'Page ${_currentSection + 1} of ${_sections.length}',
                  style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                Opacity(
                  opacity: _currentSection < _sections.length - 1 ? 1.0 : 0.0,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 20),
                    color: AppColors.primaryBlue,
                    onPressed: _currentSection < _sections.length - 1
                        ? () => setState(() => _currentSection++)
                        : null,
                  ),
                ),
              ],
            ),
          ),

        // ── Section card ──────────────────────────────────
        _buildSectionCard(section),
      ],
    );
  }

  // ── WEB: single scroll with all sections ─────────────────
  Widget _buildWebLayout() {
    return Column(
      children: _sections
          .map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildSectionCard(s),
              ))
          .toList(),
    );
  }

  // ── Section card wrapper ──────────────────────────────────
  Widget _buildSectionCard(FormSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with optional select-all checkbox
          _SectionHeader(
            title: section.sectionName,
            showCheckbox: widget.showCheckboxes,
            isChecked: _isSectionChecked(section),
            onChecked: (v) => _checkSection(section, v ?? false),
          ),
          const SizedBox(height: 16),

          // Fields
          ...section.fields
              .where((f) => _ctrl.isFieldVisible(f))
              .map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DynamicFieldWidget(
                      field: f,
                      controller: _ctrl,
                      isReadOnly: widget.isReadOnly,
                      showCheckbox: widget.showCheckboxes,
                    ),
                  )),
        ],
      ),
    );
  }

  bool _isSectionChecked(FormSection section) {
    if (_ctrl.selectAll) return true;
    final checkableFields = section.fields.where(
        (f) => f.fieldType != FormFieldType.computed &&
               f.fieldType != FormFieldType.supportingFamilyTable);
    if (checkableFields.isEmpty) return false;
    return checkableFields.every(
        (f) => _ctrl.fieldChecks[_checkKeyFor(f)] == true);
  }

  void _checkSection(FormSection section, bool v) {
    for (final f in section.fields) {
      _ctrl.fieldChecks[_checkKeyFor(f)] = v;
    }
    _ctrl.notifyListeners();
  }

  String _checkKeyFor(FormFieldModel field) {
    if (field.fieldType == FormFieldType.familyTable) return 'Family Composition';
    if (field.fieldType == FormFieldType.signature) return 'Signature';
    if (field.fieldType == FormFieldType.membershipGroup) return 'Membership Group';
    return field.fieldName;
  }
}

// ── Section header with optional checkbox ────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool showCheckbox;
  final bool isChecked;
  final ValueChanged<bool?>? onChecked;

  const _SectionHeader({
    required this.title,
    this.showCheckbox = false,
    this.isChecked = false,
    this.onChecked,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showCheckbox)
          Checkbox(
            value: isChecked,
            onChanged: onChecked,
            activeColor: AppColors.primaryBlue,
          ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
