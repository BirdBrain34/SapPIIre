import 'package:flutter/material.dart';
import 'package:sappiire/services/supabase_service.dart';

class LoginController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  final TextEditingController identifierCtrl = TextEditingController();
  final TextEditingController passwordCtrl = TextEditingController();

  bool isLoading = false;
  bool showPassword = false;

  void togglePasswordVisibility() {
    showPassword = !showPassword;
    notifyListeners();
  }

  Future<Map<String, dynamic>> login() async {
    final id = identifierCtrl.text.trim();
    final pw = passwordCtrl.text;
    if (id.isEmpty || pw.isEmpty) {
      return {'success': false, 'message': 'Please enter your username/email/phone and password'};
    }

    isLoading = true;
    notifyListeners();

    try {
      final result = await _supabaseService.login(
        username: id,
        password: pw,
      );

      isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return {'success': false, 'message': 'Connection error. Please check your internet.'};
    }
  }

  @override
  void dispose() {
    identifierCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }
}
