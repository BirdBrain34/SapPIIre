// Mobile Manage Info Screen
// Loads templates + profile, renders dynamic form, saves to Supabase,
// and transmits selected fields to the web portal via QR.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/mobile/controllers/manage_info_controller.dart';
import 'package:sappiire/mobile/screens/auth/qr_scanner_screen.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart';
import 'package:sappiire/mobile/screens/auth/ProfileScreen.dart';
import 'package:sappiire/mobile/screens/auth/HistoryScreen.dart';
import 'package:sappiire/mobile/widgets/form_popup.dart'; // ← NEW

class ManageInfoScreen extends StatefulWidget {
  final String userId;
  const ManageInfoScreen({super.key, required this.userId});

  @override
  State<ManageInfoScreen> createState() => _ManageInfoScreenState();
}

class _ManageInfoScreenState extends State<ManageInfoScreen> {
  final _supabaseService = SupabaseService();
  final _supabase = Supabase.instance.client; // ← NEW: for popup fetch
  late final ManageInfoController _controller;
  int _currentNavIndex = 0;
  String? _activeTransmitSessionId;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _controller = ManageInfoController(userId: widget.userId);
    _loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────
  Future<void> _loadAll() async {
    await _controller.loadAll(forceRefresh: true);
  }

  // ── Save to Supabase ──────────────────────────────────────
  Future<void> _saveProfile() async {
    final ok = await _controller.saveProfile();
    if (!mounted) return;
    if (ok) {
      _showFeedback('Profile saved!', Colors.green);
    } else {
      _showFeedback(
        'Save failed: ${_controller.errorMessage ?? 'Unknown error'}',
        Colors.red,
      );
    }
  }

  // ── QR Transmit ───────────────────────────────────────────
  Future<void> _scanAndTransmit() async {
    final dataToTransmit = _controller.buildTransmitPayload();
    if (dataToTransmit == null) {
      _showFeedback(
        'Please select at least one field to transmit',
        AppColors.dangerRed,
      );
      return;
    }

    // ── NEW: check if selected form has a popup configured ──
    final templateId = _controller.selectedTemplate?.templateId;
    if (templateId != null) {
      try {
        final row = await _supabase
            .from('form_templates')
            .select('popup_enabled, popup_subtitle, popup_description, form_name')
            .eq('template_id', templateId)
            .maybeSingle();

        final popupEnabled = (row?['popup_enabled'] as bool?) ?? false;

        if (popupEnabled && mounted) {
          final proceed = await FormIntroPopupDialog.show(
            context: context,
            formTitle: (row?['form_name'] as String?) ??
                _controller.selectedTemplate?.formName ??
                'Form',
            subtitle: row?['popup_subtitle'] as String?,
            description: row?['popup_description'] as String?,
          );

          // User tapped Cancel — abort the QR scan entirely
          if (!proceed || !mounted) return;
        }
      } catch (e) {
        // If the fetch fails, silently skip the popup and continue
        debugPrint('Popup fetch error: $e');
      }
    }
    // ── END NEW ─────────────────────────────────────────────

    final sessionId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          transmitData: dataToTransmit,
          userId: widget.userId,
        ),
      ),
    );

    if (sessionId != null && mounted) {
      // Guard: if one scan result is already being synced, ignore duplicates.
      if (_activeTransmitSessionId != null) {
        debugPrint(
          'Ignoring duplicate QR session result: $sessionId (active: $_activeTransmitSessionId)',
        );
        return;
      }

      _activeTransmitSessionId = sessionId;
      
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Transmitting data...'),
              ],
            ),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      try {
        // Add a small delay to ensure web subscription is ready
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Push field values + JSONB to web session
        final success = await _supabaseService.sendDataToWebSession(
          sessionId,
          dataToTransmit,
          userId: widget.userId,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          _showFeedback(
            success ? 'Data transmitted successfully!' : 'Failed to send data. Please try again.',
            success ? Colors.green : Colors.red,
          );
        }
      } catch (e) {
        debugPrint('Transmission error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          _showFeedback(
            'Error: ${e.toString()}',
            Colors.red,
          );
        }
      } finally {
        _activeTransmitSessionId = null;
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────
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

  // ── Navigation ────────────────────────────────────────────
  void _onNavTap(int index) {
    switch (index) {
      case 0:
        setState(() => _currentNavIndex = 0);
        break;
      case 1:
        // AutoFill QR — show popup (if configured) then transmit
        setState(() => _currentNavIndex = 1);
        _scanAndTransmit().then((_) {
          if (mounted) setState(() => _currentNavIndex = 0);
        });
        break;
      case 2:
        setState(() => _currentNavIndex = 2);
        break;
    }
  }

  // ── Camera Scanner ────────────────────────────────────────
  Future<void> _openCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InfoScannerScreen()),
    );
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
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
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
                      backgroundColor: AppColors.dangerRed),
                  child: const Text('Log Out',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            await Supabase.instance.client.auth.signOut();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBg,
          appBar: _buildAppBar(),
          floatingActionButton:
              (_controller.formController != null && _currentNavIndex == 0)
              ? _buildSelectAllFAB()
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: _buildBottomNav(),
          body: _currentNavIndex == 2
              ? HistoryScreen(userId: widget.userId, embedded: true)
              : _controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _controller.templates.isEmpty
              ? _buildEmptyState()
              : _buildFormContent(),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 22),
        onPressed: _handleLogout,
        tooltip: 'Log out',
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: widget.userId),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome back,',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    _controller.username.isEmpty
                        ? 'User'
                        : _controller.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.camera_alt_outlined,
            color: Colors.white,
            size: 22,
          ),
          onPressed: _openCamera,
          tooltip: 'Scan ID',
        ),
        IconButton(
          icon: _controller.isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, color: Colors.white, size: 22),
          onPressed: _controller.isSaving ? null : _saveProfile,
          tooltip: 'Save Profile',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Empty / error state ───────────────────────────────────
  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'No forms available.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main form content ─────────────────────────────────────
  Widget _buildFormContent() {
    return Column(
      children: [
        _buildFormSelector(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: AppColors.primaryBlue,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              child: _controller.formController == null
                  ? const Center(child: CircularProgressIndicator())
                  : DynamicFormRenderer(
                      template: _controller.selectedTemplate!,
                      controller: _controller.formController!,
                      mode: 'mobile',
                      showCheckboxes: true,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormSelector() {
    return Container(
      color: AppColors.primaryBlue.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Form:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDDDDEE)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _controller.selectedTemplate?.templateId,
                  isExpanded: true,
                  items: _controller.templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.templateId,
                          child: Text(
                            t.formName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) async {
                    if (id == null) return;
                    await _controller.switchTemplate(id);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Select All Button ────────────────────────────
  Widget _buildSelectAllFAB() {
    final isSelectAll = _controller.formController?.selectAll ?? false;
    return FloatingActionButton.extended(
      onPressed: () {
        _controller.formController?.setSelectAll(!isSelectAll);
        setState(() {});
      },
      backgroundColor:
          isSelectAll ? AppColors.highlight : AppColors.primaryBlue,
      elevation: 6,
      icon: Icon(
        isSelectAll ? Icons.deselect_rounded : Icons.select_all_rounded,
        color: Colors.white,
        size: 20,
      ),
      label: Text(
        isSelectAll ? 'Deselect All' : 'Select All',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.edit_document, 'Manage Info'),
              _buildNavItem(1, Icons.qr_code_scanner, 'Autofill QR'),
              _buildNavItem(2, Icons.history, 'History'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentNavIndex == index;
    return InkWell(
      onTap: () => _onNavTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == 1)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  icon,
                  color:
                      isActive ? AppColors.highlight : AppColors.primaryBlue,
                  size: 24,
                ),
              )
            else
              Icon(
                icon,
                color: isActive ? AppColors.highlight : Colors.white60,
                size: 24,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.highlight : Colors.white60,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}