import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/form_popup.dart';

class QrScannerScreen extends StatefulWidget {
  final Map<String, dynamic>? transmitData;
  final String? userId;

  const QrScannerScreen({
    super.key,
    this.transmitData,
    this.userId,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  final _supabase = Supabase.instance.client;

  // Prevents multiple detections firing at once
  bool _isProcessing = false;

  // ── After a QR is detected, fetch the form's popup config
  // from form_templates via the session row, then show the
  // popup if popup_enabled = true.
  // Returns true if the user wants to proceed, false to re-scan.
  Future<bool> _handleScannedCode(String sessionId) async {
    // Pause camera while we show the popup
    await controller.stop();

    try {
      // 1. Get the form_type (template_id) from the session row
      final session = await _supabase
          .from('form_submission')
          .select('form_type, template_id')
          .eq('id', sessionId)
          .maybeSingle();

      if (session == null || !mounted) return true;

      // Resolve template_id — prefer explicit column, fall back to form_type
      final templateId =
          (session['template_id'] as String?) ??
          (session['form_type'] as String?);

      if (templateId == null) return true;

      // 2. Fetch popup fields from form_templates
      final template = await _supabase
          .from('form_templates')
          .select('form_name, popup_enabled, popup_subtitle, popup_description')
          .eq('template_id', templateId)
          .maybeSingle();

      if (template == null || !mounted) return true;

      final popupEnabled = (template['popup_enabled'] as bool?) ?? false;

      // 3. If popup is disabled, skip straight to transmit
      if (!popupEnabled) return true;

      // 4. Show the popup
      if (!mounted) return true;
      final proceed = await FormIntroPopupDialog.show(
        context: context,
        formTitle: (template['form_name'] as String?) ?? 'Form',
        subtitle: template['popup_subtitle'] as String?,
        description: template['popup_description'] as String?,
      );

      return proceed;
    } catch (e) {
      debugPrint('Popup fetch error: $e');
      // On any error, silently proceed so the scan still works
      return true;
    }
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label, {
    bool isQr = false,
  }) {
    final isActive = index == 1;
    return InkWell(
      onTap: () {
        if (index == 0 || index == 2) {
          Navigator.pop(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isQr)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  icon,
                  color: AppColors.highlight,
                  size: 24,
                ),
              )
            else
              Icon(
                icon,
                color: isActive ? AppColors.highlight : Colors.white60,
                size: 24,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.highlight : Colors.white60,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData =
        widget.transmitData != null && widget.transmitData!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Scan QR',
            style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (hasData)
            MobileScanner(
              controller: controller,
              onDetect: (capture) async {
                // Guard: ignore if already handling a detection
                if (_isProcessing) return;

                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;

                final String? code = barcodes.first.rawValue;
                if (code == null) return;

                setState(() => _isProcessing = true);
                debugPrint('QR Code Detected: $code');

                // Show popup (if configured for this form).
                // _handleScannedCode stops the camera internally.
                final proceed = await _handleScannedCode(code);

                if (!mounted) return;

                if (proceed) {
                  // User tapped Continue — return the session ID to
                  // ManageInfoScreen so it can transmit the data.
                  Navigator.pop(context, code);
                } else {
                  // User tapped Cancel — restart the camera for re-scan.
                  setState(() => _isProcessing = false);
                  await controller.start();
                }
              },
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'No data selected to transmit.\nPlease go back and select items to share.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),

          // Scan frame overlay
          if (hasData)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

          // "Processing…" overlay shown while fetching popup data
          if (_isProcessing && hasData)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryBlue,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.edit_document, 'Manage Info'),
                _buildNavItem(1, Icons.qr_code_scanner, 'Autofill QR',
                    isQr: true),
                _buildNavItem(2, Icons.history, 'History'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}