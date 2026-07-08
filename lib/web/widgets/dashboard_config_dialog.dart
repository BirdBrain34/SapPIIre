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
  final Future<void> Function()? onSave;

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
    'line',
  ];

  @override
  void initState() {
    super.initState();
    _selectedWidgets = List.from(widget.initialConfigs);

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
    return _selectedWidgets.any((config) => config.fieldName == fieldName);
  }

  void _toggleField(FormFieldModel field) {
    final index = _selectedWidgets
        .indexWhere((config) => config.fieldName == field.fieldName);

    if (index >= 0) {
      _selectedWidgets.removeAt(index);
    } else {
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
        await widget.onSave?.call();
        if (mounted) {
          Navigator.of(context).pop();
        }
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

  // ---------------------------------------------------------------------------
  // Chart type icon & label helpers
  // ---------------------------------------------------------------------------
  String _chartTypeLabel(String type) {
    switch (type) {
      case 'bar':
        return 'Bar Chart';
      case 'hbar':
        return 'Horizontal Bar';
      case 'pie':
        return 'Pie Chart';
      case 'donut':
        return 'Donut Chart';
      case 'line':
        return 'Line Chart';
      case 'area':
        return 'Area Chart';
      case 'stacked':
        return 'Stacked Bar';
      case 'counter':
        return 'Counter';
      case 'table':
        return 'Data Table';
      case 'funnel':
        return 'Funnel Chart';
      default:
        return type;
    }
  }

  IconData _chartTypeIcon(String type) {
    switch (type) {
      case 'bar':
        return Icons.bar_chart_rounded;
      case 'hbar':
        return Icons.bar_chart_rounded;
      case 'pie':
        return Icons.pie_chart_rounded;
      case 'donut':
        return Icons.donut_large_rounded;
      case 'line':
        return Icons.show_chart_rounded;
      case 'area':
        return Icons.area_chart_rounded;
      case 'stacked':
        return Icons.stacked_bar_chart_rounded;
      case 'counter':
        return Icons.pin_rounded;
      case 'table':
        return Icons.table_chart_rounded;
      case 'funnel':
        return Icons.filter_alt_rounded;
      default:
        return Icons.bar_chart_rounded;
    }
  }

  IconData _fieldTypeIcon(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return Icons.text_fields_rounded;
      case FormFieldType.paragraph:
        return Icons.notes_rounded;
      case FormFieldType.date:
        return Icons.calendar_month_rounded;
      case FormFieldType.time:
        return Icons.access_time_rounded;
      case FormFieldType.number:
        return Icons.numbers_rounded;
      case FormFieldType.dropdown:
        return Icons.arrow_drop_down_circle_rounded;
      case FormFieldType.radio:
        return Icons.radio_button_checked_rounded;
      case FormFieldType.checkbox:
        return Icons.check_box_rounded;
      case FormFieldType.boolean:
        return Icons.toggle_on_rounded;
      case FormFieldType.linearScale:
        return Icons.linear_scale_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Color _fieldTypeColor(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return const Color(0xFF4C8BF5);
      case FormFieldType.paragraph:
        return const Color(0xFF8B5CF6);
      case FormFieldType.date:
        return const Color(0xFF2EC4B6);
      case FormFieldType.time:
        return const Color(0xFF06B6D4);
      case FormFieldType.number:
        return const Color(0xFFF59E0B);
      case FormFieldType.dropdown:
        return const Color(0xFF6366F1);
      case FormFieldType.radio:
        return const Color(0xFFEC4899);
      case FormFieldType.checkbox:
        return const Color(0xFF10B981);
      case FormFieldType.boolean:
        return const Color(0xFFF97316);
      case FormFieldType.linearScale:
        return const Color(0xFF8B5CF6);
      default:
        return AppColors.textMuted;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    return Dialog(
      child: Container(
        width: isWide ? 960 : screenWidth * 0.92,
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: AppColors.pageBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:  0.25),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.highlight.withValues(alpha:  0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: AppColors.highlight,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configure Dashboard',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Select fields and assign chart types for ${widget.template.formName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted.withValues(alpha:  0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(8),
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
    );
  }

  // ------------------------------------------------------------------------  // Wide: two-panel layout
  // ---------------------------------------------------------------------------
  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildFieldSelectorPanel(),
        ),
        Container(width: 1, color: AppColors.cardBorder),
        Expanded(
          flex: 5,
          child: _buildWidgetOrderPanel(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Narrow: tabbed layout
  // ---------------------------------------------------------------------------
  Widget _buildNarrowLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppColors.cardBg,
            child: TabBar(
              labelColor: AppColors.highlight,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.highlight,
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.list_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Available Fields'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.widgets_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Widget Order'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildFieldSelectorPanel(),
                _buildWidgetOrderPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Available Fields Panel
  // ---------------------------------------------------------------------------
  Widget _buildFieldSelectorPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Available Fields',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.highlight.withValues(alpha:  0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_availableFields.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.highlight,
                  ),
                ),
              ),
              const Spacer(),
              if (_selectedWidgets.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedWidgets.clear());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerRed.withValues(alpha:  0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all_rounded, size: 14, color: AppColors.dangerRed),
                        SizedBox(width: 4),
                        Text(
                          'Clear All',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dangerRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a field to add it to the dashboard',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted.withValues(alpha:  0.7),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _availableFields.isEmpty
                ? _buildEmptyFields()
                : ListView.separated(
                    itemCount: _availableFields.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      return _buildFieldSelectorTile(_availableFields[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFields() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No chartable fields available',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldSelectorTile(FormFieldModel field) {
    final isSelected = _isFieldSelected(field.fieldName);
    final fieldColor = _fieldTypeColor(field.fieldType);

    return GestureDetector(
      onTap: () => _toggleField(field),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.highlight.withValues(alpha:  0.07)
              : AppColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.highlight.withValues(alpha:  0.5)
                : AppColors.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.highlight.withValues(alpha:  0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: fieldColor.withValues(alpha:  0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _fieldTypeIcon(field.fieldType),
                size: 18,
                color: fieldColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.fieldLabel.trim().isEmpty
                        ? field.fieldName
                        : field.fieldLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.highlight
                          : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    field.fieldType.toString().split('.').last,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted.withValues(alpha:  0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.highlight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: AppColors.textMuted.withValues(alpha:  0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widget Order Panel
  // ---------------------------------------------------------------------------
  Widget _buildWidgetOrderPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Widget Order',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha:  0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_selectedWidgets.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Drag to reorder, tap the X to remove',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted.withValues(alpha:  0.7),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _selectedWidgets.isEmpty
                ? _buildEmptyOrder()
                : ReorderableListView.builder(
                    onReorder: _reorderWidgets,
                    itemCount: _selectedWidgets.length,
                    proxyDecorator: (child, index, animation) {
                      return _DragProxy(
                        animation: animation,
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      return _buildWidgetTile(index, _selectedWidgets[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyOrder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.widgets_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Select fields from the left panel',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 4),
          Text(
            'Selected fields will appear here',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetTile(int index, DashboardWidgetConfig config) {
    return Container(
      key: ValueKey(config.fieldName),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:  0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: drag handle + chart icon + label + remove button
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha:  0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: AppColors.textMuted.withValues(alpha:  0.5),
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _chartTypeColor(config.chartType).withValues(alpha:  0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _chartTypeIcon(config.chartType),
                  size: 16,
                  color: _chartTypeColor(config.chartType),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.fieldLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _removeWidget(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.dangerRed.withValues(alpha:  0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.dangerRed,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bottom row: full-width chart type dropdown
          SizedBox(
            width: double.infinity,
            height: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: config.chartType,
                    isDense: true,
                    isExpanded: true,
                    icon: Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.textMuted.withValues(alpha:  0.6),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
                    items: _chartTypeOptions.map((type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Row(
                          children: [
                            Icon(
                              _chartTypeIcon(type),
                              size: 12,
                              color: _chartTypeColor(type),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _chartTypeLabel(type),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newType) {
                      if (newType != null) {
                        _updateChartType(config.fieldName, newType);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _chartTypeColor(String type) {
    switch (type) {
      case 'bar':
        return AppColors.highlight;
      case 'hbar':
        return const Color(0xFF6366F1);
      case 'pie':
        return const Color(0xFFEC4899);
      case 'donut':
        return const Color(0xFF8B5CF6);
      case 'line':
        return const Color(0xFF2EC4B6);
      case 'area':
        return const Color(0xFF06B6D4);
      case 'stacked':
        return const Color(0xFFF59E0B);
      case 'counter':
        return const Color(0xFF10B981);
      case 'table':
        return const Color(0xFF6B7280);
      case 'funnel':
        return const Color(0xFFF97316);
      default:
        return AppColors.highlight;
    }
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(
          top: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              side: BorderSide(color: AppColors.cardBorder),
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.save_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Save ${_selectedWidgets.length} Widget${_selectedWidgets.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// Drag proxy animated wrapper
class _DragProxy extends AnimatedWidget {
  final Widget child;

  const _DragProxy({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final anim = listenable as Animation<double>;
    return Material(
      elevation: 4.0 * anim.value,
      borderRadius: BorderRadius.circular(10),
      shadowColor: AppColors.highlight.withValues(alpha:  0.2 * anim.value),
      color: Colors.transparent,
      child: child,
    );
  }
}
