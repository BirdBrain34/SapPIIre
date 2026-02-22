import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class SignatureField extends StatelessWidget {
  final List<Offset?>? points;
  final Function(List<Offset?>) onCaptured;
  final String label;

  const SignatureField({
    super.key,
    required this.points,
    required this.onCaptured,
    this.label = "Signature",
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
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
              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: points == null || points!.isEmpty
                ? const Center(child: Text("Tap to sign", style: TextStyle(color: Colors.black54, fontSize: 12)))
                : Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 300, // Matching the internal drawing box width
                        height: 200, // Matching the internal drawing box height
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Digital Signature"),
        backgroundColor: AppColors.primaryBlue,
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: () => setState(() => points.clear())),
          IconButton(icon: const Icon(Icons.check), onPressed: () => Navigator.pop(context, points)),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Sign within the box", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.primaryBlue),
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