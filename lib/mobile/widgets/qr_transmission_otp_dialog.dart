import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/qr_transmission_otp_controller.dart';

/// Modal "confirm it's you" challenge shown after a QR scan passes template
/// validation and before performTransmission() runs.
///
/// Returns true only if the OTP was verified. Any other result (including a
/// null Future) means: do not transmit.
class QrTransmissionOtpDialog extends StatefulWidget {
  final String userId;
  final String sessionId;

  const QrTransmissionOtpDialog({
    super.key,
    required this.userId,
    required this.sessionId,
  });

  static Future<bool> show({
    required BuildContext context,
    required String userId,
    required String sessionId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrTransmissionOtpDialog(
        userId: userId,
        sessionId: sessionId,
      ),
    );
    return result == true;
  }

  @override
  State<QrTransmissionOtpDialog> createState() =>
      _QrTransmissionOtpDialogState();
}

class _QrTransmissionOtpDialogState extends State<QrTransmissionOtpDialog> {
  late final QrTransmissionOtpController _ctrl;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = QrTransmissionOtpController(
      userId: widget.userId,
      sessionId: widget.sessionId,
    )..addListener(_onCtrlChanged);
    _ctrl.loadAccountChannels();
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _canDismiss =>
      _ctrl.step != OtpStep.sending && _ctrl.step != OtpStep.verifying;

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
            child: const Icon(Icons.verified_user_outlined,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Verify It's You",
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
              onPressed: () => Navigator.pop(context, false),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_ctrl.step) {
      case OtpStep.loadingAccount:
      case OtpStep.sending:
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      case OtpStep.selectChannel:
        return _buildChannelPicker();
      case OtpStep.awaitingCode:
      case OtpStep.verifying:
        return _buildCodeEntry();
      case OtpStep.verified:
        return const SizedBox(
          height: 100,
          child: Center(
            child: Icon(Icons.check_circle,
                color: AppColors.successGreen, size: 48),
          ),
        );
      case OtpStep.error:
        return _buildError();
    }
  }

  Widget _buildChannelPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "For your security, we need to confirm it's really you before "
          "sending your information. Where should we send your code?",
          style: TextStyle(fontSize: 13, color: Color(0xFF444466), height: 1.5),
        ),
        const SizedBox(height: 16),
        if (_ctrl.registeredEmail?.isNotEmpty == true)
          _channelTile(
            icon: Icons.email_outlined,
            label: 'Email',
            subtitle: _ctrl.registeredEmail!,
            onTap: () => _ctrl.selectChannel(OtpChannel.email),
          ),
        if (_ctrl.registeredEmail?.isNotEmpty == true &&
            _ctrl.registeredPhone?.isNotEmpty == true)
          const SizedBox(height: 8),
        if (_ctrl.registeredPhone?.isNotEmpty == true)
          _channelTile(
            icon: Icons.sms_outlined,
            label: 'SMS',
            subtitle: _ctrl.registeredPhone!,
            onTap: () => _ctrl.selectChannel(OtpChannel.phone),
          ),
      ],
    );
  }

  Widget _channelTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDEE)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeEntry() {
    final busy = _ctrl.step == OtpStep.verifying;
    final canSubmit = !busy && _codeCtrl.text.trim().length == 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter the 6-digit code sent to ${_ctrl.maskedDestination}.',
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
                  if (ok && mounted) Navigator.pop(context, true);
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
          onPressed: _ctrl.resendCountdown > 0 || busy ? null : _ctrl.sendOtp,
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
          onPressed: () => _ctrl.loadAccountChannels(),
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child:
              const Text('Try Again', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}