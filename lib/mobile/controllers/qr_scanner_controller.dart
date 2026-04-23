import 'package:flutter/material.dart';
import 'package:sappiire/services/supabase_service.dart';

class QrScannerController extends ChangeNotifier {
  final Map<String, dynamic>? transmitData;
  final String? userId;
  final String? templateId;
  final String? formName;
  final SupabaseService? supabaseService;

  QrScannerController({
    this.transmitData,
    this.userId,
    this.templateId,
    this.formName,
    this.supabaseService,
  });

  bool isTransmitting = false;
  bool transmitDone = false;
  bool transmitSuccess = false;
  String transmitStatus = 'Securing your data...';
  bool isPopping = false;

  Future<Map<String, dynamic>?> fetchPopupConfig() async {
    if (templateId == null || supabaseService == null) return null;
    try {
      final row = await supabaseService!.fetchTemplatePopupConfig(templateId!);
      return row;
    } catch (e) {
      debugPrint('Popup fetch error: $e');
      return null;
    }
  }

  Future<void> performTransmission(String sessionId) async {

    isTransmitting = true;
    transmitDone = false;
    transmitSuccess = false;
    transmitStatus = 'Encrypting your data with AES-256...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));
    transmitStatus = 'Securing encryption key with RSA...';
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    transmitStatus = 'Transmitting securely to CSWD portal...';
    notifyListeners();

    bool success = false;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      success = await (supabaseService ?? SupabaseService())
          .sendDataToWebSession(
        sessionId,
        transmitData ?? {},
        userId: userId,
      );
    } catch (e) {
      debugPrint('Transmission error: $e');
      success = false;
    }

    isTransmitting = false;
    transmitDone = true;
    transmitSuccess = success;
    transmitStatus = success
        ? 'Your information has been securely transmitted to the CSWD staff portal.'
        : 'Something went wrong during transmission. Please try again.';
    notifyListeners();
  }
}
