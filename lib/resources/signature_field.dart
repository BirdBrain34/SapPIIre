import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'dart:convert';

class SignatureField extends StatelessWidget {
  final List<Offset?>? points;
  final Function(List<Offset?>) onCaptured;
  final String label;
  final String? signatureImageBase64;
  final Color labelColor;
  
  // ADD THESE TWO PROPERTIES
  final bool isChecked;
  final ValueChanged<bool?> onCheckboxChanged;

  const SignatureField({
    super.key,
    required this.points,
    required this.onCaptured,
    required this.isChecked,          // Added
    required this.onCheckboxChanged,   // Added
    this.label = "Signature",
    this.signatureImageBase64,
    this.labelColor = AppColors.primaryBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WRAP LABEL IN A ROW TO ADD THE CHECKBOX
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Checkbox(
              value: isChecked,
              onChanged: onCheckboxChanged,
              activeColor: AppColors.primaryBlue,
              side: const BorderSide(color: AppColors.primaryBlue, width: 2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            final List<Offset?>? result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SignatureDialog(initialPoints: points),
              ),
            );
            if (result != null) onCaptured(result);
          },
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: points == null || points!.isEmpty
                ? (signatureImageBase64 != null
                    ? Image.memory(
                        base64Decode(signatureImageBase64!.split(',').last),
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: Text("Tap to sign",
                            style: TextStyle(color: Colors.black54, fontSize: 12))))
                : Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 300,
                        height: 200,
                        child: CustomPaint(painter: SignaturePainter(points!)),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// --- Internal Dialog ---
class SignatureDialog extends StatefulWidget {
  final List<Offset?>? initialPoints;
  const SignatureDialog({super.key, this.initialPoints});

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  late List<Offset?> points;

  @override
  void initState() {
    super.initState();
    points = widget.initialPoints != null ? List.from(widget.initialPoints!) : [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 3. Changed background to match your app theme
      backgroundColor: AppColors.primaryBlue,
      appBar: AppBar(
        title: const Text("Digital Signature"),
        backgroundColor: Colors.transparent, // Made transparent for a cleaner look
        elevation: 0,
        // 4. Force back arrow and buttons to white
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white), 
            onPressed: () => setState(() => points.clear())
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white), 
            onPressed: () => Navigator.pop(context, points)
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 5. Changed instruction text to white
            const Text(
              "Sign within the box", 
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)
            ),
            const SizedBox(height: 20),
            Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: GestureDetector(
                onPanUpdate: (details) => setState(() => points.add(details.localPosition)),
                onPanEnd: (_) => points.add(null),
                child: CustomPaint(painter: SignaturePainter(points), size: Size.infinite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Internal Painter ---
class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = Colors.black..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) canvas.drawLine(points[i]!, points[i + 1]!, paint);
    }
  }
  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}