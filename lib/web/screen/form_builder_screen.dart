import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/widgets/form_builder_field_card.dart';
import 'package:sappiire/web/widgets/form_builder_section_header.dart';
import 'package:sappiire/web/widgets/form_builder_status_card.dart';
import 'package:sappiire/web/widgets/form_builder_template_list_panel.dart';
import 'package:sappiire/web/widgets/form_builder_title_card.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/utils/web_session.dart';

part 'form_builder_screen_helpers.dart';

class FormBuilderScreen extends StatefulWidget {
  final String cswdId;
  final String role;
  final String displayName;
  final String? editTemplateId;

  const FormBuilderScreen({
    super.key,
    required this.cswdId,
    required this.role,
    this.displayName = '',
    this.editTemplateId,
  });

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  late final FormBuilderScreenController _controller;
  final _scrollCtrl = ScrollController();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();

  // ---------------------------------------------------------------
  // Scroll-preservation: instead of fighting the ScrollController
  // with post-frame callbacks (which caused rubber-banding), we
  // save the offset before setState and restore it synchronously
  // in the same frame via a LayoutBuilder / post-frame single shot.
  // For text-field changes we skip the rebuild entirely.
  // ---------------------------------------------------------------
  double _savedScrollOffset = 0.0;
  bool _pendingScrollRestore = false;

  @override
  void initState() {
    super.initState();
    _controller = FormBuilderScreenController()
      ..cswdId = widget.cswdId
      ..role = widget.role
      ..displayName = widget.displayName
      ..showSnackBar = _showSnackBar
      ..onShowSumColumnPicker = _showSumColumnPicker;
    _controller.addListener(_handleControllerChanged);
    _controller.loadCanonicalKeys();
    _controller.loadTemplateList().then((_) {
      if (widget.editTemplateId != null) {
        _controller.loadTemplate(widget.editTemplateId!);
      }
    });
  }

  /// Called whenever the controller calls notifyListeners().
  ///
  /// Key insight: text fields update [field.label] directly in their
  /// onChanged callbacks without calling markChanged(), so we only
  /// get notified for structural changes (add/remove field, type
  /// change, etc.).  For those we DO want a rebuild, but we must
  /// preserve scroll position.
  void _handleControllerChanged() {
    if (!mounted) return;
    // Snapshot offset before setState so the restore is synchronous.
    if (_scrollCtrl.hasClients) {
      _savedScrollOffset = _scrollCtrl.offset;
      _pendingScrollRestore = true;
    }
    setState(() {});
    // Restore in the very next frame — exactly one shot.
    if (_pendingScrollRestore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingScrollRestore = false;
        if (!mounted || !_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        final target = _savedScrollOffset.clamp(0.0, max);
        if ((_scrollCtrl.offset - target).abs() > 1.0) {
          _scrollCtrl.jumpTo(target);
        }
      });
    }
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

  Future<void> _submitForApprovalAndSnack() async {
    if (!_controller.canPublish) {
      _showSnackBar(
        'Add at least one section with a question before submitting for approval.',
        Colors.orange,
      );
      return;
    }
    if (_controller.hasUnsavedChanges) {
      await _saveTemplateAndSnack();
    }
    final confirmed = await _showConfirmDialog(
      title: 'Submit for Approval',
      message:
          'This will submit the form to a superadmin for review and approval. You will not be able to publish it directly. Continue?',
      confirmLabel: 'Submit',
      confirmColor: Colors.deepPurple,
    );
    if (confirmed != true) return;

    final success = await _controller.submitForApproval();
    if (!mounted) return;
    _showSnackBar(
      success ? 'Form submitted for approval' : 'Error submitting for approval',
      success ? Colors.deepPurple : Colors.red,
    );
  }

  Future<void> _approvePendingAndSnack() async {
    final confirmed = await _showConfirmDialog(
      title: 'Approve Form',
      message:
          'This will approve the form and publish it, making it visible to all admin users. Continue?',
      confirmLabel: 'Approve & Publish',
      confirmColor: Colors.green,
    );
    if (confirmed != true) return;

    final success = await _controller.approvePendingTemplate();
    if (!mounted) return;
    _showSnackBar(
      success ? 'Form approved and published' : 'Error approving form',
      success ? Colors.green : Colors.red,
    );
  }

  Future<void> _rejectPendingAndSnack() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Form'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Provide a reason for rejection:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Reason for rejection...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Reject',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    final success = await _controller.rejectPendingTemplate(reason);
    if (!mounted) return;
    _showSnackBar(
      success ? 'Form rejected and returned to draft' : 'Error rejecting form',
      success ? Colors.orange : Colors.red,
    );
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
    if (mounted) await WebSession.logout(context);
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

  void _showSumColumnPicker(BuilderField field) =>
      showSumColumnPicker(this, field);

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildFormBuilderScreen(this);
}
