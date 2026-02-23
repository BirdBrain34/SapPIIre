import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:flutter/services.dart';
import 'package:sappiire/models/id_information.dart';

class InfoScannerScreen extends StatefulWidget {
  const InfoScannerScreen({super.key});

  @override
  State<InfoScannerScreen> createState() => _InfoScannerScreenState();
}

class _InfoScannerScreenState extends State<InfoScannerScreen> {
  bool _isProcessing = false;
  IdInformation accumulatedData = IdInformation(
    lastName: '',
    firstName: '',
    middleName: '',
    address: '',
    dateOfBirth: '',
    sex: '',
    bloodType: '',
    maritalStatus: '',
    placeOfBirth: '',
  );

  CameraController? _controller;
  bool _isInitialized = false;
  final TextRecognizer _textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          // ================= STATUS PANEL =================
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Captured:\n"
                "Name: ${accumulatedData.firstName} ${accumulatedData.lastName}\n"
                "Sex: ${accumulatedData.sex.isEmpty ? 'Not Yet' : accumulatedData.sex}\n"
                "Address: ${accumulatedData.address.isNotEmpty ? '✔ Captured' : 'Not Yet'}",
                style:
                    const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),

          // ================= OVERLAY CUTOUT =================
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
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
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 220,
                    width: 350,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Close Button
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close,
                  color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Instruction
          const Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Text(
              "Scan FRONT then flip and scan BACK",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),

          // Scan Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: AppColors.primaryBlue,
                onPressed:
                    _isProcessing ? null : () => _scanImage(),
                child: _isProcessing
                    ? const CircularProgressIndicator(
                        color: Colors.white)
                    : const Icon(Icons.search,
                        color: Colors.white),
              ),
            ),
          ),

          // Confirm Button
          if (accumulatedData.lastName.isNotEmpty)
            Positioned(
              bottom: 30,
              right: 30,
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageInfoScreen(
                        initialData: accumulatedData),
                  ),
                ),
                label: const Text("Confirm Info"),
                icon: const Icon(Icons.check),
                backgroundColor: Colors.green,
              ),
            ),
        ],
      ),
    );
  }

  // ================= OCR LOGIC =================

Future<void> _scanImage() async {
  if (_isProcessing) return;

  try {
    setState(() => _isProcessing = true);

    final XFile imageFile = await _controller!.takePicture();
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final RecognizedText recognizedText =
        await _textRecognizer.processImage(inputImage);

    List<String> lines = recognizedText.blocks
        .expand((b) => b.lines.map((l) => l.text.trim()))
        .where((l) => l.isNotEmpty)
        .toList();

    // ---------------------------
    // Helpers
    // ---------------------------

    bool isJunk(String text) {
      final junk = [
        'republic',
        'pilipinas',
        'identity',
        'card',
        'authority',
        'national',
        'phl',
        'official'
      ];
      return junk.any((j) => text.toLowerCase().contains(j));
    }

    bool isLabel(String text) {
      final l = text.toLowerCase();
      return l.contains('apelyido') ||
          l.contains('surname') ||
          l.contains('pangalan') ||
          l.contains('given') ||
          l.contains('middle') ||
          l.contains('birth') ||
          l.contains('kapanganakan') ||
          l.contains('address') ||
          l.contains('tirahan') ||
          l.contains('sex') ||
          l.contains('kasarian') ||
          l.contains('blood') ||
          l.contains('sibil') ||
          l.contains('marital') ||
          l.contains('lugar') ||
          l.contains('place');
    }

    // Collect multi-line value until next label
    String collectValue(int index) {
      List<String> found = [];

      String originalLine = lines[index];

      // Handle "Sex: FEMALE" or "Birth: Jan 1 1990"
      if (originalLine.contains(':')) {
        String afterColon = originalLine.split(':').last.trim();
        if (afterColon.length > 2 && !isLabel(afterColon)) {
          found.add(afterColon);
        }
      }

      for (int j = index + 1; j < lines.length; j++) {
        if (isLabel(lines[j]) || isJunk(lines[j])) break;
        found.add(lines[j]);
      }

      return found.join(" ").trim();
    }

    // ---------------------------
    // Main Parsing Loop
    // ---------------------------

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String lower = line.toLowerCase();

      // -------- NAMES --------
      if (lower.contains('apelyido') || lower.contains('surname')) {
        accumulatedData.lastName = collectValue(i);
      } 
      else if (lower.contains('pangalan') || lower.contains('given')) {
        accumulatedData.firstName = collectValue(i);
      } 
      else if (lower.contains('middle')) {
        accumulatedData.middleName = collectValue(i);
      }

      // -------- DATE OF BIRTH --------
      if (lower.contains('birth') || lower.contains('kapanganakan')) {
        String rawDob = collectValue(i);

        accumulatedData.dateOfBirth = rawDob
            .replaceAll(RegExp(
                r'Date of Birth|Birth|Petsa|ng|Kapanganakan',
                caseSensitive: false),
                '')
            .trim();
      }

      // -------- ADDRESS --------
      if (lower.contains('Tirahan') || lower.contains('Address')) {
        accumulatedData.address = collectValue(i);
      }

      // -------- BACK SIDE --------
      if (lower.contains('kasarian') || lower.contains('sex')) {
        accumulatedData.sex = collectValue(i);
      } 
      else if (lower.contains('sibil') || lower.contains('marital')) {
        accumulatedData.maritalStatus = collectValue(i);
      } 
      else if (lower.contains('lugar') || lower.contains('place of birth')) {
        accumulatedData.placeOfBirth = collectValue(i);
      }
    }

    setState(() {});
    HapticFeedback.mediumImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Scan complete. Flip the ID if needed."),
        backgroundColor: Colors.blue,
      ),
    );
  } catch (e) {
    debugPrint("Scan Error: $e");
  } finally {
    setState(() => _isProcessing = false);
  }
}
}