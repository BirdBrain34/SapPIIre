import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart'
    hide FormFieldType;
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/widgets/form_builder_field_card.dart';
import 'package:sappiire/web/widgets/form_builder_section_header.dart';
import 'package:sappiire/web/widgets/form_builder_status_card.dart';
import 'package:sappiire/web/widgets/form_builder_template_list_panel.dart';
import 'package:sappiire/web/widgets/form_builder_title_card.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';

part 'form_builder_screen_helpers.dart';

class FormBuilderScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final String displayName;
  final String? editTemplateId;

  const FormBuilderScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    this.displayName = '',
    this.editTemplateId,
  });

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  late final FormBuilderScreenController _controller;
  final _authService = WebAuthService();
  final _scrollCtrl = ScrollController();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  double _lastCanvasOffset = 0.0;
  int _lastScrollToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = FormBuilderScreenController()
      ..cswdId = widget.cswd_id
      ..role = widget.role
      ..displayName = widget.displayName
      ..showSnackBar = _showSnackBar
      ..onShowSumColumnPicker = _showSumColumnPicker;
    _controller.addListener(_handleControllerChanged);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        _lastCanvasOffset = _scrollCtrl.offset;
      }
    });
    _controller.loadCanonicalKeys();
    _controller.loadTemplateList().then((_) {
      if (widget.editTemplateId != null) {
        _controller.loadTemplate(widget.editTemplateId!);
      }
    });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (_controller.scrollPositionToken != _lastScrollToken) {
      _lastScrollToken = _controller.scrollPositionToken;
      _setStatePreserveCanvasScroll(() {});
    } else {
      setState(() {});
    }
  }

  void _setStatePreserveCanvasScroll(VoidCallback fn) {
    final targetOffset = _scrollCtrl.hasClients
        ? _scrollCtrl.offset
        : _lastCanvasOffset;
    if (!mounted) return;
    super.setState(fn);

    void restoreOffset() {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, max).toDouble();
      if ((_scrollCtrl.offset - clamped).abs() > 0.5) {
        _scrollCtrl.jumpTo(clamped);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreOffset();
      WidgetsBinding.instance.addPostFrameCallback((_) => restoreOffset());
    });
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _saveTemplateAndSnack() async {
    final success = await _controller.saveTemplate();
    if (!mounted) return success;
    _showSnackBar(
      success
          ? 'Template saved'
          : 'Error saving template: ${_controller.lastSaveError ?? "unknown"}',
      success ? Colors.green : Colors.red,
    );
    return success;
  }

  Future<void> _publishTemplateAndSnack() async {
    if (!_controller.canPublish) {
      _showSnackBar(
        'Add at least one section with a question before publishing.',
        Colors.orange,
      );
      return;
    }
    if (_controller.hasUnsavedChanges) {
      await _saveTemplateAndSnack();
    }
    final confirmed = await _showConfirmDialog(
      title: 'Publish Form',
      message:
          'This will make the form visible to all admin users in their "Manage Forms" view. Continue?',
      confirmLabel: 'Publish',
      confirmColor: AppColors.highlight,
    );
    if (confirmed != true) return;

    final success = await _controller.publishTemplate();
    if (!mounted) return;
    _showSnackBar(
      success ? 'Form published' : 'Error publishing',
      success ? Colors.green : Colors.red,
    );
  }

  Future<void> _pushToMobileAndSnack() async {
    final confirmed = await _showConfirmDialog(
      title: 'Push to Mobile',
      message:
          'This will make the form available on the mobile app. Users will see it in their forms list. Continue?',
      confirmLabel: 'Push to Mobile',
      confirmColor: Colors.green,
    );
    if (confirmed != true) return;

    final success = await _controller.pushToMobile();
    if (!mounted) return;
    _showSnackBar(
      success ? 'Pushed to mobile' : 'Error pushing',
      success ? Colors.green : Colors.red,
    );
  }

  Future<void> _archiveTemplateAndSnack() async {
    final confirmed = await _showConfirmDialog(
      title: 'Archive Form',
      message:
          'This will remove the form from admins\' and mobile users\' view but keep all data intact for historical reference. Continue?',
      confirmLabel: 'Archive',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;

    final success = await _controller.archiveTemplate();
    if (!mounted) return;
    _showSnackBar(
      success
          ? 'Form archived'
          : 'Error archiving: ${_controller.lastActionError ?? "unknown error"}',
      success ? Colors.orange : Colors.red,
    );
  }

  Future<void> _restoreTemplateAndSnack() async {
    final success = await _controller.restoreTemplate();
    if (!mounted) return;
    _showSnackBar(
      success
          ? 'Form restored to draft'
          : 'Error restoring: ${_controller.lastActionError ?? "unknown error"}',
      success ? Colors.green : Colors.red,
    );
  }

  Future<void> _unpublishTemplateAndSnack() async {
    final confirmed = await _showConfirmDialog(
      title: 'Unpublish Form',
      message:
          'This will revert the form to draft status. It will no longer be visible to admins or mobile users. Continue?',
      confirmLabel: 'Unpublish',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;
    await _controller.unpublishTemplate();
  }

  Future<void> _handleTemplateSelect(String templateId) async {
    if (templateId == _controller.activeTemplateId) return;
    if (!await _confirmLeave()) return;
    await _controller.loadTemplate(templateId);
  }

  Future<bool> _confirmLeave() async {
    if (!_controller.hasUnsavedChanges) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleLogout() async {
    if (!await _confirmLeave()) return;
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ContentFadeRoute(page: const WorkerLoginScreen()),
      (route) => false,
    );
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
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showSystemBlockPicker(int sectionIndex) =>
      showSystemBlockPicker(this, sectionIndex);

  void _showSumColumnPicker(BuilderField field) =>
      showSumColumnPicker(this, field);

  void _showColumnPicker(
    BuilderField field,
    String tableKey,
    List<BuilderColumn> columns,
  ) => showColumnPicker(this, field, tableKey, columns);

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildFormBuilderScreen(this);

  Widget _buildBuilderCanvas() => buildBuilderCanvas(this);

  Widget _buildCanvasToolbar() => buildCanvasToolbar(this);

  List<Widget> _buildAllSections() => buildAllSections(this);

  Widget _buildAddSectionButton() => buildAddSectionButton(this);

  Widget _buildEmptyState() => buildEmptyState(this);

  List<Widget> _buildHeaderActions() => buildHeaderActions(this);

  Widget _headerBtn(
    String label,
    IconData icon, {
    VoidCallback? onPressed,
    Color? color,
  }) => headerBtn(this, label, icon, onPressed: onPressed, color: color);
}
