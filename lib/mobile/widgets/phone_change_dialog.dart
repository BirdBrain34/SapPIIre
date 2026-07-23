import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/phone_change_controller.dart';

/// Modal flow for changing the signed-in user's phone number.
///
/// Steps: enter new number -> receive SMS OTP -> verify. On success, [show]
/// resolves to the verified phone number string. Any other outcome (cancel,
/// dismiss) resolves to null, meaning "do not change the phone".
class PhoneChangeDialog extends StatefulWidget {
  final String userId;
  final String currentPhone;

  const PhoneChangeDialog({
    super.key,
    required this.userId,
    required this.currentPhone,
  });

  static Future<String?> show({
    required BuildContext context,
    required String userId,
    required String currentPhone,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneChangeDialog(
        userId: userId,
        currentPhone: currentPhone,
      ),
    );
  }

  @override
  State<PhoneChangeDialog> createState() => _PhoneChangeDialogState();
}

class _PhoneChangeDialogState extends State<PhoneChangeDialog> {
  late final PhoneChangeController _ctrl;
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = PhoneChangeController(
      userId: widget.userId,
      currentPhone: widget.currentPhone,
    )..addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _canDismiss =>
      _ctrl.step != PhoneChangeStep.sending &&
      _ctrl.step != PhoneChangeStep.verifying;

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
            child: const Icon(Icons.phone_android_outlined,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Update Phone Number',
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
      case PhoneChangeStep.sending:
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      case PhoneChangeStep.enterPhone:
        return _buildPhoneEntry();
      case PhoneChangeStep.awaitingCode:
      case PhoneChangeStep.verifying:
        return _buildCodeEntry();
      case PhoneChangeStep.verified:
        return const SizedBox(
          height: 100,
          child: Center(
            child: Icon(Icons.check_circle,
                color: AppColors.successGreen, size: 48),
          ),
        );
      case PhoneChangeStep.error:
        return _buildError();
    }
  }

  Widget _buildPhoneEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Enter your new mobile number. We’ll text you a 6-digit code to '
          'confirm it’s yours.',
          style: TextStyle(fontSize: 13, color: Color(0xFF444466), height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
          ],
          decoration: const InputDecoration(
            hintText: '09XXXXXXXXX',
            prefixIcon: Icon(Icons.phone_android_outlined),
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
          onPressed: _phoneCtrl.text.trim().isEmpty
              ? null
              : () => _ctrl.submitPhone(_phoneCtrl.text),
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
    final busy = _ctrl.step == PhoneChangeStep.verifying;
    final canSubmit = !busy && _codeCtrl.text.trim().length == 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter the 6-digit code sent to ${_ctrl.pendingPhone}.',
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
                    Navigator.pop(context, _ctrl.pendingPhone);
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
          onPressed:
              _ctrl.resendCountdown > 0 || busy ? null : _ctrl.resendOtp,
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
            _ctrl.step = PhoneChangeStep.enterPhone;
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
