import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/dashboard_config_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/widgets/web_shell.dart';

class DashboardConfigScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;

  const DashboardConfigScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
  });

  @override
  State<DashboardConfigScreen> createState() => _DashboardConfigScreenState();
}

class _DashboardConfigScreenState extends State<DashboardConfigScreen> {
  static const _excludedFieldTypes = {
    'signature',
    'family_table',
    'supporting_family_table',
    'computed',
    'paragraph',
    'membership_group',
    'member_table',
    'unknown',
    'time',
  };

  final _templateService = FormTemplateService();
  final _configService = DashboardConfigService();

  List<FormTemplate> _templates = [];
  final Map<String, bool> _templateConfigPresence = {};

  FormTemplate? _selectedTemplate;
  List<DashboardWidgetConfig> _widgets = [];
  String? _selectedFieldName;
  String _selectedChartType = 'bar';

  bool _isLoadingTemplates = true;
  bool _isLoadingWidgets = false;
  bool _isSaving = false;
  int _selectionToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoadingTemplates = true);

    final templates = await _templateService.fetchActiveTemplates(
      forceRefresh: true,
    );
    final configResults = await Future.wait(
      templates.map((template) => _configService.fetchConfig(template.templateId)),
    );

    final presence = <String, bool>{};
    for (var index = 0; index < templates.length; index++) {
      presence[templates[index].templateId] = configResults[index].isNotEmpty;
    }

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _templateConfigPresence
        ..clear()
        ..addAll(presence);
      _isLoadingTemplates = false;

      if (_selectedTemplate != null) {
        final matches = templates.where(
          (template) => template.templateId == _selectedTemplate!.templateId,
        );
        if (matches.isNotEmpty) {
          _selectedTemplate = matches.first;
        }
      }
    });
  }

  Future<void> _selectTemplate(FormTemplate template) async {
    final token = ++_selectionToken;
    setState(() {
      _selectedTemplate = template;
      _widgets = [];
      _selectedFieldName = null;
      _selectedChartType = 'bar';
      _isLoadingWidgets = true;
    });

    final widgets = await _configService.fetchConfig(template.templateId);
    if (!mounted || token != _selectionToken) return;

    setState(() {
      _widgets = widgets;
      _isLoadingWidgets = false;
      _templateConfigPresence[template.templateId] = widgets.isNotEmpty;
    });
  }

  List<FormFieldModel> get _eligibleFields {
    final template = _selectedTemplate;
    if (template == null) return const [];

    return template.allFields.where((field) {
      return field.parentFieldId == null &&
          !_excludedFieldTypes.contains(field.fieldType.toDbString());
    }).toList();
  }

  List<FormFieldModel> get _availableFields {
    final selectedNames = _widgets.map((widget) => widget.fieldName).toSet();
    return _eligibleFields
        .where((field) => !selectedNames.contains(field.fieldName))
        .toList();
  }

  FormFieldModel? _fieldByName(String? fieldName) {
    if (fieldName == null) return null;
    for (final field in _eligibleFields) {
      if (field.fieldName == fieldName) return field;
    }
    return null;
  }

  String _chartTypeLabel(String chartType) {
    switch (chartType) {
      case 'pie':
        return 'Pie / Distribution';
      case 'counter':
        return 'Counter Card';
      default:
        return 'Bar Chart';
    }
  }

  IconData _chartTypeIcon(String chartType) {
    switch (chartType) {
      case 'pie':
        return Icons.pie_chart_outline;
      case 'counter':
        return Icons.tag;
      default:
        return Icons.bar_chart;
    }
  }

  Color _chartTypeColor(String chartType) {
    switch (chartType) {
      case 'pie':
        return AppColors.successGreen;
      case 'counter':
        return AppColors.warningAmber;
      default:
        return AppColors.highlight;
    }
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _addWidget() async {
    final template = _selectedTemplate;
    final field = _fieldByName(_selectedFieldName);
    if (template == null || field == null) return;

    setState(() {
      _widgets = [
        ..._widgets,
        DashboardWidgetConfig(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          templateId: template.templateId,
          fieldName: field.fieldName,
          fieldLabel: field.fieldLabel,
          chartType: _selectedChartType,
          displayOrder: _widgets.length,
        ),
      ];
      _selectedFieldName = null;
      _selectedChartType = 'bar';
      _templateConfigPresence[template.templateId] = true;
    });
  }

  void _moveWidget(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _widgets.length) return;

    setState(() {
      final updated = List<DashboardWidgetConfig>.from(_widgets);
      final item = updated.removeAt(index);
      updated.insert(nextIndex, item);
      _widgets = [
        for (var i = 0; i < updated.length; i++)
          DashboardWidgetConfig(
            id: updated[i].id,
            templateId: updated[i].templateId,
            fieldName: updated[i].fieldName,
            fieldLabel: updated[i].fieldLabel,
            chartType: updated[i].chartType,
            displayOrder: i,
          ),
      ];
    });
  }

  void _removeWidget(int index) {
    setState(() {
      _widgets = [
        for (var i = 0; i < _widgets.length; i++)
          if (i != index)
            DashboardWidgetConfig(
              id: _widgets[i].id,
              templateId: _widgets[i].templateId,
              fieldName: _widgets[i].fieldName,
              fieldLabel: _widgets[i].fieldLabel,
              chartType: _widgets[i].chartType,
              displayOrder: i > index ? i - 1 : i,
            ),
      ];
    });
  }

  Future<void> _saveConfiguration() async {
    final template = _selectedTemplate;
    if (template == null) return;

    setState(() => _isSaving = true);
    final success = await _configService.saveConfig(
      template.templateId,
      _widgets,
      widget.cswd_id,
    );

    if (!mounted) return;
    if (success) {
      final refreshed = await _configService.fetchConfig(template.templateId);
      if (!mounted) return;
      setState(() {
        _widgets = refreshed;
        _templateConfigPresence[template.templateId] = refreshed.isNotEmpty;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard configuration saved.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } else {
      final err = _configService.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err == null
              ? 'Failed to save dashboard configuration.'
              : 'Failed to save dashboard configuration: ${err.split('\n').first}'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _clearAllWidgets() async {
    final template = _selectedTemplate;
    if (template == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Dashboard Widgets'),
        content: const Text(
          'This will remove all dashboard widget configurations for this form template.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: AppColors.dangerRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _configService.deleteConfig(template.templateId);
      if (!mounted) return;
      setState(() {
        _widgets = [];
        _templateConfigPresence[template.templateId] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard configuration cleared.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear dashboard configuration.'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 56,
            color: AppColors.textMuted,
          ),
          SizedBox(height: 14),
          Text(
            'Select a form template to configure its dashboard widgets',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(color: AppColors.highlight),
      ),
    );
  }

  Widget _buildAddWidgetCard() {
    final fields = _availableFields;
    final fieldItems = fields
        .map(
          (field) => DropdownMenuItem<String>(
            value: field.fieldName,
            child: Text(field.fieldLabel),
          ),
        )
        .toList();

    final chartItems = [
      DropdownMenuItem<String>(
        value: 'bar',
        child: Row(
          children: const [
            Icon(Icons.bar_chart, size: 18),
            SizedBox(width: 8),
            Text('Bar Chart'),
          ],
        ),
      ),
      DropdownMenuItem<String>(
        value: 'pie',
        child: Row(
          children: const [
            Icon(Icons.pie_chart_outline, size: 18),
            SizedBox(width: 8),
            Text('Pie / Distribution'),
          ],
        ),
      ),
      DropdownMenuItem<String>(
        value: 'counter',
        child: Row(
          children: const [
            Icon(Icons.tag, size: 18),
            SizedBox(width: 8),
            Text('Counter Card'),
          ],
        ),
      ),
      DropdownMenuItem<String>(
        value: 'hbar',
        child: Row(
          children: const [
            Icon(Icons.bar_chart, size: 18),
            SizedBox(width: 8),
            Text('Horizontal Bar'),
          ],
        ),
      ),
      DropdownMenuItem<String>(
        value: 'table',
        child: Row(
          children: const [
            Icon(Icons.table_chart_outlined, size: 18),
            SizedBox(width: 8),
            Text('Data Table'),
          ],
        ),
      ),
    ];

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Widget',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;

              final fieldDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedFieldName != null &&
                        fields.any((field) => field.fieldName == _selectedFieldName)
                    ? _selectedFieldName
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select field'),
                items: fieldItems,
                onChanged: fields.isEmpty
                    ? null
                    : (value) {
                        setState(() => _selectedFieldName = value);
                      },
              );

              final chartDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedChartType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chart type'),
                items: chartItems,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedChartType = value);
                },
              );

              final addButton = ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.highlight,
                  foregroundColor: Colors.white,
                ),
                onPressed: fields.isEmpty || _selectedFieldName == null
                    ? null
                    : _addWidget,
                child: const Text('Add Widget'),
              );

              if (compact) {
                return Column(
                  children: [
                    fieldDropdown,
                    const SizedBox(height: 12),
                    chartDropdown,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: addButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fieldDropdown),
                  const SizedBox(width: 12),
                  SizedBox(width: 280, child: chartDropdown),
                  const SizedBox(width: 12),
                  addButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetRow(int index, DashboardWidgetConfig config) {
    return Container(
      margin: EdgeInsets.only(bottom: index == _widgets.length - 1 ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Icon(_chartTypeIcon(config.chartType), color: _chartTypeColor(config.chartType)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.fieldLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  config.fieldName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _chartTypeColor(config.chartType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _chartTypeLabel(config.chartType),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _chartTypeColor(config.chartType),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: index == 0 ? null : () => _moveWidget(index, -1),
            icon: const Icon(Icons.keyboard_arrow_up),
            color: AppColors.textMuted,
            tooltip: 'Move up',
          ),
          IconButton(
            onPressed: index == _widgets.length - 1 ? null : () => _moveWidget(index, 1),
            icon: const Icon(Icons.keyboard_arrow_down),
            color: AppColors.textMuted,
            tooltip: 'Move down',
          ),
          IconButton(
            onPressed: () => _removeWidget(index),
            icon: const Icon(Icons.delete_outline),
            color: AppColors.dangerRed,
            tooltip: 'Delete widget',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentWidgetsList() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Widgets',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingWidgets)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.highlight),
              ),
            )
          else if (_widgets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No widgets configured. Add fields above.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < _widgets.length; index++)
                  _buildWidgetRow(index, _widgets[index]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedTemplatePanel() {
    final template = _selectedTemplate;
    if (template == null) return _buildEmptyState();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardShell(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.formName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Configure which fields appear on the dashboard and how they are visualized',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSaving ? null : _saveConfiguration,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.highlight,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save Configuration'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerRed,
                    side: const BorderSide(color: AppColors.dangerRed),
                  ),
                  onPressed: _isSaving ? null : _clearAllWidgets,
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildAddWidgetCard(),
          const SizedBox(height: 20),
          _buildCurrentWidgetsList(),
        ],
      ),
    );
  }

  Widget _buildTemplateItem(FormTemplate template) {
    final isActive = _selectedTemplate?.templateId == template.templateId;
    final configured = _templateConfigPresence[template.templateId] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.highlight.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: AppColors.highlight.withValues(alpha: 0.3))
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
          template.formName,
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
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: configured ? AppColors.successGreen : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              configured ? 'Configured' : 'Not configured',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        onTap: () {
          if (!isActive) {
            _selectTemplate(template);
          }
        },
      ),
    );
  }

  void _navigateToScreen(String path) {
    Widget? next;

    switch (path) {
      case 'Dashboard':
        next = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
          onLogout: () => Navigator.pop(context),
        );
        break;
      case 'Forms':
        next = ManageFormsScreen(
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
      case 'Staff':
        if (widget.role != 'superadmin') return;
        next = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'CreateStaff':
        if (widget.role != 'superadmin') return;
        next = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      case 'FormBuilder':
        if (widget.role != 'superadmin' && widget.role != 'admin') return;
        next = FormBuilderScreen(
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
      case 'DashboardConfig':
        if (widget.role != 'superadmin' && widget.role != 'admin') return;
        next = DashboardConfigScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          displayName: widget.displayName,
        );
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(ContentFadeRoute(page: next));
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'DashboardConfig',
      pageTitle: 'Dashboard Configuration',
      pageSubtitle: 'Define which fields to visualize per form',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: () => Navigator.pop(context),
      onNavigate: _navigateToScreen,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
                            'Form Templates',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _isLoadingTemplates ? null : _loadTemplates,
                          icon: const Icon(Icons.refresh),
                          color: AppColors.highlight,
                          tooltip: 'Refresh templates',
                          iconSize: 22,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.cardBorder),
                  Expanded(
                    child: _isLoadingTemplates
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.highlight,
                            ),
                          )
                        : _templates.isEmpty
                            ? const Center(
                                child: Text(
                                  'No active templates found',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _templates.length,
                                itemBuilder: (context, index) {
                                  return _buildTemplateItem(_templates[index]);
                                },
                              ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: _isLoadingWidgets
                    ? _buildLoadingState()
                    : _buildSelectedTemplatePanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}