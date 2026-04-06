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
  final bool showCheckboxes;
  // Set of field names that should be highlighted red (missing required)
  final Set<String> highlightedFields;

  const DynamicFormRenderer({
    super.key,
    required this.template,
    required this.controller,
    this.mode = 'web',
    this.isReadOnly = false,
    this.showCheckboxes = false,
    this.highlightedFields = const {},
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
    if (widget.template.templateId != oldWidget.template.templateId) {
      _currentSection = 0;
    }
    if (_currentSection >= _sections.length && _sections.isNotEmpty) {
      _currentSection = _sections.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        if (widget.mode == 'mobile') {
          return _buildMobileLayout();
        } else {
          return _buildWebLayout();
        }
      },
    );
  }

  Widget _buildMobileLayout() {
    if (_sections.isEmpty) return const SizedBox();
    if (_currentSection >= _sections.length) {
      _currentSection = _sections.length - 1;
    }
    final section = _sections[_currentSection];

    return Column(
      children: [
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
                    onPressed: _currentSection > 0 ? () => setState(() => _currentSection--) : null,
                  ),
                ),
                Text(
                  'Page ${_currentSection + 1} of ${_sections.length}',
                  style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Opacity(
                  opacity: _currentSection < _sections.length - 1 ? 1.0 : 0.0,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 20),
                    color: AppColors.primaryBlue,
                    onPressed: _currentSection < _sections.length - 1 ? () => setState(() => _currentSection++) : null,
                  ),
                ),
              ],
            ),
          ),
        _buildSectionCard(section),
      ],
    );
  }

  Widget _buildWebLayout() {
    return Column(
      children: _sections
          .map((s) => Padding(padding: const EdgeInsets.only(bottom: 16), child: _buildSectionCard(s)))
          .toList(),
    );
  }

  Widget _buildSectionCard(FormSection section) {
    // Check if any field in this section is highlighted (missing required)
    final sectionHasError = section.fields.any(
      (f) => widget.highlightedFields.contains(f.fieldName),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: sectionHasError
            ? Border.all(color: Colors.red.withOpacity(0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: sectionHasError
                ? Colors.red.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: section.sectionName,
            showCheckbox: widget.showCheckboxes,
            isChecked: _isSectionChecked(section),
            onChecked: (v) => _checkSection(section, v ?? false),
            hasError: sectionHasError,
          ),
          const SizedBox(height: 16),
          ...section.fields
              .where((f) => _ctrl.isFieldVisible(f))
              .map((f) {
                final isHighlighted = widget.highlightedFields.contains(f.fieldName);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: isHighlighted
                      ? _buildHighlightedField(f)
                      : DynamicFieldWidget(
                          field: f,
                          controller: _ctrl,
                          isReadOnly: widget.isReadOnly,
                          showCheckbox: widget.showCheckboxes,
                        ),
                );
              }),
        ],
      ),
    );
  }

  /// Wraps a field in a red-bordered container to visually flag it as missing
  Widget _buildHighlightedField(FormFieldModel field) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.5), width: 1.5),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Red asterisk label above the field
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  'Required — ${field.fieldLabel}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          DynamicFieldWidget(
            field: field,
            controller: _ctrl,
            isReadOnly: widget.isReadOnly,
            showCheckbox: widget.showCheckboxes,
          ),
        ],
      ),
    );
  }

  bool _isSectionChecked(FormSection section) {
    if (_ctrl.selectAll) return true;
    final checkableFields = section.fields.where(
      (f) => f.fieldType != FormFieldType.computed && f.fieldType != FormFieldType.supportingFamilyTable,
    );
    if (checkableFields.isEmpty) return false;
    return checkableFields.every((f) => _ctrl.fieldChecks[f.checkKey] == true);
  }

  void _checkSection(FormSection section, bool v) {
    for (final f in section.fields) {
      _ctrl.fieldChecks[f.checkKey] = v;
    }
    _ctrl.notifyFormChanged();
  }
}

// ── Section header with optional checkbox ─────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool showCheckbox;
  final bool isChecked;
  final ValueChanged<bool?>? onChecked;
  final bool hasError;

  const _SectionHeader({
    required this.title,
    this.showCheckbox = false,
    this.isChecked = false,
    this.onChecked,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showCheckbox)
          Checkbox(value: isChecked, onChanged: onChecked, activeColor: AppColors.primaryBlue),
        if (hasError) ...[
          const Icon(Icons.warning_rounded, size: 16, color: Colors.red),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: hasError ? Colors.red.shade700 : AppColors.primaryBlue,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}