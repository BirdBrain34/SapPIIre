import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/profile_controller.dart';
import 'package:sappiire/mobile/screens/auth/ChangePassword.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/widgets/TermsAndCondition.dart';
import 'package:sappiire/mobile/widgets/profile_header_card.dart';
import 'package:sappiire/mobile/widgets/profile_section_card.dart';
import 'package:sappiire/mobile/widgets/signature_pad_widget.dart';
import 'package:sappiire/mobile/widgets/unsaved_changes_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController(userId: widget.userId);
    _controller.addListener(() => setState(() {}));
    _controller.loadProfile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool?> _showUnsavedChangesDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UnsavedChangesDialog(
        onDiscard: () {
          debugPrint('ProfileScreen: unsaved dialog button tapped -> Discard');
          Navigator.pop(ctx, false);
        },
        onSaveAndContinue: () async {
          debugPrint('ProfileScreen: unsaved dialog button tapped -> Save & Continue');
          await _saveProfile();
          if (!ctx.mounted) return;
          if (!_controller.hasPendingUnsavedChanges()) {
            Navigator.pop(ctx, true);
          }
        },
      ),
    );
  }

  Future<bool> _resolveUnsavedChangesIfAny() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    while (_controller.hasPendingUnsavedChanges()) {
      final result = await _showUnsavedChangesDialog();
      if (!mounted) return false;

      if (result != true) {
        debugPrint('ProfileScreen: unsaved dialog action=discard');
        await _controller.discardPendingChangesAndRefresh();
      } else {
        debugPrint('ProfileScreen: unsaved dialog action=save');
      }

      if (!_controller.hasPendingUnsavedChanges()) return true;
    }

    return true;
  }

  Future<void> _handleBackNavigation() async {
    if (_controller.exitFlowInProgress) return;
    _controller.exitFlowInProgress = true;

    try {
      final canProceed = await _resolveUnsavedChangesIfAny();
      if (!canProceed || !mounted) return;
      Navigator.pop(context);
    } finally {
      _controller.exitFlowInProgress = false;
    }
  }

  Future<void> _saveProfile() async {
    final success = await _controller.saveProfile();
    if (!mounted) return;
    if (success) {
      _showFeedback('Profile updated successfully!', Colors.green);
    } else {
      _showFeedback('Account saved, but some PII details failed.', Colors.orange);
    }
  }

  Future<void> _handleChangePassword() async {
    final canProceed = await _resolveUnsavedChangesIfAny();
    if (!canProceed || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen(fromProfile: true)),
    );
    if (mounted) _showFeedback('Password changed successfully!', Colors.green);
  }

  Future<void> _openCamera() async {
    final canProceed = await _resolveUnsavedChangesIfAny();
    if (!canProceed || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
    );
    if (mounted) await _controller.loadProfile();
  }

  Future<void> _selectDate() async {
    await _controller.selectDate(context);
  }

  void _showFeedback(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  void _onSignaturePanStart(Offset position) {
    setState(() => _controller.signaturePoints.add(position));
  }

  void _onSignaturePanUpdate(Offset position) {
    setState(() => _controller.signaturePoints.add(position));
  }

  void _onSignaturePanEnd() async {
    _controller.signaturePoints.add(null);
    await _controller.finalizeSignature();
  }

  void _onClearExistingSignature() {
    setState(() {
      _controller.signaturePoints = [];
      _controller.signatureBase64 = null;
      _controller.hasExistingSignature = false;
    });
  }

  void _onClearDrawing() {
    setState(() {
      _controller.signaturePoints = [];
      _controller.signatureBase64 = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: _buildAppBar(),
        body: _controller.isLoading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: _handleBackNavigation,
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
                _controller.usernameCtrl.text.isEmpty ? 'User' : _controller.usernameCtrl.text,
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
          icon: _controller.isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
          onPressed: _controller.isSaving ? null : _saveProfile,
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
          ProfileHeaderCard(
            displayName: _controller.displayName,
            username: _controller.usernameCtrl.text,
          ),

          const SizedBox(height: 20),

          const ProfileSectionHeader(title: 'Account Information', icon: Icons.manage_accounts_outlined),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileTextField(label: 'Username', controller: _controller.usernameCtrl, icon: Icons.badge_outlined),
            const ProfileDivider(),
            ProfileReadOnlyRow(icon: Icons.email_outlined, label: 'Email', value: _controller.emailCtrl.text.isEmpty ? '—' : _controller.emailCtrl.text),
            const ProfileDivider(),
            ProfileReadOnlyRow(icon: Icons.phone_android_outlined, label: 'Phone Number', value: _controller.phoneCtrl.text.isEmpty ? '—' : _controller.phoneCtrl.text),
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

          const ProfileSectionHeader(title: 'Personal Information', icon: Icons.badge_outlined),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileTextField(label: 'Last Name', controller: _controller.lastNameCtrl, icon: Icons.person_outline),
            const ProfileDivider(),
            ProfileTextField(label: 'First Name', controller: _controller.firstNameCtrl, icon: Icons.person_outline),
            const ProfileDivider(),
            ProfileTextField(label: 'Middle Name', controller: _controller.middleNameCtrl, icon: Icons.person_outline),
          ]),

          const SizedBox(height: 16),

          const ProfileSectionHeader(title: 'Birth Details', icon: Icons.cake_outlined),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileDateField(value: _controller.dobCtrl.text, onTap: _selectDate),
            const ProfileDivider(),
            ProfileTextField(label: 'Place of Birth', controller: _controller.placeOfBirthCtrl, icon: Icons.location_city_outlined),
          ]),

          const SizedBox(height: 16),

          const ProfileSectionHeader(title: 'Additional Details', icon: Icons.info_outline),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileDropdownField(
              label: 'Sex',
              value: _controller.normalizeGender(_controller.sex),
              icon: Icons.wc_outlined,
              items: const ['Male', 'Female'],
              onChanged: (v) => setState(() => _controller.sex = _controller.normalizeGender(v) ?? ''),
            ),

            const ProfileDivider(),
            ProfileDropdownField(
              label: 'Marital Status',
              value: _controller.maritalStatus.isEmpty ? null : _controller.maritalStatus,
              icon: Icons.favorite_border_outlined,
              items: const ['Single', 'Married', 'Widowed', 'Separated', 'Live-in', 'Minor', 'Annulled'],
              onChanged: (v) => setState(() => _controller.maritalStatus = v ?? ''),
            ),
          ]),

          const SizedBox(height: 16),

          const ProfileSectionHeader(title: 'Address', icon: Icons.home_outlined),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileTextField(
              label: 'Full Address',
              controller: _controller.addressCtrl,
              icon: Icons.map_outlined,
              hint: 'House No., Street, Subdivision, Barangay',
              maxLines: 2,
            ),
          ]),

          const SizedBox(height: 16),

          const ProfileSectionHeader(title: 'Signature', icon: Icons.draw_outlined),
          const SizedBox(height: 4),
          Text(
            'Draw your signature below. It will be saved and used in forms.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          SignaturePadWidget(
            signatureBase64: _controller.signatureBase64,
            hasExistingSignature: _controller.hasExistingSignature,
            signaturePoints: _controller.signaturePoints,
            onClearExisting: _onClearExistingSignature,
            onClearDrawing: _onClearDrawing,
            onPanStart: _onSignaturePanStart,
            onPanUpdate: _onSignaturePanUpdate,
            onPanEnd: _onSignaturePanEnd,
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _controller.isSaving ? null : _saveProfile,
              icon: _controller.isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(
                _controller.isSaving ? 'Saving...' : 'Save Profile',
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

          const ProfileSectionHeader(title: 'Account Settings', icon: Icons.settings_outlined),
          const SizedBox(height: 12),
          ProfileCard(children: [
            ProfileActionRow(
              icon: Icons.lock_reset_outlined,
              label: 'Change Password',
              subtitle: 'Update your account password',
              onTap: _handleChangePassword,
            ),
            const ProfileDivider(),
            ProfileActionRow(
              icon: Icons.shield_outlined,
              label: 'Privacy & Terms',
              subtitle: 'Data Privacy Act of 2012 (R.A. 10173)',
              onTap: () => TermsAndConditionsDialog.showForReading(context),
            ),
            const ProfileDivider(),
            ProfileActionRow(
              icon: Icons.logout,
              label: 'Log Out',
              subtitle: 'Sign out of your account',
              onTap: () => _controller.handleLogout(context),
              isDestructive: true,
            ),
          ]),

          const SizedBox(height: 16),
          Center(child: Text('SapPIIre v1.0.0', style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
        ],
      ),
    );
  }
}
