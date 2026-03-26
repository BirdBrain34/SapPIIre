// form_intro_popup_dialog.dart
// Shown on mobile (ManageInfoScreen) before the user proceeds to
// scan the QR code, when the selected form has popup_enabled = true.
//
// Place this file at:
//   lib/mobile/widgets/form_intro_popup_dialog.dart

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class FormIntroPopupDialog extends StatelessWidget {
  final String formTitle;
  final String? subtitle;
  final String? description;

  const FormIntroPopupDialog({
    super.key,
    required this.formTitle,
    this.subtitle,
    this.description,
  });

  /// Shows the dialog and returns true if the user tapped Continue,
  /// false / null if they tapped Cancel or dismissed.
  static Future<bool> show({
    required BuildContext context,
    required String formTitle,
    String? subtitle,
    String? description,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FormIntroPopupDialog(
        formTitle: formTitle,
        subtitle: subtitle,
        description: description,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      backgroundColor: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        formTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!.trim(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Scrollable description ─────────────────────────
          if (description != null && description!.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    description!.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF444466),
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 16),

          // ── Divider ────────────────────────────────────────
          const Divider(height: 1, color: Color(0xFFEEEEF4)),

          // ── Action buttons ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                // Cancel
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: Color(0xFFDDDDEE)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                ),
                const SizedBox(width: 12),
                // Continue
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
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