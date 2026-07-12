import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/services/supabase_service.dart';

/// Coordinates QR transmission status updates and popup metadata lookup.
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
  bool sessionExpired = false;
  String transmitStatus = 'Securing your data...';
  bool isPopping = false;
  bool isFinalized = false;
  bool isPolling = false;
  Timer? _pollingTimer;
  String? _pendingSessionId;

  Future<Map<String, dynamic>?> fetchPopupConfig() async {
    if (templateId == null || supabaseService == null) return null;
    try {
      final row = await supabaseService!.fetchTemplatePopupConfig(templateId!);
      return row;
    } catch (e) {
      debugPrint('[QrScannerController/fetchPopupConfig] Error: $e');
      return null;
    }
  }

  Future<void> performTransmission(String sessionId) async {
    isTransmitting = true;
    transmitDone = false;
    transmitSuccess = false;
    sessionExpired = false;
    transmitStatus = 'Encrypting your data with AES-256...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));
    transmitStatus = 'Securing encryption key with RSA...';
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    transmitStatus = 'Transmitting securely to CSWD portal...';
    notifyListeners();

    String result = 'error';
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      result = await (supabaseService ?? SupabaseService())
          .sendDataToWebSession(
        sessionId,
        transmitData ?? {},
        userId: userId,
      );
    } catch (e) {
      debugPrint('[QrScannerController/performTransmission] Error: $e');
    }

    isTransmitting = false;
    transmitDone = true;
    sessionExpired = result == 'expired';
    transmitSuccess = result == 'ok';
    transmitStatus = result == 'ok'
        ? 'Your information has been securely transmitted to the CSWD staff portal.'
        : result == 'expired'
            ? 'This QR session has expired. Please ask the CSWD staff to generate a new QR code.'
            : 'Something went wrong during transmission. Please try again.';

    if (result == 'ok') {
      startFinalizationPolling(sessionId);
    } else {
      notifyListeners();
    }
  }

  void startFinalizationPolling(String sessionId) {
    _pendingSessionId = sessionId;
    isFinalized = false;
    isPolling = true;
    notifyListeners();

    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(
      const Duration(seconds: 4),
      (timer) async {
        if (_pendingSessionId == null) {
          timer.cancel();
          isPolling = false;
          notifyListeners();
          return;
        }

        final finalized = await (supabaseService ?? SupabaseService())
            .isSessionFinalized(_pendingSessionId!);

        if (finalized) {
          timer.cancel();
          isPolling = false;
          isFinalized = true;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
