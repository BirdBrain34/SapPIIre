import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/canonical_key_entry.dart';
import 'package:sappiire/services/audit/audit_log_service.dart';
import 'package:sappiire/services/form_builder_service.dart';

/// Full management dialog for the canonical key registry.
/// Opened from the Form Builder canvas toolbar's "Manage Keys" button.
Future<void> showCanonicalKeyManagerDialog(
  BuildContext context,
  FormBuilderService service, {
  required String cswdId,
  required String displayName,
  required String role,
  required VoidCallback onChanged,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _CanonicalKeyManagerDialog(
      service: service,
      cswdId: cswdId,
      displayName: displayName,
      role: role,
      onChanged: onChanged,
    ),
  );
}

class _CanonicalKeyManagerDialog extends StatefulWidget {
  final FormBuilderService service;
  final String cswdId;
  final String displayName;
  final String role;
  final VoidCallback onChanged;

  const _CanonicalKeyManagerDialog({
    required this.service,
    required this.cswdId,
    required this.displayName,
    required this.role,
    required this.onChanged,
  });

  @override
  State<_CanonicalKeyManagerDialog> createState() =>
      _CanonicalKeyManagerDialogState();
}

class _CanonicalKeyManagerDialogState
    extends State<_CanonicalKeyManagerDialog> {
  List<CanonicalKeyEntry> _entries = [];
  Map<String, int> _usageCounts = {};
  bool _isLoading = true;
  String? _actionError;
  String? _editingKey;
  final _editLabelCtrl = TextEditingController();
  final _editDescCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editLabelCtrl.dispose();
    _editDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final entries =
        await widget.service.fetchCanonicalKeyRegistry(activeOnly: false);
    final counts = await widget.service.fetchCanonicalKeyUsageCounts();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _usageCounts = counts;
      _isLoading = false;
    });
  }

  Future<void> _toggleActive(CanonicalKeyEntry entry) async {
    if (entry.isSystem) return;
    final newActive = !entry.isActive;
    final ok = await widget.service.setCanonicalKeyActive(
        entry.keyName, newActive);
    if (!ok || !mounted) return;

    if (!newActive) {
      await AuditLogService().log(
        actionType: kAuditCanonicalKeyDeactivated,
        category: kCategoryTemplate,
        severity: kSeverityInfo,
        actorId: widget.cswdId,
        actorName: widget.displayName,
        actorRole: widget.role,
        targetType: 'canonical_key',
        targetId: entry.keyName,
        targetLabel: entry.displayLabel,
      );
    }

    widget.onChanged();
    await _load();
  }

  Future<void> _saveEdit() async {
    if (_editingKey == null) return;
    setState(() => _isSaving = true);
    final ok = await widget.service.updateCanonicalKeyMeta(
      keyName: _editingKey!,
      displayLabel: _editLabelCtrl.text.trim(),
      description: _editDescCtrl.text.trim().isEmpty
          ? null
          : _editDescCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _editingKey = null;
        _isSaving = false;
      });
      widget.onChanged();
      await _load();
    } else {
      setState(() {
        _actionError = 'Failed to update key.';
        _isSaving = false;
      });
    }
  }

  void _startEdit(CanonicalKeyEntry entry) {
    _editLabelCtrl.text = entry.displayLabel;
    _editDescCtrl.text = entry.description ?? '';
    setState(() {
      _editingKey = entry.keyName;
      _actionError = null;
    });
  }

  Future<void> _delete(CanonicalKeyEntry entry) async {
    final result = await widget.service.deleteUnusedCanonicalKey(entry.keyName);
    if (!mounted) return;
    if (result['success'] == true) {
      widget.onChanged();
      await _load();
    } else {
      setState(() {
        _actionError = result['message']?.toString() ?? 'Failed to delete.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key, size: 22, color: AppColors.highlight),
                const SizedBox(width: 10),
                const Text(
                  'Manage Canonical Keys',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'System (reserved) keys cannot be renamed, deactivated, or deleted.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 8),
              Text(
                _actionError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.highlight),
                ),
              )
            else if (_entries.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No keys found.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.cardBorder),
                  itemBuilder: (_, i) => _buildRow(_entries[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(CanonicalKeyEntry entry) {
    final usage = _usageCounts[entry.keyName] ?? 0;
    final isEditing = _editingKey == entry.keyName;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: isEditing ? _buildEditRow(entry) : _buildDisplayRow(entry, usage),
    );
  }

  Widget _buildDisplayRow(CanonicalKeyEntry entry, int usage) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // System badge
        if (entry.isSystem)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.highlight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 10, color: AppColors.highlight),
                SizedBox(width: 3),
                Text(
                  'System',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.highlight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(width: 50),
        const SizedBox(width: 10),
        // Active indicator
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: entry.isActive ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        // Name + display label
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.displayLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                entry.keyName,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        // Description
        Expanded(
          flex: 2,
          child: Text(
            entry.description ?? '',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        // Usage count
        SizedBox(
          width: 40,
          child: Text(
            '$usage',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: usage > 0 ? AppColors.textDark : AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        // Actions
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 16),
          tooltip: 'Edit label/description',
          onPressed: () => _startEdit(entry),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        if (entry.isSystem)
          IconButton(
            icon: Icon(Icons.toggle_off_outlined,
                size: 16, color: Colors.grey.shade300),
            tooltip: 'System keys cannot be deactivated',
            onPressed: null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )
        else
          IconButton(
            icon: Icon(
              entry.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
              size: 16,
              color: entry.isActive ? Colors.green : AppColors.textMuted,
            ),
            tooltip: entry.isActive ? 'Deactivate' : 'Activate',
            onPressed: () => _toggleActive(entry),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 16,
            color: entry.isSystem || usage > 0 ? Colors.grey.shade300 : Colors.red,
          ),
          tooltip: entry.isSystem
              ? 'System keys cannot be deleted'
              : usage > 0
                  ? 'In use by $usage field(s) — deactivate instead'
                  : 'Delete',
          onPressed: (entry.isSystem || usage > 0) ? null : () => _delete(entry),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildEditRow(CanonicalKeyEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Editing: ${entry.keyName}',
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _editLabelCtrl,
          decoration: InputDecoration(
            labelText: 'Display label',
            filled: true,
            fillColor: AppColors.pageBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _editDescCtrl,
          decoration: InputDecoration(
            labelText: 'Description',
            filled: true,
            fillColor: AppColors.pageBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            isDense: true,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _editingKey = null),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.highlight,
                foregroundColor: Colors.white,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}