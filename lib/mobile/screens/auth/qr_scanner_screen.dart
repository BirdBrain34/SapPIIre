import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/qr_scanner_controller.dart';

class QrScannerScreen extends StatefulWidget {
  final Map<String, dynamic>? transmitData;
  final String? userId;
  final String? templateId;
  final String? formName;
  final SupabaseService? supabaseService;

  const QrScannerScreen({
    super.key,
    this.transmitData,
    this.userId,
    this.templateId,
    this.formName,
    this.supabaseService,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  late final QrScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QrScannerController(
      transmitData: widget.transmitData,
      userId: widget.userId,
      templateId: widget.templateId,
      formName: widget.formName,
      supabaseService: widget.supabaseService,
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Attempts to parse the QR code content as JSON with sessionId + templateId.
  /// Returns [true] if valid and template matches (or is legacy plain-text UUID).
  /// Returns [false] if template mismatch is detected.
  Future<bool> _validateQrCode(String rawCode) async {
    try {
      final decoded = jsonDecode(rawCode);
      if (decoded is! Map) return true; // non-JSON fallback to legacy
      final scannedSessionId = decoded['sessionId'] as String?;
      final scannedTemplateId = decoded['templateId'] as String?;

      if (scannedSessionId == null || scannedTemplateId == null) {
        // Malformed JSON QR — treat as legacy and allow
        return true;
      }

      // Template validation
      if (widget.templateId != null && scannedTemplateId != widget.templateId) {
        if (mounted) {
          await _showTemplateMismatchDialog(scannedTemplateId);
        }
        return false;
      }

      return true; // Templates match
    } catch (_) {
      // Not valid JSON — assume legacy QR code (plain session UUID)
      return true;
    }
  }

  Future<void> _handleScannedCode(String rawCode) async {
    // Validate template match from QR content
    final isValid = await _validateQrCode(rawCode);
    if (!isValid) {
      // Template mismatch: re-enable scanner so user can try again
      _controller.isPopping = false;
      if (mounted) {
        await _scannerController.start();
      }
      return;
    }

    // Extract sessionId (from JSON or raw UUID)
    String sessionId;
    try {
      final decoded = jsonDecode(rawCode);
      if (decoded is Map && decoded.containsKey('sessionId')) {
        sessionId = decoded['sessionId'] as String;
      } else {
        sessionId = rawCode; // legacy plain-text UUID
      }
    } catch (_) {
      sessionId = rawCode; // legacy plain-text UUID
    }

    final row = await _controller.fetchPopupConfig();
    if (row != null) {
      final popupEnabled = (row['popup_enabled'] as bool?) ?? false;

      if (popupEnabled && mounted) {
        final proceed = await _showFormIntroDialog(
          formTitle: (row['form_name'] as String?) ??
              widget.formName ??
              'Form',
          subtitle: row['popup_subtitle'] as String?,
          description: row['popup_description'] as String?,
        );

        if (!proceed || !mounted) {
          _controller.isPopping = false;
          await _scannerController.start();
          return;
        }
      }
    }
    await _controller.performTransmission(sessionId);
  }

  /// Shows a dialog alerting the user that the scanned QR is for a different form template.
  Future<void> _showTemplateMismatchDialog(String scannedTemplateId) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 32, color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text(
                'Form Template Mismatch',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This QR code belongs to a different form template than what you currently have selected. Please inform the CSWD staff to switch to the correct form template, then scan again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Scan Again',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _showFormIntroDialog({
    required String formTitle,
    String? subtitle,
    String? description,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.info_outline_rounded,
                      size: 32, color: AppColors.primaryBlue),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                formTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Continue',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 1,
      onTap: (index) {
        if (index == 0 || index == 2) Navigator.pop(context);
      },
      backgroundColor: AppColors.primaryBlue,
      selectedItemColor: AppColors.highlight,
      unselectedItemColor: Colors.white60,
      selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
      type: BottomNavigationBarType.fixed,
      elevation: 10,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.edit_document, size: 24),
          label: 'Manage Info',
        ),
        BottomNavigationBarItem(
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.qr_code_scanner,
                color: AppColors.highlight, size: 22),
          ),
          label: 'Autofill QR',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.history, size: 24),
          label: 'History',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData =
        widget.transmitData != null && widget.transmitData!.isNotEmpty;

    if (_controller.isTransmitting || _controller.transmitDone) {
      return Scaffold(
        backgroundColor: AppColors.primaryBlue,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.transmitDone)
                    Icon(
                      _controller.transmitSuccess
                          ? Icons.check_circle_outline
                          : _controller.sessionExpired
                              ? Icons.timer_off_outlined
                              : Icons.error_outline,
                      size: 80,
                      color: _controller.transmitSuccess
                          ? Colors.green
                          : _controller.sessionExpired
                              ? Colors.orange
                              : Colors.red,
                    )
                  else
                    const SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    _controller.transmitDone
                      ? (_controller.transmitSuccess
                        ? 'Transmission Complete!'
                        : _controller.sessionExpired
                          ? 'QR Session Expired'
                          : 'Transmission Failed')
                        : 'Transmitting...',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _controller.transmitStatus,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  if (_controller.transmitDone) ...[
                    const SizedBox(height: 40),
                    if (_controller.transmitSuccess) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _controller.isFinalized
                              ? () => Navigator.of(context).pop('history')
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _controller.isFinalized
                                ? 'View History ✓'
                                : 'View History',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                        if (!_controller.isFinalized) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Please wait til the CSWD staff finish reviewing your submission',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ] else if (_controller.sessionExpired) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Go Back',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop('history'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('View History',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to Form',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Scan QR', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (hasData)
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) async {
                if (_controller.isPopping) return;
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue;
                  if (code != null) {
                    _controller.isPopping = true;
                    await _scannerController.stop();
                    if (mounted) await _handleScannedCode(code);
                  }
                }
              },
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No data selected to transmit.\nPlease go back and select items to share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
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
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}
