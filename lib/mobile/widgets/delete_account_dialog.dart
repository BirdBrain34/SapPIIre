// lib/mobile/widgets/delete_account_dialog.dart
// Destructive confirmation popup for permanent account + data erasure
// (Data Privacy Act of 2012, R.A. 10173 — right to erasure).
//
// Modeled on unsaved_changes_dialog.dart: non-dismissible PopScope, header bar,
// warning bubble, and an internal _isDeleting state that disables the buttons
// and swaps the CTA for a spinner while the async delete runs. Adds a
// type-"DELETE"-to-confirm gate so the destructive action can't be tapped by
// accident.

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class DeleteAccountDialog extends StatefulWidget {
  /// Runs the deletion. Should perform the delete and, on success, navigate
  /// away (which disposes this dialog). On failure it should return so the
  /// dialog re-enables for another attempt.
  final Future<void> Function() onConfirmDelete;

  const DeleteAccountDialog({super.key, required this.onConfirmDelete});

  /// Shows the dialog. Non-dismissible; the user must explicitly cancel.
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onConfirmDelete,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(onConfirmDelete: onConfirmDelete),
    );
  }

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  static const String _confirmWord = 'DELETE';

  final TextEditingController _confirmCtrl = TextEditingController();
  bool _isDeleting = false;
  bool get _canDelete =>
      _confirmCtrl.text.trim().toUpperCase() == _confirmWord && !_isDeleting;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    if (!_canDelete) return;
    setState(() => _isDeleting = true);
    try {
      await widget.onConfirmDelete();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        backgroundColor: Colors.white,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: const BoxDecoration(color: AppColors.dangerRed),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Delete My Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Body ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.dangerRed.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.dangerRed,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'This cannot be undone',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Deleting your account permanently erases your login, '
                        'profile, and all personal information stored on your '
                        'device account. You will be signed out immediately.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // Retention notice — records already submitted to the
                      // office are kept, consistent with the Privacy notice.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14,
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.7)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Records you already submitted to the CSWD '
                                'office are retained as official records '
                                '(R.A. 10173).',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primaryBlue
                                      .withValues(alpha: 0.75),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Type-to-confirm gate.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Type $_confirmWord to confirm',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmCtrl,
                        enabled: !_isDeleting,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: _confirmWord,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.dangerRed, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEEEEF4)),
                ),

                // ── Action buttons ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _canDelete ? _handleDelete : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dangerRed,
                          disabledBackgroundColor:
                              AppColors.dangerRed.withValues(alpha: 0.4),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.delete_forever_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete Permanently',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _isDeleting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
