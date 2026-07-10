// lib/mobile/widgets/unsaved_changes_dialog.dart
// Reusable unsaved-changes popup.
// Shown whenever the user tries to leave the form with pending edits,
// switch templates, log out, or navigate away via bottom nav.

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class UnsavedChangesDialog extends StatefulWidget {
  /// Called when the user chooses to discard changes and leave.
  final VoidCallback onDiscard;

  /// Called when the user chooses to save before continuing.
  /// Should call the save logic and then pop the dialog if successful.
  final Future<void> Function() onSaveAndContinue;

  const UnsavedChangesDialog({
    super.key,
    required this.onDiscard,
    required this.onSaveAndContinue,
  });

  @override
  State<UnsavedChangesDialog> createState() => _UnsavedChangesDialogState();
}

class _UnsavedChangesDialogState extends State<UnsavedChangesDialog> {
  bool _isSaving = false;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Unsaved Changes',
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
                    // Warning icon bubble
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'You have unsaved changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your edits to this form have not been saved yet. '
                      'Would you like to save them before leaving, or discard?',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Info chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14,
                              color: AppColors.primaryBlue.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Discarding cannot be undone. '
                              'Your previous saved data will be restored.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primaryBlue.withValues(alpha: 0.75),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Divider ─────────────────────────────────────
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                child: Divider(height: 1, color: Color(0xFFEEEEF4)),
              ),

              // ── Action buttons ───────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Save & Continue — primary CTA
                    ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              setState(() => _isSaving = true);
                              try {
                                await widget.onSaveAndContinue();
                              } finally {
                                if (mounted) {
                                  setState(() => _isSaving = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        disabledBackgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isSaving
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
                                Icon(Icons.save_outlined, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Save & Continue',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 8),

                    // Discard — secondary
                    OutlinedButton(
                      onPressed: _isSaving ? null : widget.onDiscard,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Discard Changes',
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
    );
  }
}
