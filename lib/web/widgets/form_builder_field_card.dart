import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';

class FormBuilderFieldCard extends StatelessWidget {
  const FormBuilderFieldCard({
    super.key,
    required this.field,
    required this.sectionIndex,
    required this.fieldIndex,
    required this.isActive,
    required this.controller,
    required this.onTap,
  });

  final BuilderField field;
  final int sectionIndex;
  final int fieldIndex;
  final bool isActive;
  final FormBuilderScreenController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                        _buildFieldToolbar(field, sectionIndex, fieldIndex),
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

  Widget _buildFieldHeaderActive(BuilderField field) {
    final isSignatureField = field.type == FormFieldType.signature;
    final canLinkCanonicalKey =
        canonicalKeyEligibleTypes.contains(field.type) || isSignatureField;
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
                focusNode: controller.focusNode('fld_${field.id}'),
                controller: controller.ctrl('fld_${field.id}', field.label),
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
                onChanged: (value) {
                  field.label = value;
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
                            systemTypeIcons[field.type] ?? Icons.help_outline,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'System: ${systemTypeLabels[field.type] ?? field.type.toDbString()}',
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
                          items: typeLabels.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Row(
                                children: [
                                  Icon(
                                    typeIcons[entry.key],
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      entry.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            if (value == FormFieldType.signature) {
                              final hasOtherSignature = controller.sections
                                  .expand((section) => section.fields)
                                  .any(
                                    (otherField) =>
                                        otherField.type ==
                                            FormFieldType.signature &&
                                        otherField.id != field.id,
                                  );
                              if (hasOtherSignature) {
                                controller.showSnackBar?.call(
                                  'A "Signature" block already exists in this form.',
                                  Colors.orange.shade700,
                                );
                                return;
                              }
                            }
                            field.type = value;
                            if (value == FormFieldType.signature) {
                              field.canonicalFieldKey = 'signature';
                            }
                            if (value != FormFieldType.number) {
                              field.ageFromFieldId = null;
                            }
                            if (field.hasOptions && field.options.isEmpty) {
                              field.options.add(
                                BuilderOption(label: 'Option 1'),
                              );
                            }
                            controller.markChanged();
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
                      child: Text('None'),
                    ),
                  ...(isSignatureField
                          ? const [(key: 'signature', label: 'Signature')]
                          : controller.availableCanonicalKeys)
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
                  field.canonicalFieldKey = isSignatureField
                      ? 'signature'
                      : value;
                  controller.markChanged();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFieldHeaderInactive(BuilderField field) {
    return Row(
      children: [
        Icon(
          (field.type.isSystemType
                  ? systemTypeIcons[field.type]
                  : typeIcons[field.type]) ??
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
                    color: AppColors.highlight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.highlight.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '-> ${field.canonicalFieldKey}',
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

  Widget _buildFieldToolbar(
    BuilderField field,
    int sectionIndex,
    int fieldIndex,
  ) {
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
              onPressed: () =>
                  controller.duplicateField(sectionIndex, fieldIndex),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              tooltip: 'Delete',
              onPressed: () => controller.removeField(sectionIndex, fieldIndex),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.cardBorder),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: 'Move up',
              onPressed: fieldIndex > 0
                  ? () => controller.moveField(sectionIndex, fieldIndex, -1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              tooltip: 'Move down',
              onPressed:
                  fieldIndex <
                      controller.sections[sectionIndex].fields.length - 1
                  ? () => controller.moveField(sectionIndex, fieldIndex, 1)
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
              activeThumbColor: AppColors.highlight,
              onChanged: (value) {
                field.isRequired = value;
                controller.markChanged();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisibilityConditionRow(BuilderField field) {
    final triggerCandidates = controller.sections
        .expand((section) => section.fields)
        .where(
          (candidate) =>
              candidate.id != field.id &&
              (candidate.type == FormFieldType.boolean ||
                  candidate.type == FormFieldType.radio ||
                  candidate.type == FormFieldType.dropdown ||
                  candidate.type == FormFieldType.checkbox ||
                  candidate.type == FormFieldType.membershipGroup),
        )
        .toList();

    final hasCondition = field.condition.triggerFieldId.isNotEmpty;

    BuilderField? triggerField;
    for (final candidate in triggerCandidates) {
      if (candidate.id == field.condition.triggerFieldId) {
        triggerField = candidate;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasCondition
            ? Colors.orange.withValues(alpha: 0.06)
            : AppColors.pageBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasCondition
              ? Colors.orange.withValues(alpha: 0.4)
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
                'Show only if...',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const Spacer(),
              Switch(
                value: hasCondition,
                activeThumbColor: Colors.orange,
                onChanged: triggerCandidates.isEmpty
                    ? null
                    : (value) {
                        if (!value) {
                          field.condition.triggerFieldId = '';
                          field.condition.triggerValue = '';
                        } else {
                          field.condition.triggerFieldId =
                              triggerCandidates.first.id;
                          field.condition.triggerValue = '';
                          field.condition.action = 'show';
                        }
                        controller.markChanged();
                      },
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
                        items: triggerCandidates.map((candidate) {
                          return DropdownMenuItem<String>(
                            value: candidate.id,
                            child: Text(
                              candidate.label.isNotEmpty
                                  ? candidate.label
                                  : candidate.fieldName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          field.condition.triggerFieldId = value ?? '';
                          field.condition.triggerValue = '';
                          field.condition.action = 'show';
                          controller.markChanged();
                        },
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
                                  : triggerField.options.map((option) {
                                      return DropdownMenuItem<String>(
                                        value: slugify(option.label),
                                        child: Text(
                                          option.label,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      );
                                    }).toList(),
                              onChanged: (value) {
                                field.condition.triggerValue = value ?? '';
                                field.condition.action = 'show';
                              },
                            ),
                          ),
                        )
                      : TextField(
                          focusNode: controller.focusNode(
                            'cond_val_${field.id}',
                          ),
                          controller: controller.ctrl(
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
                          onChanged: (value) {
                            field.condition.triggerValue = value;
                            field.condition.action = 'show';
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              field.condition.triggerValue.isEmpty
                  ? 'Pick a value to complete the condition.'
                  : 'This field shows when "${triggerField?.label ?? '?'}" = "${field.condition.triggerValue}"',
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

  Widget _buildFieldContent(BuilderField field, bool isActive) {
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

  Widget _buildNumberEditor(BuilderField field, bool isActive) {
    if (!isActive) return _textPreview('Number');

    final dateCandidates = controller.sections
        .expand((section) => section.fields)
        .where(
          (candidate) =>
              candidate.id != field.id && candidate.type == FormFieldType.date,
        )
        .toList();
    final hasLink =
        field.ageFromFieldId != null && field.ageFromFieldId!.isNotEmpty;
    final selectedValid =
        hasLink &&
        dateCandidates.any((candidate) => candidate.id == field.ageFromFieldId);
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
                activeThumbColor: AppColors.highlight,
                onChanged: (value) {
                  if (!value) {
                    field.ageFromFieldId = null;
                  } else {
                    field.ageFromFieldId = dateCandidates.isNotEmpty
                        ? dateCandidates.first.id
                        : null;
                  }
                  controller.markChanged();
                },
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
                        (candidate) => DropdownMenuItem<String>(
                          value: candidate.id,
                          child: Text(
                            candidate.label.isNotEmpty
                                ? candidate.label
                                : candidate.fieldName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: dateCandidates.isEmpty
                      ? null
                      : (value) {
                          field.ageFromFieldId = value;
                          controller.markChanged();
                        },
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
    BuilderField tableField,
    BuilderColumn column,
  ) {
    final dateColumns = tableField.columns
        .where(
          (candidate) =>
              candidate.id != column.id && candidate.type == FormFieldType.date,
        )
        .toList();
    final hasLink =
        column.ageFromColumnId != null && column.ageFromColumnId!.isNotEmpty;
    final selectedValid =
        hasLink &&
        dateColumns.any((candidate) => candidate.id == column.ageFromColumnId);
    final selectedValue = selectedValid ? column.ageFromColumnId : null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.highlight.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.highlight.withValues(alpha: 0.2)),
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
                activeThumbColor: AppColors.highlight,
                onChanged: (value) {
                  if (!value) {
                    column.ageFromColumnId = null;
                  } else {
                    column.ageFromColumnId = dateColumns.isNotEmpty
                        ? dateColumns.first.id
                        : null;
                  }
                  controller.markChanged();
                },
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
                        (candidate) => DropdownMenuItem<String>(
                          value: candidate.id,
                          child: Text(
                            candidate.label.isNotEmpty
                                ? candidate.label
                                : candidate.fieldName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: dateColumns.isEmpty
                      ? null
                      : (value) {
                          column.ageFromColumnId = value;
                          controller.markChanged();
                        },
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

  Widget _buildLinearScaleEditor(BuilderField field, bool isActive) {
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
          items: [0, 1]
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value')),
              )
              .toList(),
          onChanged: (value) {
            field.scaleMin = value!;
            controller.markChanged();
          },
        ),
        const SizedBox(width: 24),
        const Text(
          'To:',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMax,
          items: List.generate(9, (index) => index + 2)
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value')),
              )
              .toList(),
          onChanged: (value) {
            field.scaleMax = value!;
            controller.markChanged();
          },
        ),
      ],
    );
  }

  Widget _buildColumnEditor(BuilderField field, bool isActive) {
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
            children: field.columns.map((column) {
              return Chip(
                label: Text(
                  '${column.label} (${columnTypes[column.type] ?? column.type.toDbString()})',
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
          final columnIndex = entry.key;
          final column = entry.value;
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
                          onPressed: columnIndex > 0
                              ? () => controller.moveColumn(field, columnIndex, -1)
                              : null,
                          tooltip: 'Move up',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: columnIndex < field.columns.length - 1
                              ? () => controller.moveColumn(field, columnIndex, 1)
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
                        focusNode: controller.focusNode('col_${column.id}'),
                        controller: controller.ctrl(
                          'col_${column.id}',
                          column.label,
                        ),
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
                        onChanged: (value) {
                          column.label = value;
                          column.fieldName = slugify(value);
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
                            value: column.type,
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark,
                            ),
                            items: columnTypes.entries.map((entry) {
                              return DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              column.type = value;
                              if (value != FormFieldType.number) {
                                column.ageFromColumnId = null;
                              }
                              if (value == FormFieldType.dropdown &&
                                  column.options.isEmpty) {
                                column.options.add(
                                  BuilderOption(label: 'Option 1'),
                                );
                              }
                              controller.markChanged();
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
                      onPressed: () {
                        field.columns.removeAt(columnIndex);
                        controller.markChanged();
                      },
                    ),
                  ],
                ),
                if (column.type == FormFieldType.number) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: _buildColumnAutoComputeEditor(field, column),
                  ),
                ],
              ],
            ),
          );
        }),
        ...field.columns
            .where((column) => column.type == FormFieldType.dropdown)
            .map(
              (column) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Options for "${column.label}":',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    ...column.options.asMap().entries.map((optionEntry) {
                      final option = optionEntry.value;
                      return Row(
                        children: [
                          const Icon(
                            Icons.arrow_right,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: TextField(
                              focusNode: controller.focusNode(
                                'colopt_${option.id}',
                              ),
                              controller: controller.ctrl(
                                'colopt_${option.id}',
                                option.label,
                              ),
                              scrollPadding: EdgeInsets.zero,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Option',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              onChanged: (value) {
                                option.label = value;
                              },
                            ),
                          ),
                          if (column.options.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () {
                                column.options.removeAt(optionEntry.key);
                                controller.markChanged();
                              },
                            ),
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () {
                        column.options.add(
                          BuilderOption(
                            label: 'Option ${column.options.length + 1}',
                          ),
                        );
                        controller.markChanged();
                      },
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
          onPressed: () {
            field.columns.add(
              BuilderColumn(
                label: 'Column ${field.columns.length + 1}',
                order: field.columns.length,
              ),
            );
            controller.markChanged();
          },
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSystemTableColumnEditor(BuilderField field, bool isActive) {
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
            children: field.columns.map((column) {
              return Chip(
                label: Text(
                  '${column.label} (${columnTypes[column.type] ?? column.type.toDbString()})',
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
          'Edit, rename, or remove any column. Pre-populated columns map to the database when present.',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        ...field.columns.asMap().entries.map((entry) {
          final columnIndex = entry.key;
          final column = entry.value;
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
                          onPressed: columnIndex > 0
                              ? () => controller.moveColumn(field, columnIndex, -1)
                              : null,
                          tooltip: 'Move up',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: columnIndex < field.columns.length - 1
                              ? () => controller.moveColumn(field, columnIndex, 1)
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
                        focusNode: controller.focusNode('col_${column.id}'),
                        controller: controller.ctrl(
                          'col_${column.id}',
                          column.label,
                        ),
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
                        onChanged: (value) {
                          column.label = value;
                          if (column.dbMapKey == null) {
                            column.fieldName = slugify(value);
                          }
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
                            value: column.type,
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark,
                            ),
                            items: columnTypes.entries.map((entry) {
                              return DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              column.type = value;
                              if (value != FormFieldType.number) {
                                column.ageFromColumnId = null;
                              }
                              if (value == FormFieldType.dropdown &&
                                  column.options.isEmpty) {
                                column.options.add(
                                  BuilderOption(label: 'Option 1'),
                                );
                              }
                              controller.markChanged();
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
                      onPressed: () {
                        field.columns.removeAt(columnIndex);
                        controller.markChanged();
                      },
                    ),
                  ],
                ),
                if (column.type == FormFieldType.number) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: _buildColumnAutoComputeEditor(field, column),
                  ),
                ],
              ],
            ),
          );
        }),
        ...field.columns
            .where((column) => column.type == FormFieldType.dropdown)
            .map(
              (column) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Options for "${column.label}":',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    ...column.options.asMap().entries.map((optionEntry) {
                      final option = optionEntry.value;
                      return Row(
                        children: [
                          const Icon(
                            Icons.arrow_right,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: TextField(
                              focusNode: controller.focusNode(
                                'colopt_${option.id}',
                              ),
                              controller: controller.ctrl(
                                'colopt_${option.id}',
                                option.label,
                              ),
                              scrollPadding: EdgeInsets.zero,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Option',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              onChanged: (value) {
                                option.label = value;
                              },
                            ),
                          ),
                          if (column.options.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () {
                                column.options.removeAt(optionEntry.key);
                                controller.markChanged();
                              },
                            ),
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () {
                        column.options.add(
                          BuilderOption(
                            label: 'Option ${column.options.length + 1}',
                          ),
                        );
                        controller.markChanged();
                      },
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
          onPressed: () {
            field.columns.add(
              BuilderColumn(
                label: 'Column ${field.columns.length + 1}',
                order: field.columns.length,
              ),
            );
            controller.markChanged();
          },
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Add Column', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildOptionsEditor(BuilderField field, bool isActive) {
    final isRadio = field.type == FormFieldType.radio;
    final isCheckbox = field.type == FormFieldType.checkbox;
    final optionIcon = isRadio
        ? Icons.radio_button_unchecked
        : isCheckbox
        ? Icons.check_box_outline_blank
        : Icons.arrow_right;

    return Column(
      children: [
        ...List.generate(field.options.length, (optionIndex) {
          final option = field.options[optionIndex];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(optionIcon, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                if (isActive)
                  Expanded(
                    child: TextField(
                      focusNode: controller.focusNode('opt_${option.id}'),
                      controller: controller.ctrl(
                        'opt_${option.id}',
                        option.label,
                      ),
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
                      onChanged: (value) {
                        option.label = value;
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      option.label,
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
                    onPressed: () {
                      field.options.removeAt(optionIndex);
                      controller.markChanged();
                    },
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
                  optionIcon,
                  size: 20,
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    field.options.add(
                      BuilderOption(
                        label: 'Option ${field.options.length + 1}',
                        order: field.options.length,
                      ),
                    );
                    controller.markChanged();
                  },
                  child: const Text('Add option'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFormulaEditor(BuilderField field, bool isActive) {
    final tokens = controller.formulaTokens(field);
    final numericFields = controller.sections
        .expand((section) => section.fields)
        .where(
          (candidate) =>
              candidate.id != field.id &&
              (candidate.type == FormFieldType.number ||
                  candidate.type == FormFieldType.computed),
        )
        .toList();
    final fieldLabelMap = {
      for (final candidate in controller.sections
          .expand((section) => section.fields)
          .where((candidate) => candidate.id != field.id))
        candidate.fieldName: (candidate.label.isNotEmpty
            ? candidate.label
            : candidate.fieldName),
    };

    if (!isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.buttonOutlineBlue.withValues(alpha: 0.3),
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
                    : tokens
                          .map((token) => fieldLabelMap[token] ?? token)
                          .join(' '),
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
          'Tap field names and operators below to build the formula. Tap x on a token to remove it.',
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
              color: AppColors.buttonOutlineBlue.withValues(alpha: 0.4),
            ),
          ),
          child: tokens.isEmpty
              ? const Text(
                  'Empty - add fields and operators below',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tokens.asMap().entries.map((entry) {
                    final tokenIndex = entry.key;
                    final token = entry.value;
                    final isOperator = const {
                      '+', '-', '*', '/', '(', ')',
                    }.contains(token);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOperator
                            ? const Color(0xFFE8EEFF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isOperator
                              ? AppColors.primaryBlue.withValues(alpha: 0.3)
                              : AppColors.buttonOutlineBlue,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isOperator
                                ? token
                                : (fieldLabelMap[token] ?? token),
                            style: TextStyle(
                              fontSize: isOperator ? 14 : 12,
                              fontFamily: 'monospace',
                              fontWeight: isOperator
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => controller.removeFormulaToken(
                              field,
                              tokenIndex,
                            ),
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
            children: numericFields.map((candidate) {
              return ElevatedButton.icon(
                onPressed: () =>
                    controller.appendFormulaToken(field, candidate.fieldName),
                icon: const Icon(Icons.add, size: 14),
                label: Text(
                  candidate.label.isNotEmpty
                      ? candidate.label
                      : candidate.fieldName,
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
          onPressed: () => controller.onShowSumColumnPicker?.call(field),
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
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
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
          children: ['+', '-', '*', '/', '(', ')'].map((operator) {
            return ElevatedButton(
              onPressed: () => controller.appendFormulaToken(field, operator),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8EEFF),
                foregroundColor: AppColors.primaryBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size(36, 32),
              ),
              child: Text(
                operator,
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

  Widget _buildConditionEditor(BuilderField field, bool isActive) {
    final allFields = controller.sections
        .expand((section) => section.fields)
        .where((candidate) => candidate.id != field.id)
        .toList();

    BuilderField? triggerField;
    for (final candidate in allFields) {
      if (candidate.id == field.condition.triggerFieldId) {
        triggerField = candidate;
        break;
      }
    }

    if (!isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                    (candidate) => DropdownMenuItem<String>(
                      value: candidate.id,
                      child: Text(
                        candidate.label.isNotEmpty
                            ? candidate.label
                            : candidate.fieldName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                field.condition.triggerFieldId = value;
                field.condition.action = 'show';
                controller.markChanged();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          focusNode: controller.focusNode('cond_val_${field.id}'),
          controller: controller.ctrl(
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
          onChanged: (value) {
            field.condition.triggerValue = value;
            field.condition.action = 'show';
          },
        ),
      ],
    );
  }
}