import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:sappiire/models/id_information.dart'; // Adjust path based on your folder structure

// -------------------
// Model Class
// -------------------




// -------------------
// Scanner Screen
// -------------------
class InfoScannerScreen extends StatefulWidget {
  const InfoScannerScreen({super.key});

  @override
  State<InfoScannerScreen> createState() => _InfoScannerScreenState();
}

class _InfoScannerScreenState extends State<InfoScannerScreen> {
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
      cameras[0],
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

          // -------------------
          // Overlay with Cutout
          // -------------------
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
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Instruction Text
          const Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Text(
              "Align your ID inside the box",
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
                child: const Icon(Icons.search, color: Colors.white),
                onPressed: () => _scanImage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------
  // Scan Logic
  // -------------------
  Future<void> _scanImage() async {
    try {
      // Capture image
      final XFile imageFile = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      // Flatten OCR lines
      List<String> lines = recognizedText.blocks
          .expand((b) => b.lines.map((l) => l.text.trim()))
          .where((l) => l.isNotEmpty)
          .toList();

      print("OCR LINES: $lines");

      // -------------------
      // Helper Functions
      // -------------------
      bool isLabel(String text) {
        final lower = text.toLowerCase();
        return lower.contains('pangalan') ||
            lower.contains('given') ||
            lower.contains('apelyido') ||
            lower.contains('surname') ||
            lower.contains('middle') ||
            lower.contains('birth') ||
            lower.contains('kapanganakan') ||
            lower.contains('address') ||
            lower.contains('purok') ||
            lower.contains('residence') ||
            lower.contains('/');
      }

      bool isJunk(String text) {
        final junkKeywords = [
          'republic',
          'pilipinas',
          'identity',
          'card',
          'pambansang',
          'authority',
          'official',
          'signature',
          'national',
          'sex'
        ];

        final lower = text.toLowerCase();
        if (text.length < 2 || text.length > 40) return true;
        return junkKeywords.any((junk) => lower.contains(junk));
      }

      bool looksLikeName(String text) {
        return text == text.toUpperCase() &&
            text.length > 2 &&
            !text.contains(RegExp(r'\d'));
      }

      bool looksLikeDate(String text) {
        final numericDate = RegExp(r'\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}');
        final monthNames =
            RegExp(r'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec',
                caseSensitive: false);
        return numericDate.hasMatch(text) || monthNames.hasMatch(text);
      }

      // -------------------
      // Smart Parsing
      // -------------------
      String? extractedLast;
      String? extractedFirst;
      String? extractedMiddle;
      String? extractedAddress;
      String? extractedDob;

      for (int i = 0; i < lines.length; i++) {
        String current = lines[i];
        String lower = current.toLowerCase();

        // LAST NAME
        if (lower.contains('apelyido') ||
            lower.contains('surname') ||
            lower.contains('last name')) {
          extractedLast = lines.skip(i + 1).firstWhere(
                (l) => !isLabel(l) && !isJunk(l) && looksLikeName(l),
                orElse: () => extractedLast ?? '',
              );
        }

        // FIRST NAME
        if (lower.contains('pangalan') || lower.contains('given')) {
          extractedFirst = lines.skip(i + 1).firstWhere(
                (l) => !isLabel(l) && !isJunk(l) && looksLikeName(l),
                orElse: () => extractedFirst ?? '',
              );
        }

        // MIDDLE NAME
        if (lower.contains('middle')) {
          extractedMiddle = lines.skip(i + 1).firstWhere(
                (l) => !isLabel(l) && !isJunk(l) && looksLikeName(l),
                orElse: () => extractedMiddle ?? '',
              );
        }

        // DATE OF BIRTH
        if (lower.contains('birth') ||
            lower.contains('kapanganakan') ||
            lower.contains('date')) {
          extractedDob = lines.skip(i + 1).firstWhere(
                (l) => !isLabel(l) && !isJunk(l) && looksLikeDate(l),
                orElse: () => extractedDob ?? '',
              );
        }

        // ADDRESS
        if (lower.contains('address') ||
            lower.contains('purok') ||
            lower.contains('residence')) {
          extractedAddress = lines.skip(i + 1).firstWhere(
                (l) => !isLabel(l) && !isJunk(l),
                orElse: () => extractedAddress ?? '',
              );
        }
      }

      // Create model
      IdInformation extractedData = IdInformation(
        lastName: extractedLast ?? '',
        firstName: extractedFirst ?? '',
        middleName: extractedMiddle ?? '',
        address: extractedAddress ?? '',
        dateOfBirth: extractedDob ?? '',
      );

      // Haptic feedback on success
      HapticFeedback.mediumImpact();

      // Validate name
      if (!extractedData.hasValidName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Could not detect name. Please align the ID and try again."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Navigate to ManageInfoScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ManageInfoScreen(initialData: extractedData),
        ),
      );
    } catch (e) {
      print("Scan error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to scan ID. Try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
