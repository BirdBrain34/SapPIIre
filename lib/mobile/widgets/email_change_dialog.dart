import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/email_change_controller.dart';

/// Modal flow for changing the signed-in user's email.
///
/// Steps: enter new email -> confirmation code sent to the new inbox ->
/// verify. On success, [show] resolves to the verified email string. Any other
/// outcome (cancel, dismiss) resolves to null, meaning "do not change email".
class EmailChangeDialog extends StatefulWidget {
  final String currentEmail;

  const EmailChangeDialog({super.key, required this.currentEmail});

  static Future<String?> show({
    required BuildContext context,
    required String currentEmail,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailChangeDialog(currentEmail: currentEmail),
    );
  }

  @override
  State<EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<EmailChangeDialog> {
  late final EmailChangeController _ctrl;
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = EmailChangeController(currentEmail: widget.currentEmail)
      ..addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _canDismiss =>
      _ctrl.step != EmailChangeStep.sending &&
      _ctrl.step != EmailChangeStep.verifying;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Padding(padding: const EdgeInsets.all(24), child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.email_outlined,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Update Email',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_canDismiss)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_ctrl.step) {
      case EmailChangeStep.sending:
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      case EmailChangeStep.enterEmail:
        return _buildEmailEntry();
      case EmailChangeStep.awaitingCode:
      case EmailChangeStep.verifying:
        return _buildCodeEntry();
      case EmailChangeStep.verified:
        return const SizedBox(
          height: 100,
          child: Center(
            child: Icon(Icons.check_circle,
                color: AppColors.successGreen, size: 48),
          ),
        );
      case EmailChangeStep.error:
        return _buildError();
    }
  }

  Widget _buildEmailEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Enter your new email address. We’ll send a 6-digit confirmation '
          'code to that inbox.',
          style: TextStyle(fontSize: 13, color: Color(0xFF444466), height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_ctrl.errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(_ctrl.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _emailCtrl.text.trim().isEmpty
              ? null
              : () => _ctrl.submitEmail(_emailCtrl.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Send Code', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildCodeEntry() {
    final busy = _ctrl.step == EmailChangeStep.verifying;
    final canSubmit = !busy && _codeCtrl.text.trim().length == 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter the 6-digit code sent to ${_ctrl.pendingEmail}.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF444466)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          enabled: !busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          decoration: const InputDecoration(counterText: '', hintText: '000000'),
          onChanged: (_) => setState(() {}),
        ),
        if (_ctrl.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(_ctrl.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: canSubmit
              ? () async {
                  final ok = await _ctrl.verifyOtp(_codeCtrl.text);
                  if (ok && mounted) {
                    Navigator.pop(context, _ctrl.pendingEmail);
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Verify', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _ctrl.resendCountdown > 0 || busy ? null : _ctrl.resend,
          child: Text(_ctrl.resendCountdown > 0
              ? 'Resend code in ${_ctrl.resendCountdown}s'
              : 'Resend code'),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_ctrl.errorMessage ?? 'Something went wrong.',
            style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () {
            _ctrl.step = EmailChangeStep.enterEmail;
            _ctrl.errorMessage = null;
            setState(() {});
          },
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Try Again', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
