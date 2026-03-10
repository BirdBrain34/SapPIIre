import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabaseService = SupabaseService();
  bool _isLoading = true;
  bool _isSaving = false;
  String _username = '';

  // Controllers
  final _lastNameCtrl      = TextEditingController();
  final _firstNameCtrl     = TextEditingController();
  final _middleNameCtrl    = TextEditingController();
  final _dobCtrl           = TextEditingController();
  final _addressCtrl       = TextEditingController();
  final _placeOfBirthCtrl  = TextEditingController();
  String _sex         = '';
  String _bloodType   = '';
  String _maritalStatus = '';

  String? _profileId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final username = await _supabaseService.getUsername(widget.userId);
      final profileData = await _supabaseService.loadUserProfile(widget.userId);

      setState(() {
        _username = username ?? '';
        if (profileData != null) {
          _profileId = profileData['profile_id'];
          _lastNameCtrl.text   = profileData['lastname'] ?? '';
          _firstNameCtrl.text  = profileData['firstname'] ?? '';
          _middleNameCtrl.text = profileData['middle_name'] ?? '';
          final rawGender = profileData['gender'] ?? '';
          _sex = (rawGender == 'M') ? 'Male'
              : (rawGender == 'F') ? 'Female'
              : rawGender;
          _bloodType = profileData['blood_type'] ?? '';
          final rawCivil = profileData['civil_status'] ?? '';
          _maritalStatus = (rawCivil == 'S') ? 'Single'
              : (rawCivil == 'M') ? 'Married'
              : (rawCivil == 'W') ? 'Widowed'
              : (rawCivil == 'Sep') ? 'Separated'
              : (rawCivil == 'A') ? 'Annulled'
              : rawCivil;
          _placeOfBirthCtrl.text = profileData['birthplace'] ?? '';

          // Format birthdate
          final rawDate = profileData['birthdate'];
          if (rawDate != null) {
            _dobCtrl.text = rawDate.toString().split('T').first;
          }

          // Address from nested user_addresses
          final address = profileData['user_addresses'];
          if (address != null && address is Map) {
            final parts = [
              address['address_line'],
              address['subdivision'],
              address['barangay'],
            ].where((p) => p != null && p.toString().isNotEmpty).join(', ');
            _addressCtrl.text = parts;
          }
        }
      });
    } catch (e) {
      debugPrint('ProfileScreen._loadProfile error: $e');
      _showFeedback('Failed to load profile', Colors.red);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      // Save main profile fields
      await _supabaseService.saveUserProfile(
        userId: widget.userId,
        profileData: {
          'lastname':     _lastNameCtrl.text.trim(),
          'firstname':    _firstNameCtrl.text.trim(),
          'middle_name':  _middleNameCtrl.text.trim(),
          'birthdate':    _dobCtrl.text.trim(),
          'gender': _sex == 'Male' ? 'M' : _sex == 'Female' ? 'F' : _sex,
          'civil_status': _maritalStatus == 'Single' ? 'S'
            : _maritalStatus == 'Married' ? 'M'
            : _maritalStatus == 'Widowed' ? 'W'
            : _maritalStatus == 'Separated' ? 'Sep'
            : _maritalStatus == 'Annulled' ? 'A'
            : _maritalStatus,
          'blood_type':   _bloodType,
          'birthplace':   _placeOfBirthCtrl.text.trim(),
        },
        membershipData: {},
      );

      // Save address — parse combined address back into parts
      if (_profileId != null) {
        final addressParts = _addressCtrl.text.trim().split(',');
        await _supabaseService.saveUserAddress(_profileId!, {
          'address_line': addressParts.isNotEmpty ? addressParts[0].trim() : '',
          'subdivision':  addressParts.length > 1  ? addressParts[1].trim() : '',
          'barangay':     addressParts.length > 2  ? addressParts[2].trim() : '',
        });
      }

      _showFeedback('Profile saved!', Colors.green);
    } catch (e) {
      debugPrint('ProfileScreen._saveProfile error: $e');
      _showFeedback('Save failed: $e', Colors.red);
    }
    setState(() => _isSaving = false);
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime(2000);
    if (_dobCtrl.text.isNotEmpty) {
      try {
        initial = DateTime.parse(_dobCtrl.text);
      } catch (_) {}
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerRed,
            ),
            child: const Text('Log Out',
                style: TextStyle(color: Colors.white)),
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

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
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
            child: const Icon(Icons.person_outline,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'My Profile',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w400),
              ),
              Text(
                _username.isEmpty ? 'User' : _username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined,
                  color: Colors.white, size: 22),
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
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          _firstNameCtrl.text,
                          _middleNameCtrl.text.isNotEmpty
                              ? '${_middleNameCtrl.text[0]}.'
                              : '',
                          _lastNameCtrl.text,
                        ]
                            .where((s) => s.isNotEmpty)
                            .join(' ')
                            .trim()
                            .isEmpty
                            ? 'No Name Set'
                            : [
                                _firstNameCtrl.text,
                                _middleNameCtrl.text.isNotEmpty
                                    ? '${_middleNameCtrl.text[0]}.'
                                    : '',
                                _lastNameCtrl.text,
                              ]
                                .where((s) => s.isNotEmpty)
                                .join(' '),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$_username',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Personal Info Section
          _buildSectionHeader('Personal Information', Icons.badge_outlined),
          const SizedBox(height: 12),

          _buildCard([
            _buildTextField(
              label: 'Last Name',
              controller: _lastNameCtrl,
              icon: Icons.person_outline,
            ),
            _buildDivider(),
            _buildTextField(
              label: 'First Name',
              controller: _firstNameCtrl,
              icon: Icons.person_outline,
            ),
            _buildDivider(),
            _buildTextField(
              label: 'Middle Name',
              controller: _middleNameCtrl,
              icon: Icons.person_outline,
            ),
          ]),

          const SizedBox(height: 16),
          _buildSectionHeader('Birth Details', Icons.cake_outlined),
          const SizedBox(height: 12),

          _buildCard([
            _buildDateField(),
            _buildDivider(),
            _buildTextField(
              label: 'Place of Birth',
              controller: _placeOfBirthCtrl,
              icon: Icons.location_city_outlined,
            ),
          ]),

          const SizedBox(height: 16),
          _buildSectionHeader('Additional Details', Icons.info_outline),
          const SizedBox(height: 12),

          _buildCard([
            _buildDropdownField(
              label: 'Sex',
              value: _sex.isEmpty ? null : _sex,
              icon: Icons.wc_outlined,
              items: const ['Male', 'Female'],
              onChanged: (v) => setState(() => _sex = v ?? ''),
            ),
            _buildDivider(),
            _buildDropdownField(
              label: 'Blood Type',
              value: _bloodType.isEmpty ? null : _bloodType,
              icon: Icons.water_drop_outlined,
              items: const [
                'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
              ],
              onChanged: (v) => setState(() => _bloodType = v ?? ''),
            ),
            _buildDivider(),
            _buildDropdownField(
              label: 'Marital Status',
              value: _maritalStatus.isEmpty ? null : _maritalStatus,
              icon: Icons.favorite_border_outlined,
              items: const [
                'Single', 'Married', 'Widowed', 'Separated', 'Annulled'
              ],
              onChanged: (v) => setState(() => _maritalStatus = v ?? ''),
            ),
          ]),

          const SizedBox(height: 16),
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

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Profile',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ── Card wrapper ──────────────────────────────────────────

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() => const Divider(height: 1, indent: 16, endIndent: 16);

  // ── Text Field ────────────────────────────────────────────

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
                labelStyle: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Date Field ────────────────────────────────────────────

  Widget _buildDateField() {
    return InkWell(
      onTap: _selectDate,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date of Birth',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dobCtrl.text.isEmpty ? 'Select date' : _dobCtrl.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: _dobCtrl.text.isEmpty
                          ? Colors.grey.shade400
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ── Dropdown Field ────────────────────────────────────────

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Text(label,
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade400)),
                isExpanded: true,
                icon: Icon(Icons.expand_more,
                    size: 18, color: Colors.grey.shade400),
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87),
                items: items
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ))
                    .toList(),
                onChanged: onChanged,
                selectedItemBuilder: (context) => items
                    .map((item) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                            Text(item,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87)),
                          ],
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}