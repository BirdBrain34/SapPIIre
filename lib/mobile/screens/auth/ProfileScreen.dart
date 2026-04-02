import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/field_value_service.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/ChangePIN.dart';
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
  final _lastNameCtrl     = TextEditingController();
  final _firstNameCtrl    = TextEditingController();
  final _middleNameCtrl   = TextEditingController();
  final _dobCtrl          = TextEditingController();
  final _addressCtrl      = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  String _sex = '';
  String _maritalStatus = '';

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
      final pii = await _supabaseService.loadPiiFromFieldValues(widget.userId);

      _activeTemplate ??= await _templateService
          .fetchActiveTemplates()
          .then((list) => list.isNotEmpty ? list.first : throw Exception('No template'));

      setState(() {
        _usernameCtrl.text = accountInfo['username'] ?? '';
        _emailCtrl.text    = accountInfo['email']    ?? '';
        _phoneCtrl.text    = accountInfo['phone_number'] ?? '';

        _lastNameCtrl.text      = pii['last_name']  ?? '';
        _firstNameCtrl.text     = pii['first_name'] ?? '';
        _middleNameCtrl.text    = pii['middle_name'] ?? '';
        _dobCtrl.text           = pii['date_of_birth'] ?? '';
        _placeOfBirthCtrl.text  = pii['lugar_ng_kapanganakan_place_of_birth'] ?? '';

        _sex          = _normalizeGender(pii['kasarian_sex'] ?? '') ?? '';
        _maritalStatus = _normalizeCivilStatus(pii['estadong_sibil_civil_status'] ?? '');

        final parts = [
          pii['house_number_street_name_phase_purok'] ?? '',
          pii['subdivison_'] ?? '',
          pii['barangay'] ?? '',
        ].where((s) => s.isNotEmpty).join(', ');
        _addressCtrl.text = parts;
      });
    } catch (e) {
      debugPrint('ProfileScreen._loadProfile error: $e');
      _showFeedback('Failed to load profile', Colors.red);
    }
    setState(() => _isLoading = false);
  }

  String _normalizeCivilStatus(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('single')    || lower == 's')   return 'Single';
    if (lower.contains('married')   || lower == 'm')   return 'Married';
    if (lower.contains('widow')     || lower == 'w')   return 'Widowed';
    if (lower.contains('separated') || lower == 'sep') return 'Separated';
    if (lower.contains('annul')     || lower == 'a')   return 'Annulled';
    return raw;
  }

  String _normalizeKey(String raw) {
    return raw.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String? _findTemplateFieldName(List<String> aliases) {
    final template = _activeTemplate;
    if (template == null) return null;
    final wanted = aliases.map(_normalizeKey).toSet();
    for (final field in template.allFields) {
      if (field.parentFieldId != null) continue;
      final fieldKey  = _normalizeKey(field.fieldName);
      final canonical = field.canonicalFieldKey == null ? null : _normalizeKey(field.canonicalFieldKey!);
      final source    = field.autofillSource    == null ? null : _normalizeKey(field.autofillSource!);
      if (wanted.contains(fieldKey) ||
          (canonical != null && wanted.contains(canonical)) ||
          (source    != null && wanted.contains(source))) {
        return field.fieldName;
      }
    }
    return null;
  }

  void _putMappedValue(Map<String, dynamic> formData, List<String> aliases, dynamic value) {
    final fieldName = _findTemplateFieldName(aliases);
    if (fieldName == null) return;
    formData[fieldName] = value;
  }

Future<void> _saveProfile() async {
    if (_activeTemplate == null) {
      _showFeedback('No active form template found', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Update core account information (user_accounts table)
      // This saves the editable Username, Email, and Phone Number
      await _supabaseService.updateAccountInfo(widget.userId, {
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
      });

      // 2. Prepare PII Data (Field Values)
      // We parse the address controller back into its component parts
      final addressParts = _addressCtrl.text.trim().split(',');
      final addressLine  = addressParts.isNotEmpty ? addressParts[0].trim() : '';
      final subdivision  = addressParts.length > 1  ? addressParts[1].trim() : '';
      final barangay     = addressParts.length > 2  ? addressParts[2].trim() : '';

      final formData = <String, dynamic>{};

      // Map Identity Fields
      _putMappedValue(formData, const ['last_name', 'lastname'], _lastNameCtrl.text.trim());
      _putMappedValue(formData, const ['first_name', 'firstname'], _firstNameCtrl.text.trim());
      _putMappedValue(formData, const ['middle_name', 'middlename'], _middleNameCtrl.text.trim());

      // Map Birth Details
      _putMappedValue(formData, const [
        'date_of_birth',
        'birth_date',
        'petsa_ng_kapanganakan',
        'date_of_birth_petsa_ng_kapanganakan',
      ], _dobCtrl.text.trim());

      _putMappedValue(formData, const [
        'lugar_ng_kapanganakan_place_of_birth',
        'lugar_ng_kapanganakan',
        'place_of_birth',
        'birth_place',
        'birthplace',
      ], _placeOfBirthCtrl.text.trim());

      // Map Additional Details
      _putMappedValue(formData, const ['kasarian_sex', 'gender', 'sex', 'kasarian'], _sex);
      _putMappedValue(formData, const [
        'estadong_sibil_civil_status', 
        'civil_status', 
        'marital_status', 
        'estadong_sibil',
      ], _maritalStatus);

      // Map Address Parts
      _putMappedValue(formData, const [
        'house_number_street_name_phase_purok', 
        'address_line', 
        'house_no_street',
      ], addressLine);
      _putMappedValue(formData, const ['subdivison_', 'subdivision'], subdivision);
      _putMappedValue(formData, const ['barangay'], barangay);

      // 3. Save PII to the field_values system
      final savedPII = await _fieldValueService.saveUserFieldValues(
        userId: widget.userId,
        template: _activeTemplate!,
        formData: formData,
      );

      if (savedPII) {
        _showFeedback('Profile updated successfully!', Colors.green);
        // We call setState to refresh the UI (especially the username in the AppBar)
        setState(() {});
      } else {
        _showFeedback('Account saved, but PII details failed.', Colors.orange);
      }

    } catch (e) {
      debugPrint('ProfileScreen._saveProfile error: $e');
      _showFeedback('Save failed: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
            primary: AppColors.primaryBlue, onPrimary: Colors.white,
            surface: Colors.white,          onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      // FIX: wrap in setState so the Text widget rebuilds immediately
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

  void _handleChangePin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePinScreen(fromProfile: true)),
    ).then((_) {
      if (mounted) _showFeedback('PIN changed successfully!', Colors.green);
    });
  }

  Future<void> _openCamera() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoScannerScreen()));
  }

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  // ── Build ──────────────────────────────────────────────────

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
              color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              const Text('My Profile',
                  style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w400)),
              Text(_usernameCtrl.text.isEmpty ? 'User' : _usernameCtrl.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 22),
          onPressed: _openCamera, tooltip: 'Scan ID',
        ),
        IconButton(
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
          onPressed: _isSaving ? null : _saveProfile, tooltip: 'Save Profile',
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
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
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

          // Account Information (read-only)
          _buildSectionHeader('Account Information', Icons.manage_accounts_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(
              label: 'Username', 
              controller: _usernameCtrl, 
              icon: Icons.badge_outlined
            ),
            _buildDivider(),
            _buildTextField(
              label: 'Email', 
              controller: _emailCtrl, 
              icon: Icons.email_outlined
            ),
            _buildDivider(),
            _buildTextField(
              label: 'Phone Number', 
              controller: _phoneCtrl, 
              icon: Icons.phone_android_outlined
            ),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'To change username, email, or phone — contact support.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ),

          const SizedBox(height: 20),

          // Personal Information
          _buildSectionHeader('Personal Information', Icons.badge_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(label: 'Last Name',   controller: _lastNameCtrl,  icon: Icons.person_outline),
            _buildDivider(),
            _buildTextField(label: 'First Name',  controller: _firstNameCtrl, icon: Icons.person_outline),
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
            _buildTextField(label: 'Place of Birth', controller: _placeOfBirthCtrl,
                icon: Icons.location_city_outlined),
          ]),

          const SizedBox(height: 16),

          // Additional Details
          _buildSectionHeader('Additional Details', Icons.info_outline),
          const SizedBox(height: 12),
          _buildCard([
            _buildDropdownField(
              label: 'Sex', value: _normalizeGender(_sex), icon: Icons.wc_outlined,
              items: const ['Male', 'Female'],
              onChanged: (v) => setState(() => _sex = _normalizeGender(v) ?? ''),
            ),
            _buildDivider(),
            _buildDropdownField(
              label: 'Marital Status', value: _maritalStatus.isEmpty ? null : _maritalStatus,
              icon: Icons.favorite_border_outlined,
              items: const ['Single', 'Married', 'Widowed', 'Separated', 'Annulled'],
              onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
            ),
          ]),

          const SizedBox(height: 16),

          // Address
          _buildSectionHeader('Address', Icons.home_outlined),
          const SizedBox(height: 12),
          _buildCard([
            _buildTextField(
              label: 'Full Address', controller: _addressCtrl, icon: Icons.map_outlined,
              hint: 'House No., Street, Subdivision, Barangay', maxLines: 2,
            ),
          ]),

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(_isSaving ? 'Saving...' : 'Save Profile',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
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
              icon: Icons.lock_reset_outlined, label: 'Change PIN',
              subtitle: 'Update your 6-digit login PIN', onTap: _handleChangePin,
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.shield_outlined, label: 'Privacy & Terms',
              subtitle: 'Data Privacy Act of 2012 (R.A. 10173)',
              onTap: () => TermsAndConditionsDialog.showForReading(context),
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.logout, label: 'Log Out',
              subtitle: 'Sign out of your account',
              onTap: _handleLogout, isDestructive: true,
            ),
          ]),

          const SizedBox(height: 16),
          Center(child: Text('SapPIIre v1.0.0',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
        ],
      ),
    );
  }

  // ── Reusable widgets ────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.primaryBlue),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryBlue, letterSpacing: 0.3)),
    ]);
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label, required TextEditingController controller,
    required IconData icon, String? hint, int maxLines = 1,
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
              controller: controller, maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                labelText: label, hintText: hint,
                labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                border: InputBorder.none, isDense: true,
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Date of Birth', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(
                  _dobCtrl.text.isEmpty ? 'Select date' : _dobCtrl.text,
                  style: TextStyle(fontSize: 14,
                      color: _dobCtrl.text.isEmpty ? Colors.grey.shade400 : Colors.black87),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label, required String? value, required IconData icon,
    required List<String> items, required void Function(String?) onChanged,
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
    required IconData icon, required String label, required String subtitle,
    required VoidCallback onTap, bool isDestructive = false,
  }) {
    final color = isDestructive ? AppColors.dangerRed : AppColors.primaryBlue;
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: isDestructive ? AppColors.dangerRed : Colors.black87)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}