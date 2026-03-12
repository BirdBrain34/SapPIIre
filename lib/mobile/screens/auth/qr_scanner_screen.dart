import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart'; 
import 'package:sappiire/constants/app_colors.dart';

class QrScannerScreen extends StatefulWidget {
  // Add these parameters to receive the data from ManageInfoScreen
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
  bool isPopping = false;

  Widget _buildNavItem(int index, IconData icon, String label, {bool isQr = false}) {
  // QR tab (index 1) is always active since we're on the scanner
  final isActive = index == 1;
  return InkWell(
    onTap: () {
      if (index == 0 || index == 2) {
        // Go back to ManageInfoScreen on the correct tab
        Navigator.pop(context);
      }
      // index == 1 does nothing (already here)
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
    // Check if there is actually data to transmit
    final bool hasData = widget.transmitData != null && widget.transmitData!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Scan QR", style: TextStyle(color: Colors.white)),
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
            onDetect: (capture) async { // Added async
              if (isPopping) return; 
              
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) {
                  isPopping = true; 
                  debugPrint('QR Code Detected: $code');
                  
                  // STOP THE CAMERA FIRST
                  await controller.stop(); 
                  
                  if (mounted) {
                    Navigator.pop(context, code); 
                  }
                }
              }
            },
            )
          else
            // Error message if user forgot to check boxes
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "No data selected to transmit.\nPlease go back and select items to share.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),

          // Blueprint Overlay (Only show if we are actually scanning)
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
                _buildNavItem(1, Icons.qr_code_scanner, 'Autofill QR', isQr: true),
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