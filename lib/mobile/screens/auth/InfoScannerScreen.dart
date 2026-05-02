import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/info_scanner_controller.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/mobile/utils/snackbar_utils.dart';

class InfoScannerScreen extends StatefulWidget {
  /// If true, tapping Confirm returns IdInformation to the caller
  /// instead of saving to Supabase (used during signup flow).
  final bool returnOnly;

  const InfoScannerScreen({super.key, this.returnOnly = false});

  @override
  State<InfoScannerScreen> createState() => _InfoScannerScreenState();
}

class _InfoScannerScreenState extends State<InfoScannerScreen> {
  late final InfoScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = InfoScannerController();
    _controller.addListener(() => setState(() {}));
    _controller.setupCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onScanPressed() async {
    try {
      await _controller.scanImage();
      if (_controller.backScanned) {
        SnackbarUtils.showSuccess(context, 'Back scanned — review and confirm');
      } else if (_controller.frontScanned) {
        SnackbarUtils.showCustom(
          context,
          'Front scanned — now flip to the back',
          Colors.blue,
        );
      }
    } catch (e) {
      SnackbarUtils.showError(context, 'Scan failed. Try again.');
    }
  }

  Future<void> _onConfirmPressed() async {
    if (widget.returnOnly) {
      Navigator.pop(context, _controller.data);
      return;
    }

    try {
      await _controller.saveToSupabase();
      SnackbarUtils.showSuccess(context, 'Information saved!');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      final userId = _controller.currentUserId;
      if (userId == null) {
        SnackbarUtils.showError(context, 'Not logged in.');
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ManageInfoScreen(userId: userId),
        ),
      );

    } catch (e) {
      SnackbarUtils.showError(context, 'Save failed: $e');
    }
  }

  void _onRescanFront() {
    setState(() {
      _controller.frontScanned = false;
      _controller.data.lastName = '';
      _controller.data.firstName = '';
      _controller.data.middleName = '';
      _controller.data.dateOfBirth = '';
      _controller.data.address = '';
    });
  }

  void _onRescanBack() {
    setState(() {
      _controller.backScanned = false;
      _controller.data.sex = '';
      _controller.data.bloodType = '';
      _controller.data.maritalStatus = '';
      _controller.data.placeOfBirth = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isInitialized || _controller.cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final String stepLabel = !_controller.frontScanned
        ? 'Step 1 of 2 — Scan FRONT of ID'
        : !_controller.backScanned
            ? 'Step 2 of 2 — Scan BACK of ID'
            : 'All done! Review below.';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller.cameraController!),
          _buildOverlayCutout(),

          // Close button
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Step label
          Positioned(
            top: 52,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  stepLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          // Data summary
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: _buildDataSummary(),
          ),

          // Instruction
          Positioned(
            bottom: 110,
            left: 16,
            right: 16,
            child: Text(
              !_controller.frontScanned
                  ? 'Point camera at the FRONT of your Philippine National ID'
                  : !_controller.backScanned
                      ? 'Now flip the ID and scan the BACK'
                      : 'Tap Confirm to save your information',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),

          // Scan button
          if (!_controller.backScanned)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _controller.isProcessing ? null : _onScanPressed,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryBlue,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: _controller.isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
              ),
            ),

          // Re-scan Front
          if (_controller.frontScanned && !_controller.backScanned)
            Positioned(
              bottom: 110,
              left: 32,
              right: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text(
                  'Re-scan Front',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: _onRescanFront,
              ),
            ),

          // Re-scan Back
          if (_controller.backScanned)
            Positioned(
              bottom: 92,
              left: 32,
              right: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text(
                  'Re-scan Back',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: _onRescanBack,
              ),
            ),

          // Confirm button
          if (_controller.backScanned)
            Positioned(
              bottom: 28,
              left: 32,
              right: 32,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Confirm & Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _onConfirmPressed,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayCutout() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.55),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              height: 210,
              width: 340,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSummary() {
    final rows = [
      ['Last Name', _controller.data.lastName],
      ['Given Name(s)', _controller.data.firstName],
      ['Middle Name', _controller.data.middleName],
      ['Date of Birth', _controller.data.dateOfBirth],
      ['Address', _controller.data.address],
      ['Sex', _controller.data.sex],
      ['Blood Type', _controller.data.bloodType],
      ['Marital Status', _controller.data.maritalStatus],
      ['Place of Birth', _controller.data.placeOfBirth],
    ].where((r) => r[1].isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    children: [
                      TextSpan(
                        text: '${r[0]}: ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(text: r[1]),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
