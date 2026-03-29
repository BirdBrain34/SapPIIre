// terms_and_conditions_dialog.dart
// Reusable T&C popup modeled after FormIntroPopupDialog.
// Place at: lib/mobile/widgets/terms_and_conditions_dialog.dart

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class TermsAndConditionsDialog extends StatelessWidget {
  /// If true, shows only "I Understand" (read-only mode from ProfileScreen).
  /// If false, shows "Decline" + "I Agree & Proceed" (first-time acceptance).
  final bool readOnly;

  const TermsAndConditionsDialog({
    super.key,
    this.readOnly = false,
  });

  /// Show T&C for first-time acceptance.
  /// Returns true if user agreed, false/null if declined.
  static Future<bool> showForAcceptance(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TermsAndConditionsDialog(readOnly: false),
    );
    return result == true;
  }

  /// Show T&C in read-only mode (from ProfileScreen settings).
  static Future<void> showForReading(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TermsAndConditionsDialog(readOnly: true),
    );
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
          // ── Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Privacy & Terms',
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
                const SizedBox(height: 8),
                Text(
                  'Republic Act No. 10173 — Data Privacy Act of 2012',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable content ───────────────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _SectionTitle('1. Collection of Personal Information'),
                    _SectionBody(
                      'SapPIIre collects personal information — including your '
                      'full name, date of birth, address, contact number, and '
                      'email address — solely for the purpose of pre-filling '
                      'government and institutional forms on your behalf. '
                      'Collection is done with your informed consent, in '
                      'accordance with the Data Privacy Act of 2012 (R.A. 10173).',
                    ),
                    SizedBox(height: 12),
                    _SectionTitle('2. Purpose of Data Use'),
                    _SectionBody(
                      'Your personal data is used exclusively to autofill '
                      'designated forms within the SapPIIre system. We do not '
                      'use your data for marketing, profiling, or any purpose '
                      'beyond what is necessary for form autofill.',
                    ),
                    SizedBox(height: 12),
                    _SectionTitle('3. Data Sharing'),
                    _SectionBody(
                      'SapPIIre does not sell, trade, or share your personal '
                      'information with third parties without your explicit '
                      'consent, except when required by law or by authorized '
                      'government agencies.',
                    ),
                    SizedBox(height: 12),
                    _SectionTitle('4. Data Security'),
                    _SectionBody(
                      'We implement reasonable technical and organizational '
                      'measures to protect your personal data against '
                      'unauthorized access, disclosure, alteration, or '
                      'destruction, consistent with the standards set by the '
                      'National Privacy Commission (NPC).',
                    ),
                    SizedBox(height: 12),
                    _SectionTitle('5. Your Rights as a Data Subject'),
                    _SectionBody(
                      'Under R.A. 10173, you have the right to: be informed '
                      'of how your data is processed; access your personal '
                      'data; correct inaccurate data; object to processing; '
                      'erasure or blocking of data; and file a complaint with '
                      'the NPC if your rights are violated.',
                    ),
                    SizedBox(height: 12),
                    _SectionTitle('6. Consent'),
                    _SectionBody(
                      'By proceeding, you acknowledge that you have read and '
                      'understood this privacy notice and consent to the '
                      'collection and use of your personal information as '
                      'described above, in compliance with the Data Privacy '
                      'Act of 2012.',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Divider ──────────────────────────────────────────
          const Divider(height: 1, color: Color(0xFFEEEEF4)),

          // ── Action buttons ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: readOnly
                ? _buildReadOnlyButton(context)
                : _buildAcceptanceButtons(context),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'I Understand',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAcceptanceButtons(BuildContext context) {
    return Row(
      children: [
        // Decline
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
              'Decline',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Agree & Proceed
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
                  'Agree & Proceed',
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
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final String text;
  const _SectionBody(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0xFF444466),
        height: 1.6,
      ),
    );
  }
}