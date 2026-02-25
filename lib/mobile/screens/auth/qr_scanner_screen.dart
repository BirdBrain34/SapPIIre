import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sappiire/mobile/widgets/bottom_navbar.dart'; 

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
      bottomNavigationBar: CustomBottomNav(
        currentIndex: 1, 
        onTap: (index) {
          if (index == 0) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}