import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';


class ProfileController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final FormTemplateService _templateService = FormTemplateService();
  final FieldValueService _fieldValueService = FieldValueService();
  final String userId;

  FormTemplate? activeTemplate;
  bool isLoading = true;
  bool isSaving = false;
  bool exitFlowInProgress = false;
  String savedProfileFingerprint = '';

  // Account info controllers
  final TextEditingController usernameCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();

  // PII controllers
  final TextEditingController lastNameCtrl = TextEditingController();
  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController middleNameCtrl = TextEditingController();
  final TextEditingController dobCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController placeOfBirthCtrl = TextEditingController();
  String sex = '';
  String maritalStatus = '';

  // Signature
  List<Offset?> signaturePoints = [];
  String? signatureBase64;
  bool hasExistingSignature = false;

  ProfileController({required this.userId});

  Future<void> loadProfile() async {
    isLoading = true;
    notifyListeners();

    try {
      final accountInfo = await _supabaseService.getAccountInfo(userId);
      final accountData = accountInfo['data'] is Map<String, dynamic>
          ? accountInfo['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final pii = await _supabaseService.loadPiiFromFieldValues(userId);

      activeTemplate ??= await _templateService.fetchActiveTemplates().then(
        (list) => list.isNotEmpty ? list.first : throw Exception('No template'),
      );

      final crossFilled = await _fieldValueService
          .loadUserFieldValuesWithCrossFormFill(
            userId: userId,
            template: activeTemplate!,
          );
      final sigFromCross = crossFilled['__signature']?.toString() ?? '';

      usernameCtrl.text = accountData['username'] ?? '';
      emailCtrl.text = _firstNonEmpty(accountData, ['email']);

      final accountPhone = accountData['phone_number']?.toString().trim() ?? '';
      if (accountPhone.isNotEmpty) {
        phoneCtrl.text = accountPhone;
      } else {
        phoneCtrl.text = _firstNonEmpty(pii, [
          'cp_number', 'phone_number', 'contact_number',
        ]);
      }

      lastNameCtrl.text = pii['last_name'] ?? '';
      firstNameCtrl.text = pii['first_name'] ?? '';
      middleNameCtrl.text = pii['middle_name'] ?? '';
      dobCtrl.text = pii['date_of_birth'] ?? '';
      placeOfBirthCtrl.text = _firstNonEmpty(pii, [
        'place_of_birth',
        'lugar_ng_kapanganakan_place_of_birth',
        'lugar_ng_kapanganakan',
        'birth_place',
        'birthplace',
      ]);

      sex = normalizeGender(pii['kasarian_sex'] ?? '') ?? '';

      maritalStatus = _normalizeCivilStatus(
        _firstNonEmpty(pii, [
          'estadong_sibil_civil_status',
          'civil_status',
          'marital_status',
          'estadong_sibil',
        ]),
      );

      final parts = [
        pii['house_number_street_name_phase_purok'] ?? '',
        pii['subdivison_'] ?? '',
        pii['barangay'] ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
      addressCtrl.text = parts;

      final directSig = (pii['signature'] ?? pii['__signature'] ?? '')
          .toString();
      final existingSig = directSig.isNotEmpty ? directSig : sigFromCross;
      if (existingSig.isNotEmpty) {
        signatureBase64 = existingSig;
        hasExistingSignature = true;
      }

      markProfileAsSaved();
    } catch (e) {
      debugPrint('ProfileController.loadProfile error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _currentProfileFingerprint() {
    return jsonEncode({
      'username': usernameCtrl.text,
      'email': emailCtrl.text,
      'phone': phoneCtrl.text,
      'lastName': lastNameCtrl.text,
      'firstName': firstNameCtrl.text,
      'middleName': middleNameCtrl.text,
      'dob': dobCtrl.text,
      'address': addressCtrl.text,
      'placeOfBirth': placeOfBirthCtrl.text,
      'sex': sex,
      'maritalStatus': maritalStatus,
      'signatureBase64': signatureBase64 ?? '',
      'hasExistingSignature': hasExistingSignature,
    });
  }

  void markProfileAsSaved() {
    savedProfileFingerprint = _currentProfileFingerprint();
  }

  bool hasPendingUnsavedChanges() {
    return _currentProfileFingerprint() != savedProfileFingerprint;
  }

  Future<void> discardPendingChangesAndRefresh() async {
    debugPrint('ProfileController: discarding changes, refreshing latest saved data');
    await loadProfile();
  }

  String _normalizeCivilStatus(String raw) {
    switch (_civilStatusBucket(raw)) {
      case 'single': return 'Single';
      case 'married': return 'Married';
      case 'widowed': return 'Widowed';
      case 'separated': return 'Separated';
      case 'live_in': return 'Live-in';
      case 'minor': return 'Minor';
      case 'annulled': return 'Annulled';
      default: return raw;
    }
  }

  String _firstNonEmpty(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _normalizeKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _civilStatusBucket(String raw) {
    final t = _normalizeKey(raw);
    if (t.isEmpty) return '';
    if (t == 's' || t.contains('single')) return 'single';
    if (t == 'm' || t.contains('married') || t.contains('kasal')) return 'married';
    if (t == 'w' || t.contains('widow') || t.contains('balo')) return 'widowed';
    if (t == 'h' || t.contains('hiwalay') || t.contains('separated')) return 'separated';
    if (t == 'li' || t.contains('live_in') || t.contains('livein')) return 'live_in';
    if (t == 'c' || t.contains('minor')) return 'minor';
    if (t == 'a' || t.contains('annul')) return 'annulled';
    return '';
  }

  Future<bool> syncCivilStatusAcrossTemplates() async {
    final civil = maritalStatus.trim();
    if (civil.isEmpty) return true;
    final result = await _supabaseService.saveScannedIdFieldValues(
      userId: userId,
      canonicalValues: {
        'estadong_sibil_civil_status': civil,
        'civil_status': civil,
        'marital_status': civil,
      },
    );
    return result['success'] == true;
  }

  Future<bool> saveProfile() async {
    if (activeTemplate == null) {
      return false;
    }

    isSaving = true;
    notifyListeners();

    try {
      // 1. Update ONLY username in user_accounts
      await _supabaseService.updateAccountInfo(userId, {
        'username': usernameCtrl.text.trim(),
      });

      // 2. Build PII data map — only include fields with actual values
      final addressParts = addressCtrl.text.trim().split(',');
      final addressLine = addressParts.isNotEmpty ? addressParts[0].trim() : '';
      final subdivision = addressParts.length > 1 ? addressParts[1].trim() : '';
      final barangay = addressParts.length > 2 ? addressParts[2].trim() : '';

      final canonicalMap = <String, String>{};

      if (lastNameCtrl.text.trim().isNotEmpty)
        canonicalMap['last_name'] = lastNameCtrl.text.trim();
      if (firstNameCtrl.text.trim().isNotEmpty)
        canonicalMap['first_name'] = firstNameCtrl.text.trim();
      if (middleNameCtrl.text.trim().isNotEmpty)
        canonicalMap['middle_name'] = middleNameCtrl.text.trim();
      if (dobCtrl.text.trim().isNotEmpty)
        canonicalMap['date_of_birth'] = dobCtrl.text.trim();
      if (placeOfBirthCtrl.text.trim().isNotEmpty) {
        canonicalMap['lugar_ng_kapanganakan_place_of_birth'] =
            placeOfBirthCtrl.text.trim();
        canonicalMap['place_of_birth'] = placeOfBirthCtrl.text.trim();
      }
      if (phoneCtrl.text.trim().isNotEmpty) {
        canonicalMap['cp_number'] = phoneCtrl.text.trim();
        canonicalMap['phone_number'] = phoneCtrl.text.trim();
        canonicalMap['contact_number'] = phoneCtrl.text.trim();
      }
      if (emailCtrl.text.trim().isNotEmpty) {
        canonicalMap['email_address'] = emailCtrl.text.trim();
        canonicalMap['email'] = emailCtrl.text.trim();
      }
      if (sex.isNotEmpty) {
        canonicalMap['kasarian_sex'] = sex;
      }
      if (maritalStatus.isNotEmpty) {
        canonicalMap['estadong_sibil_civil_status'] = maritalStatus;
        canonicalMap['civil_status'] = maritalStatus;
        canonicalMap['marital_status'] = maritalStatus;
      }
      if (addressLine.isNotEmpty) {
        canonicalMap['house_number_street_name_phase_purok'] = addressLine;
      }
      if (subdivision.isNotEmpty) {
        canonicalMap['subdivison_'] = subdivision;
      }
      if (barangay.isNotEmpty) {
        canonicalMap['barangay'] = barangay;
      }

      // Save signature if drawn
      if (signatureBase64 != null && signatureBase64!.isNotEmpty) {
        canonicalMap['signature'] = signatureBase64!;
      }

      // 3. Save PII via canonical key system
      bool savedPII = true;
      if (canonicalMap.isNotEmpty) {
        final result = await _supabaseService.saveScannedIdFieldValues(
          userId: userId,
          canonicalValues: canonicalMap,
        );
        savedPII = result['success'] == true;
      }

      if (savedPII) {
        markProfileAsSaved();
        isSaving = false;
        notifyListeners();
        return true;
      } else {
        isSaving = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('ProfileController.saveProfile error: $e');
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  String? normalizeGender(String? rawValue) {


    if (rawValue == null || rawValue.isEmpty) return null;
    final trimmed = rawValue.toString().trim();
    final lower = trimmed.toLowerCase();
    if (trimmed == 'M' || lower == 'male' || lower == 'lalaki') return 'Male';
    if (trimmed == 'F' || lower == 'female' || lower == 'babae') return 'Female';
    return null;
  }

  Future<void> finalizeSignature() async {
    final realPoints = signaturePoints.whereType<Offset>().toList();
    if (realPoints.length < 2) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 160),
      Paint()..color = Colors.white,
    );

    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < signaturePoints.length - 1; i++) {
      if (signaturePoints[i] != null && signaturePoints[i + 1] != null) {
        canvas.drawLine(signaturePoints[i]!, signaturePoints[i + 1]!, pen);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(320, 160);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;

    final b64 = 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
    signatureBase64 = b64;
    hasExistingSignature = true;
    notifyListeners();
  }

  Future<DateTime?> selectDate(BuildContext context) async {
    DateTime initial = DateTime(2000);
    if (dobCtrl.text.isNotEmpty) {
      try { initial = DateTime.parse(dobCtrl.text); } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryBlue,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      dobCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      notifyListeners();
    }
    return picked;
  }

  Future<void> handleLogout(BuildContext context) async {
    if (exitFlowInProgress) return;
    exitFlowInProgress = true;

    try {
      final hasPendingUnsaved = hasPendingUnsavedChanges();
      debugPrint('ProfileController: logout requested, hasPendingUnsaved=$hasPendingUnsaved');
      if (hasPendingUnsaved) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Log out?'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
              child: const Text('Log Out', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } finally {
      exitFlowInProgress = false;
    }
  }

  String get displayName {
    final name = [
      firstNameCtrl.text,
      middleNameCtrl.text.isNotEmpty ? '${middleNameCtrl.text[0]}.' : '',
      lastNameCtrl.text,
    ].where((s) => s.isNotEmpty).join(' ').trim();
    return name.isEmpty ? 'No Name Set' : name;
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    lastNameCtrl.dispose();
    firstNameCtrl.dispose();
    middleNameCtrl.dispose();
    dobCtrl.dispose();
    addressCtrl.dispose();
    placeOfBirthCtrl.dispose();
    super.dispose();
  }
}
