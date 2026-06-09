import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_config_service.dart';

/// Dialog for configuring dashboard widgets for a specific form template.
/// Allows users to select fields, set chart types, and reorder widgets.
class DashboardConfigDialog extends StatefulWidget {
  final String templateId;
  final FormTemplate template;
  final List<DashboardWidgetConfig> initialConfigs;
  final String staffId;
  final VoidCallback? onSave;

  const DashboardConfigDialog({
    super.key,
    required this.templateId,
    required this.template,
    required this.initialConfigs,
    required this.staffId,
    this.onSave,
  });

  @override
  State<DashboardConfigDialog> createState() => _DashboardConfigDialogState();
}

class _DashboardConfigDialogState extends State<DashboardConfigDialog> {
  late List<DashboardWidgetConfig> _selectedWidgets;
  late List<FormFieldModel> _availableFields;
  bool _isSaving = false;

  static const _skipTypes = {
    FormFieldType.signature,
    FormFieldType.familyTable,
    FormFieldType.membershipGroup,
    FormFieldType.supportingFamilyTable,
    FormFieldType.computed,
    FormFieldType.paragraph,
    FormFieldType.memberTable,
    FormFieldType.conditional,
    FormFieldType.unknown,
  };

  static const _chartTypeOptions = [
    'bar',
    'hbar',
    'pie',
    'donut',
    'line',
    'area',
    'stacked',
    'counter',
    'table',
    'funnel',
  ];

  @override
  void initState() {
    super.initState();
    _selectedWidgets = List.from(widget.initialConfigs);

    // Filter available fields: top-level, not skipped
    _availableFields = widget.template.allFields
        .where((field) => field.parentFieldId == null)
        .where((field) => !_skipTypes.contains(field.fieldType))
        .toList()
      ..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder));
  }

  String _defaultChartTypeFor(FormFieldType type) {
    switch (type) {
      case FormFieldType.boolean:
      case FormFieldType.dropdown:
      case FormFieldType.radio:
        return 'pie';
      case FormFieldType.checkbox:
        return 'hbar';
      case FormFieldType.number:
        return 'counter';
      case FormFieldType.date:
        return 'line';
      case FormFieldType.text:
        return 'hbar';
      default:
        return 'bar';
    }
  }

  bool _isFieldSelected(String fieldName) {
    return _selectedWidgets
        .any((config) => config.fieldName == fieldName);
  }

  void _toggleField(FormFieldModel field) {
    final index = _selectedWidgets
        .indexWhere((config) => config.fieldName == field.fieldName);

    if (index >= 0) {
      // Remove
      _selectedWidgets.removeAt(index);
    } else {
      // Add
      _selectedWidgets.add(
        DashboardWidgetConfig(
          fieldName: field.fieldName,
          fieldLabel: field.fieldLabel.trim().isEmpty
              ? field.fieldName
              : field.fieldLabel,
          chartType: _defaultChartTypeFor(field.fieldType),
          displayOrder: _selectedWidgets.length,
        ),
      );
    }

    setState(() {});
  }

  void _updateChartType(String fieldName, String newChartType) {
    final index = _selectedWidgets
        .indexWhere((config) => config.fieldName == fieldName);

    if (index >= 0) {
      _selectedWidgets[index] = DashboardWidgetConfig(
        fieldName: _selectedWidgets[index].fieldName,
        fieldLabel: _selectedWidgets[index].fieldLabel,
        chartType: newChartType,
        displayOrder: _selectedWidgets[index].displayOrder,
      );
      setState(() {});
    }
  }

  void _reorderWidgets(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = _selectedWidgets.removeAt(oldIndex);
    _selectedWidgets.insert(newIndex, item);
    setState(() {});
  }

  void _removeWidget(int index) {
    _selectedWidgets.removeAt(index);
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final configService = DashboardConfigService();
      await configService.saveConfig(
        widget.templateId,
        _selectedWidgets,
        widget.staffId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dashboard configuration saved'),
            backgroundColor: AppColors.successGreen,
            duration: Duration(seconds: 2),
          ),
        );
        widget.onSave?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving configuration: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppColors.pageBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                border: Border(
                  bottom: BorderSide(color: AppColors.cardBorder),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Configure Dashboard Widgets',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.pageBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Row(
                children: [
                  // Left: Field selector
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Fields',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: _availableFields
                                    .map(
                                      (field) => _buildFieldSelector(field),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    width: 1,
                    color: AppColors.cardBorder,
                  ),
                  // Right: Widget order preview
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      color: AppColors.cardBg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Widget Order',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _selectedWidgets.isEmpty
                                ? Center(
                                    child: Text(
                                      'Select fields to add widgets',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  )
                                : ReorderableListView(
                                    onReorder: _reorderWidgets,
                                    children: _selectedWidgets
                                        .asMap()
                                        .entries
                                        .map(
                                          (entry) => _buildWidgetTile(
                                            entry.key,
                                            entry.value,
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Footer: Save / Cancel
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.cardBorder),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: AppColors.textDark,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.highlight,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldSelector(FormFieldModel field) {
    final isSelected = _isFieldSelected(field.fieldName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _toggleField(field),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.highlight.withValues(alpha: 0.1)
                : AppColors.pageBg,
            border: Border.all(
              color: isSelected
                  ? AppColors.highlight
                  : AppColors.cardBorder,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleField(field),
                activeColor: AppColors.highlight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.fieldLabel.trim().isEmpty
                          ? field.fieldName
                          : field.fieldLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      field.fieldType.toString().split('.').last,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWidgetTile(int index, DashboardWidgetConfig config) {
    return Container(
      key: ValueKey(config.fieldName),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.drag_handle,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.fieldLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 28,
                  child: DropdownButton<String>(
                    value: config.chartType,
                    isDense: true,
                    isExpanded: true,
                    items: _chartTypeOptions
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (newType) {
                      if (newType != null) {
                        _updateChartType(config.fieldName, newType);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeWidget(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.dangerRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.close,
                color: AppColors.dangerRed,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
