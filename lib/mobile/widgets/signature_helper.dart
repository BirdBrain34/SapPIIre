import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';

// Reusable signature helper for converting signature points to/from base64
// Usage: Call SignatureHelper.convertToBase64() before saving to database
class SignatureHelper {
  // Convert signature points to base64 PNG string for database storage
  static Future<String?> convertToBase64(List<Offset?> points) async {
    if (points.isEmpty) return null;
    
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Draw white background (300x200 matches SignatureDialog size)
      final paint = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 200), paint);
      
      // Draw signature strokes
      final signaturePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      
      for (int i = 0; i < points.length - 1; i++) {
        if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i]!, points[i + 1]!, signaturePaint);
        }
      }
      
      // Convert to PNG image
      final picture = recorder.endRecording();
      final img = await picture.toImage(300, 200);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) return null;
      
      final bytes = byteData.buffer.asUint8List();
      final base64String = base64Encode(bytes);
      
      return 'data:image/png;base64,$base64String';
    } catch (e) {
      debugPrint('Signature conversion error: $e');
      return null;
    }
  }
}
