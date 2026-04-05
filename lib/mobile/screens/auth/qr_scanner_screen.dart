import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/mobile/screens/auth/HistoryScreen.dart';
import 'package:sappiire/constants/app_colors.dart';

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
  final MobileScannerController controller = MobileScannerController();
  bool isPopping = false;

  // Transmission state
  bool _isTransmitting = false;
  bool _transmitDone = false;
  bool _transmitSuccess = false;
  String _transmitStatus = 'Securing your data...';
  String? _scannedSessionId;

  // --- NEW METHODS START ---

  Future<void> _handleScannedCode(String sessionId) async {
    _scannedSessionId = sessionId;
    
    // Show popup if enabled for this form
    if (widget.templateId != null && widget.supabaseService != null) {
      try {
        final row = await widget.supabaseService!
            .fetchTemplatePopupConfig(widget.templateId!);
        final popupEnabled = (row?['popup_enabled'] as bool?) ?? false;

        if (popupEnabled && mounted) {
          final proceed = await _showFormIntroDialog(
            formTitle: (row?['form_name'] as String?) ??
                widget.formName ??
                'Form',
            subtitle: row?['popup_subtitle'] as String?,
            description: row?['popup_description'] as String?,
          );

          if (!proceed || !mounted) {
            isPopping = false;
            await controller.start(); // Resume scanning if they cancel
            return;
          }
        }
      } catch (e) {
        debugPrint('Popup fetch error: $e');
      }
    }
    // Start transmission if popup is disabled or user pressed "Continue"
    await _transmitData(sessionId);
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
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 32,
                  color: AppColors.primaryBlue,
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
                textAlign: TextAlign.center,
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
                  textAlign: TextAlign.center,
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
                      textAlign: TextAlign.center,
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
                          borderRadius: BorderRadius.circular(10),
                        ),
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(color: Colors.white),
                      ),
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

  Future<void> _transmitData(String sessionId) async {
    if (!mounted) return;
    setState(() {
      _isTransmitting = true;
      _transmitStatus = 'Encrypting your data with AES-256...';
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _transmitStatus = 'Securing encryption key with RSA...');
    }
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _transmitStatus = 'Transmitting securely to CSWD portal...');
    }

    bool success = false;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      success = await (widget.supabaseService ?? SupabaseService())
          .sendDataToWebSession(
        sessionId,
        widget.transmitData ?? {},
        userId: widget.userId,
      );
    } catch (e) {
      debugPrint('Transmission error: $e');
      success = false;
    }

    if (mounted) {
      setState(() {
        _isTransmitting = false;
        _transmitDone = true;
        _transmitSuccess = success;
        _transmitStatus = success
            ? 'Your information has been securely transmitted to the CSWD staff portal.'
            : 'Something went wrong during transmission. Please try again.';
      });
    }
  }

  // --- UI COMPONENTS ---



Widget _buildBottomNav() {
  return Container(
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
            _buildNavItem(1, Icons.qr_code_scanner, 'Autofill QR', isQr: true),
            _buildNavItem(2, Icons.history, 'History'),
          ],
        ),
      ),
    ),
  );
}

Widget _buildNavItem(int index, IconData icon, String label,
    {bool isQr = false}) {
  final isActive = index == 1;
  return InkWell(
    onTap: () {
      if (index == 0 || index == 2) Navigator.pop(context);
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
    final bool hasData = widget.transmitData != null && widget.transmitData!.isNotEmpty;

    if (_isTransmitting || _transmitDone) {
      return Scaffold(
        backgroundColor: AppColors.primaryBlue,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_transmitDone)
                    Icon(
                      _transmitSuccess ? Icons.check_circle_outline : Icons.error_outline,
                      size: 80,
                      color: _transmitSuccess ? Colors.green : Colors.red,
                    )
                  else
                    const SizedBox(
                      width: 72, height: 72,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    _transmitDone ? (_transmitSuccess ? 'Transmission Complete!' : 'Transmission Failed') : 'Transmitting...',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(_transmitStatus, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
                  if (_transmitDone) ...[
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => HistoryScreen(userId: widget.userId ?? '')),
                            (route) => route.isFirst,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('View History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to Form', style: TextStyle(color: Colors.white70, fontSize: 14)),
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
        title: const Text('Scan QR', style: TextStyle(color: Colors.white)),
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
                if (isPopping) return;
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue;
                  if (code != null) {
                    isPopping = true;
                    await controller.stop();
                    if (mounted) {
                      await _handleScannedCode(code);
                    }
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
                width: 250, height: 250,
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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}