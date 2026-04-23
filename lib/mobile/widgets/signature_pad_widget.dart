import 'dart:convert';

import 'package:flutter/material.dart';

class SignaturePadWidget extends StatelessWidget {
  final String? signatureBase64;
  final bool hasExistingSignature;
  final List<Offset?> signaturePoints;
  final VoidCallback onClearExisting;
  final VoidCallback onClearDrawing;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  const SignaturePadWidget({
    super.key,
    this.signatureBase64,
    required this.hasExistingSignature,
    required this.signaturePoints,
    required this.onClearExisting,
    required this.onClearDrawing,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  Widget _renderSignature(String sig) {
    try {
      final b64 = sig.contains(',') ? sig.split(',').last : sig;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(base64Decode(b64), fit: BoxFit.contain),
      );
    } catch (_) {
      return const Center(child: Text('Invalid signature', style: TextStyle(color: Colors.black38)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          if (hasExistingSignature && signatureBase64 != null) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saved Signature', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEEEEF5)),
                      color: const Color(0xFFF9F9FC),
                    ),
                    child: _renderSignature(signatureBase64!),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onClearExisting,
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.red),
                    label: const Text('Clear & Re-draw', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Draw your signature:', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDDDDEE)),
                    ),
                    child: GestureDetector(
                      onPanStart: (d) => onPanStart(d.localPosition),
                      onPanUpdate: (d) => onPanUpdate(d.localPosition),
                      onPanEnd: (_) => onPanEnd(),
                      child: CustomPaint(
                        painter: SignaturePainter(signaturePoints),
                        child: Container(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Draw above', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      const Spacer(),
                      if (signaturePoints.isNotEmpty)
                        TextButton(
                          onPressed: onClearDrawing,
                          child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) => true;
}
