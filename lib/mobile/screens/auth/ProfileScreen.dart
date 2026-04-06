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
import 'package:sappiire/mobile/screens/auth/ChangePassword.dart';
import 'package:sappiire/mobile/widgets/TermsAndCondition.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabaseService = SupabaseService();
  final _templateService = FormTemplateService();
  final _fieldValueService = FieldValueService();
  FormTemplate? _activeTemplate;
  bool _isLoading = true;
  bool _isSaving = false;

  // Account info (from user_accounts table)
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // PII Controllers
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

  // Signature
  List<Offset?> _signaturePoints = [];
  String? _signatureBase64;
  bool _hasExistingSignature = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    super.dispose();
  }

  String? _normalizeGender(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return null;
    final trimmed = rawValue.toString().trim();
    final lower = trimmed.toLowerCase();
    if (trimmed == 'M' || lower == 'male' || lower == 'lalaki') return 'Male';
    if (trimmed == 'F' || lower == 'female' || lower == 'babae') return 'Female';
    return null;
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final accountInfo = await _supabaseService.getAccountInfo(widget.userId);
      final accountData = accountInfo['data'] is Map<String, dynamic>
          ? accountInfo['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final pii = await _supabaseService.loadPiiFromFieldValues(widget.userId);

      _activeTemplate ??= await _templateService.fetchActiveTemplates().then(
        (list) => list.isNotEmpty ? list.first : throw Exception('No template'),
      );

      setState(() {
        _usernameCtrl.text = accountData['username'] ?? '';
        _emailCtrl.text = _firstNonEmpty(accountData, ['email']);

        final accountPhone = accountData['phone_number']?.toString().trim() ?? '';
        if (accountPhone.isNotEmpty) {
          _phoneCtrl.text = accountPhone;
        } else {
          _phoneCtrl.text = _firstNonEmpty(pii, [
            'cp_number', 'phone_number', 'contact_number',
          ]);
        }

        _lastNameCtrl.text = pii['last_name'] ?? '';
        _firstNameCtrl.text = pii['first_name'] ?? '';
        _middleNameCtrl.text = pii['middle_name'] ?? '';
        _dobCtrl.text = pii['date_of_birth'] ?? '';
        _placeOfBirthCtrl.text = _firstNonEmpty(pii, [
          'place_of_birth',
          'lugar_ng_kapanganakan_place_of_birth',
          'lugar_ng_kapanganakan',
          'birth_place',
          'birthplace',
        ]);

        _sex = _normalizeGender(pii['kasarian_sex'] ?? '') ?? '';
        _maritalStatus = _normalizeCivilStatus(
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
        _addressCtrl.text = parts;

        // Load existing signature if any
        final existingSig = pii['signature'] ?? pii['__signature'] ?? '';
        if (existingSig.isNotEmpty) {
          _signatureBase64 = existingSig;
          _hasExistingSignature = true;
        }
      });
    } catch (e) {
      debugPrint('ProfileScreen._loadProfile error: $e');
      _showFeedback('Failed to load profile', Colors.red);
    }
    setState(() => _isLoading = false);
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

  FormFieldModel? _findTemplateField(List<String> aliases) {
    final template = _activeTemplate;
    if (template == null) return null;
    final wanted = aliases.map(_normalizeKey).toSet();
    for (final field in template.allFields) {
      if (field.parentFieldId != null) continue;
      final fieldKey = _normalizeKey(field.fieldName);
      final canonical = field.canonicalFieldKey == null
          ? null
          : _normalizeKey(field.canonicalFieldKey!);
      final source = field.autofillSource == null
          ? null
          : _normalizeKey(field.autofillSource!);
      if (wanted.contains(fieldKey) ||
          (canonical != null && wanted.contains(canonical)) ||
          (source != null && wanted.contains(source))) {
        return field;
      }
    }
    return null;
  }

  String? _findTemplateFieldName(List<String> aliases) {
    return _findTemplateField(aliases)?.fieldName;
  }

  void _putMappedValue(
    Map<String, dynamic> formData,
    List<String> aliases,
    dynamic value,
  ) {
    final fieldName = _findTemplateFieldName(aliases);
    if (fieldName == null) return;
    formData[fieldName] = value;
  }

  String _resolveCivilStatusForField(FormFieldModel field, String rawValue) {
    final bucket = _civilStatusBucket(rawValue);
    if (bucket.isEmpty) return rawValue;
    if (field.options.isNotEmpty) {
      for (final option in field.options) {
        if (_civilStatusBucket(option.value) == bucket ||
            _civilStatusBucket(option.label) == bucket) {
          return option.value;
        }
      }
    }
    return _normalizeCivilStatus(rawValue);
  }

  void _putMappedCivilStatusValue(
    Map<String, dynamic> formData,
    List<String> aliases,
    String rawValue,
  ) {
    final field = _findTemplateField(aliases);
    if (field == null) return;
    formData[field.fieldName] = _resolveCivilStatusForField(field, rawValue);
  }

  Future<bool> _syncCivilStatusAcrossTemplates() async {
    final civil = _maritalStatus.trim();
    if (civil.isEmpty) return true;
    final result = await _supabaseService.saveScannedIdFieldValues(
      userId: widget.userId,
      canonicalValues: {
        'estadong_sibil_civil_status': civil,
        'civil_status': civil,
        'marital_status': civil,
      },
    );
    return result['success'] == true;
  }

  // ── SAVE PROFILE — FIX: username change no longer clears PII ──────
  // Root cause was that saveUserFieldValues was using the template's allFields
  // list and since we pass an empty/partial formData, it was overwriting
  // existing values. Fix: only update fields that have non-empty values,
  // and update username separately without touching PII.
  Future<void> _saveProfile() async {
    if (_activeTemplate == null) {
      _showFeedback('No active form template found', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Update ONLY username in user_accounts
      // This is completely separate from PII — no PII is touched here
      await _supabaseService.updateAccountInfo(widget.userId, {
        'username': _usernameCtrl.text.trim(),
      });

      // 2. Build PII data map — only include fields with actual values
      // This prevents overwriting existing DB values with empty strings
      final addressParts = _addressCtrl.text.trim().split(',');
      final addressLine = addressParts.isNotEmpty ? addressParts[0].trim() : '';
      final subdivision = addressParts.length > 1 ? addressParts[1].trim() : '';
      final barangay = addressParts.length > 2 ? addressParts[2].trim() : '';

      // Build canonical map for cross-template save
      // Only include non-empty values to avoid overwriting DB with blanks
      final canonicalMap = <String, String>{};

      if (_lastNameCtrl.text.trim().isNotEmpty)
        canonicalMap['last_name'] = _lastNameCtrl.text.trim();
      if (_firstNameCtrl.text.trim().isNotEmpty)
        canonicalMap['first_name'] = _firstNameCtrl.text.trim();
      if (_middleNameCtrl.text.trim().isNotEmpty)
        canonicalMap['middle_name'] = _middleNameCtrl.text.trim();
      if (_dobCtrl.text.trim().isNotEmpty)
        canonicalMap['date_of_birth'] = _dobCtrl.text.trim();
      if (_placeOfBirthCtrl.text.trim().isNotEmpty) {
        canonicalMap['lugar_ng_kapanganakan_place_of_birth'] =
            _placeOfBirthCtrl.text.trim();
        canonicalMap['place_of_birth'] = _placeOfBirthCtrl.text.trim();
      }
      if (_phoneCtrl.text.trim().isNotEmpty) {
        canonicalMap['cp_number'] = _phoneCtrl.text.trim();
        canonicalMap['phone_number'] = _phoneCtrl.text.trim();
        canonicalMap['contact_number'] = _phoneCtrl.text.trim();
      }
      if (_sex.isNotEmpty) {
        canonicalMap['kasarian_sex'] = _sex;
      }
      if (_maritalStatus.isNotEmpty) {
        canonicalMap['estadong_sibil_civil_status'] = _maritalStatus;
        canonicalMap['civil_status'] = _maritalStatus;
        canonicalMap['marital_status'] = _maritalStatus;
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
      if (_signatureBase64 != null && _signatureBase64!.isNotEmpty) {
        canonicalMap['signature'] = _signatureBase64!;
      }

      // 3. Save PII via canonical key system — updates across all templates
      // Uses saveScannedIdFieldValues which only UPSERTS — never deletes existing rows
      bool savedPII = true;
      if (canonicalMap.isNotEmpty) {
        final result = await _supabaseService.saveScannedIdFieldValues(
          userId: widget.userId,
          canonicalValues: canonicalMap,
        );
        savedPII = result['success'] == true;
      }

      if (savedPII) {
        _showFeedback('Profile updated successfully!', Colors.green);
        setState(() {});
      } else {
        _showFeedback('Account saved, but some PII details failed.', Colors.orange);
      }
    } catch (e) {
      debugPrint('ProfileScreen._saveProfile error: $e');
      // Check for duplicate username error
      if (e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('unique') ||
          e.toString().toLowerCase().contains('duplicate') ||
          e.toString().toLowerCase().contains('already exists')) {
        _showFeedback(
          'This username already exists. Please choose a different one.',
          Colors.red,
        );
      } else {
        _showFeedback('Save failed: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Signature helpers ─────────────────────────────────────
  Future<void> _finalizeSignature() async {
    final realPoints = _signaturePoints.whereType<Offset>().toList();
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

    for (int i = 0; i < _signaturePoints.length - 1; i++) {
      if (_signaturePoints[i] != null && _signaturePoints[i + 1] != null) {
        canvas.drawLine(_signaturePoints[i]!, _signaturePoints[i + 1]!, pen);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(320, 160);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;

    final b64 = 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
    if (mounted) {
      setState(() {
        _signatureBase64 = b64;
        _hasExistingSignature = true;
      });
    }
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime(2000);
    if (_dobCtrl.text.isNotEmpty) {
      try { initial = DateTime.parse(_dobCtrl.text); } catch (_) {}
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
      setState(() {
        _dobCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _handleLogout() async {
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
    if (confirmed != true || !mounted) return;
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _handleChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen(fromProfile: true)),
    ).then((_) {
      if (mounted) _showFeedback('Password changed successfully!', Colors.green);
    });
  }

  Future<void> _openCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
    );
    // Reload after scanning — do NOT clear existing values, just refresh
    if (mounted) await _loadProfile();
  }

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: _buildAppBar(),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('My Profile', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w400)),
              Text(
                _usernameCtrl.text.isEmpty ? 'User' : _usernameCtrl.text,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 22),
          onPressed: _openCamera,
          tooltip: 'Scan ID',
        ),
        IconButton(
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
          onPressed: _isSaving ? null : _saveProfile,
          tooltip: 'Save Profile',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          final name = [
                            _firstNameCtrl.text,
                            _middleNameCtrl.text.isNotEmpty ? '${_middleNameCtrl.text[0]}.' : '',
                            _lastNameCtrl.text,
                          ].where((s) => s.isNotEmpty).join(' ').trim();
                          return name.isEmpty ? 'No Name Set' : name;
                        }(),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('@${_usernameCtrl.text}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Account Information
          _buildSectionHeader('Account Information', Icons.manage_accounts_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(label: 'Username', controller: _usernameCtrl, icon: Icons.badge_outlined),
            _buildDivider(),
            _buildReadOnlyRow(icon: Icons.email_outlined, label: 'Email', value: _emailCtrl.text.isEmpty ? '—' : _emailCtrl.text),
            _buildDivider(),
            _buildReadOnlyRow(icon: Icons.phone_android_outlined, label: 'Phone Number', value: _phoneCtrl.text.isEmpty ? '—' : _phoneCtrl.text),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Email and phone number cannot be changed here. Contact support if needed.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ),

          const SizedBox(height: 20),

          // Personal Information
          _buildSectionHeader('Personal Information', Icons.badge_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(label: 'Last Name', controller: _lastNameCtrl, icon: Icons.person_outline),
            _buildDivider(),
            _buildTextField(label: 'First Name', controller: _firstNameCtrl, icon: Icons.person_outline),
            _buildDivider(),
            _buildTextField(label: 'Middle Name', controller: _middleNameCtrl, icon: Icons.person_outline),
          ]),

          const SizedBox(height: 16),

          // Birth Details
          _buildSectionHeader('Birth Details', Icons.cake_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildDateField(),
            _buildDivider(),
            _buildTextField(label: 'Place of Birth', controller: _placeOfBirthCtrl, icon: Icons.location_city_outlined),
          ]),

          const SizedBox(height: 16),

          // Additional Details
          _buildSectionHeader('Additional Details', Icons.info_outline),
          const SizedBox(height: 12),
          _buildCard([
            _buildDropdownField(
              label: 'Sex',
              value: _normalizeGender(_sex),
              icon: Icons.wc_outlined,
              items: const ['Male', 'Female'],
              onChanged: (v) => setState(() => _sex = _normalizeGender(v) ?? ''),
            ),
            _buildDivider(),
            _buildDropdownField(
              label: 'Marital Status',
              value: _maritalStatus.isEmpty ? null : _maritalStatus,
              icon: Icons.favorite_border_outlined,
              items: const ['Single', 'Married', 'Widowed', 'Separated', 'Live-in', 'Minor', 'Annulled'],
              onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
            ),
          ]),

          const SizedBox(height: 16),

          // Address
          _buildSectionHeader('Address', Icons.home_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(
              label: 'Full Address',
              controller: _addressCtrl,
              icon: Icons.map_outlined,
              hint: 'House No., Street, Subdivision, Barangay',
              maxLines: 2,
            ),
          ]),

          const SizedBox(height: 16),

          // Signature
          _buildSectionHeader('Signature', Icons.draw_outlined),
          const SizedBox(height: 4),
          Text(
            'Draw your signature below. It will be saved and used in forms.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          _buildSignatureCard(),

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Profile',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Account Settings
          _buildSectionHeader('Account Settings', Icons.settings_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildActionRow(
              icon: Icons.lock_reset_outlined,
              label: 'Change Password',
              subtitle: 'Update your account password',
              onTap: _handleChangePassword,
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.shield_outlined,
              label: 'Privacy & Terms',
              subtitle: 'Data Privacy Act of 2012 (R.A. 10173)',
              onTap: () => TermsAndConditionsDialog.showForReading(context),
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.logout,
              label: 'Log Out',
              subtitle: 'Sign out of your account',
              onTap: _handleLogout,
              isDestructive: true,
            ),
          ]),

          const SizedBox(height: 16),
          Center(child: Text('SapPIIre v1.0.0', style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
        ],
      ),
    );
  }

  // ── Signature Card ─────────────────────────────────────────
  Widget _buildSignatureCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          if (_hasExistingSignature && _signatureBase64 != null) ...[
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
                    child: _renderSignature(_signatureBase64!),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _signaturePoints = [];
                      _signatureBase64 = null;
                      _hasExistingSignature = false;
                    }),
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
                      onPanStart: (d) => setState(() => _signaturePoints.add(d.localPosition)),
                      onPanUpdate: (d) => setState(() => _signaturePoints.add(d.localPosition)),
                      onPanEnd: (_) async {
                        _signaturePoints.add(null);
                        await _finalizeSignature();
                      },
                      child: CustomPaint(
                        painter: _SignaturePainter(_signaturePoints),
                        child: Container(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Draw above', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      const Spacer(),
                      if (_signaturePoints.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _signaturePoints = [];
                            _signatureBase64 = null;
                          }),
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

  // ── Reusable widgets ────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryBlue),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryBlue, letterSpacing: 0.3)),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() => const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _buildReadOnlyRow({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _selectDate,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date of Birth', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(
                    _dobCtrl.text.isEmpty ? 'Select date' : _dobCtrl.text,
                    style: TextStyle(fontSize: 14, color: _dobCtrl.text.isEmpty ? Colors.grey.shade400 : Colors.black87),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    String? safeValue = value;
    if (safeValue != null && !items.contains(safeValue)) safeValue = null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: safeValue,
                hint: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                isExpanded: true,
                icon: Icon(Icons.expand_more, size: 18, color: Colors.grey.shade400),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                onChanged: onChanged,
                selectedItemBuilder: (context) => items.map((item) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    Text(item, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                  ],
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? AppColors.dangerRed : AppColors.primaryBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDestructive ? AppColors.dangerRed : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Signature painter ─────────────────────────────────────────
class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

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
  bool shouldRepaint(_SignaturePainter old) => true;
}