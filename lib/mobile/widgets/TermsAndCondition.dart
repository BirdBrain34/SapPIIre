// lib/mobile/widgets/terms_and_conditions_dialog.dart
//
// Two modes:
//  • showForAcceptance() — new-account flow (non-dismissible)
//      – User must scroll to the bottom of the T&C content to unlock the checkbox.
//      – User must tick the checkbox to unlock the "Agree & Proceed" button.
//      – "Decline" is always available.
//  • showForReading()    — read-only from ProfileScreen (dismissible, "I Understand" only)

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class TermsAndConditionsDialog extends StatefulWidget {
  /// If true, shows only "I Understand" (read-only mode from ProfileScreen).
  /// If false, shows the full acceptance flow with checkbox + locked button.
  final bool readOnly;

  const TermsAndConditionsDialog({
    super.key,
    this.readOnly = false,
  });

  // ── Static helpers ────────────────────────────────────────────────────────

  /// Show T&C for first-time acceptance (non-dismissible).
  /// Returns true if user agreed, false/null if declined.
  static Future<bool> showForAcceptance(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TermsAndConditionsDialog(readOnly: false),
    );
    return result == true;
  }

  /// Show T&C in read-only mode (dismissible, from ProfileScreen settings).
  static Future<void> showForReading(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TermsAndConditionsDialog(readOnly: true),
    );
  }

  @override
  State<TermsAndConditionsDialog> createState() =>
      _TermsAndConditionsDialogState();
}

class _TermsAndConditionsDialogState extends State<TermsAndConditionsDialog> {
  final ScrollController _scrollController = ScrollController();

  /// True once the user has scrolled to (or past) the bottom of the content.
  bool _hasScrolledToBottom = false;

  /// True once the user ticks the acknowledgement checkbox.
  bool _hasChecked = false;

  /// The "Agree & Proceed" button is enabled only when both conditions are met.
  bool get _canProceed => _hasScrolledToBottom && _hasChecked;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasScrolledToBottom) return; // already unlocked — no need to recheck
    final pos = _scrollController.position;
    // Consider "bottom" when within 8 px of the max scroll extent.
    if (pos.pixels >= pos.maxScrollExtent - 8) {
      setState(() => _hasScrolledToBottom = true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Cap the dialog to 92% of screen height so it never overflows on any
    // phone, including compact devices. The Flexible content area absorbs
    // whatever space is left after the fixed header, hint, and buttons.
    final maxHeight = MediaQuery.of(context).size.height * 0.92;

    return PopScope(
      canPop: widget.readOnly,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Reduced vertical inset gives the dialog more room on short screens.
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────
              _buildHeader(),

              // ── Scrollable T&C content — flexes to fill remaining height ──
              Flexible(child: _buildScrollableContent()),

              // ── Scroll hint ────────────────────────────────────
              if (!widget.readOnly) _buildScrollHint(),

              // ── Divider ────────────────────────────────────────
              const Divider(height: 1, color: Color(0xFFEEEEF4)),

              // ── Checkbox + buttons ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: widget.readOnly
                    ? _buildReadOnlyButton()
                    : _buildAcceptanceSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
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
          // Progress hint for acceptance mode only
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            _buildReadProgress(),
          ],
        ],
      ),
    );
  }

  /// Small step-indicator so the user knows what's left to do.
  Widget _buildReadProgress() {
    return Row(
      children: [
        _ProgressStep(
          icon: Icons.menu_book_outlined,
          label: 'Read',
          done: _hasScrolledToBottom,
        ),
        _buildProgressConnector(done: _hasScrolledToBottom),
        _ProgressStep(
          icon: Icons.check_box_outlined,
          label: 'Agree',
          done: _hasChecked,
        ),
        _buildProgressConnector(done: _hasChecked),
        _ProgressStep(
          icon: Icons.lock_open_outlined,
          label: 'Proceed',
          done: _canProceed,
        ),
      ],
    );
  }

  Widget _buildProgressConnector({required bool done}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: done
              ? Colors.greenAccent.withOpacity(0.8)
              : Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Scrollable content ────────────────────────────────────────────────────

  Widget _buildScrollableContent() {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
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
    );
  }

  // ── Scroll hint strip ─────────────────────────────────────────────────────

  Widget _buildScrollHint() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _hasScrolledToBottom
          // Once scrolled: show a compact "all read" confirmation
          ? Container(
              key: const ValueKey('done'),
              color: Colors.green.shade50,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'You\'ve read the full terms.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          // Before scrolling: animated bounce arrow prompting to scroll down
          : Container(
              key: const ValueKey('hint'),
              color: const Color(0xFFF0F4FF),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const _BouncingArrow(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please scroll down and read all terms before continuing.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryBlue.withOpacity(0.8),
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Acceptance section (checkbox + buttons) ───────────────────────────────

  Widget _buildAcceptanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Checkbox row ─────────────────────────────────────
        GestureDetector(
          // Only tappable after reading
          onTap: _hasScrolledToBottom
              ? () => setState(() => _hasChecked = !_hasChecked)
              : () => _showMustReadSnackbar(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hasChecked
                  ? Colors.green.shade50
                  : _hasScrolledToBottom
                      ? const Color(0xFFF5F5FA)
                      : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hasChecked
                    ? Colors.green.shade300
                    : _hasScrolledToBottom
                        ? const Color(0xFFDDDDEE)
                        : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Checkbox visual
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _hasChecked
                        ? Colors.green.shade500
                        : _hasScrolledToBottom
                            ? Colors.white
                            : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _hasChecked
                          ? Colors.green.shade500
                          : _hasScrolledToBottom
                              ? const Color(0xFFBBBBCC)
                              : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: _hasChecked
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16)
                      : _hasScrolledToBottom
                          ? null
                          : const Icon(Icons.lock_outline,
                              color: Colors.white, size: 13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I have read and agree to the Privacy & Terms of SapPIIre in accordance with R.A. 10173.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: _hasScrolledToBottom
                          ? const Color(0xFF1A1A2E)
                          : Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Lock hint label shown when not yet scrolled to bottom
        if (!_hasScrolledToBottom) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 11, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                'Scroll to the bottom to unlock this checkbox',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],

        const SizedBox(height: 10),

        // ── Buttons ──────────────────────────────────────────
        Row(
          children: [
            // Decline — always available
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: const BorderSide(color: Color(0xFFDDDDEE)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
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

            // Agree & Proceed — locked until checkbox ticked
            Expanded(
              flex: 2,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _canProceed ? 1.0 : 0.45,
                child: ElevatedButton(
                  onPressed: _canProceed
                      ? () => Navigator.pop(context, true)
                      : () => _showCannotProceedHint(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canProceed
                        ? AppColors.primaryBlue
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    elevation: _canProceed ? 0 : 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _canProceed
                            ? Icons.arrow_forward_rounded
                            : Icons.lock_outline,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _canProceed ? 'Agree & Proceed' : 'Locked',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Read-only button ──────────────────────────────────────────────────────

  Widget _buildReadOnlyButton() {
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showMustReadSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Please scroll down and read the full terms first.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showCannotProceedHint() {
    if (!_hasScrolledToBottom) {
      _showMustReadSnackbar();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_box_outline_blank,
                color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Please tick the checkbox to confirm you\'ve read and agree.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Bouncing down-arrow animation ──────────────────────────────────────────────

class _BouncingArrow extends StatefulWidget {
  const _BouncingArrow();

  @override
  State<_BouncingArrow> createState() => _BouncingArrowState();
}

class _BouncingArrowState extends State<_BouncingArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: AppColors.primaryBlue.withOpacity(0.7),
        ),
      ),
    );
  }
}

// ── Step indicator widget ─────────────────────────────────────────────────────

class _ProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;

  const _ProgressStep({
    required this.icon,
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: done
                ? Colors.greenAccent.withOpacity(0.25)
                : Colors.white.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: done
                  ? Colors.greenAccent.withOpacity(0.8)
                  : Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Icon(
            done ? Icons.check_rounded : icon,
            color: done ? Colors.greenAccent : Colors.white.withOpacity(0.6),
            size: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: done
                ? Colors.greenAccent.withOpacity(0.9)
                : Colors.white.withOpacity(0.55),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ── Section helpers ───────────────────────────────────────────────────────────

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