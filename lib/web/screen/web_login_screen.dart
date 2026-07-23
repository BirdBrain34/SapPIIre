// lib/web/screen/web_login_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sappiire/web/screen/first_login_password_screen.dart';
import 'package:sappiire/web/screen/forgot_password_screen.dart';
import 'package:sappiire/web/screen/new_staff_setup_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/web/utils/page_transitions.dart';

class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final WebAuthService _authService = WebAuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _capsLockOn = false;

  @override
  void initState() {
    super.initState();
    _passwordFocus.addListener(_onPasswordFocusChange);
  }

  @override
  void dispose() {
    _passwordFocus.removeListener(_onPasswordFocusChange);
    _passwordFocus.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  KeyEventResult _onHardwareKey(KeyEvent event) {
    if (!_passwordFocus.hasFocus) return KeyEventResult.ignored;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.capsLock) {
      _setCapsLock(!_capsLockOn);
    }
    return KeyEventResult.ignored;
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocus.hasFocus) {
      _setCapsLock(false);
    }
  }

  void _setCapsLock(bool on) {
    if (on != _capsLockOn) {
      setState(() => _capsLockOn = on);
    }
  }

  Future<void> _handleLogin() async {
    if (_identifierController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _snack('Please enter your login identifier and password.', error: true);
      return;
    }
    setState(() => _isLoading = true);
    final result = await _authService.login(
      loginIdentifier: _identifierController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      _snack('Welcome, ${result['username']}!');
      final bool isFirstLogin = result['is_first_login'] == true;

      // Persist the session so it survives tab refreshes.
      await _authService.saveSession(
        cswdId: result['cswd_id'] ?? '',
        username: result['username'] ?? '',
        email: result['email'] ?? '',
        role: result['role'] ?? 'admin',
        displayName: result['display_name'] ?? result['username'] ?? '',
      );

      if (isFirstLogin) {
        if (!mounted) return;
        Navigator.push(
          context,
          ContentFadeRoute(
            page: FirstLoginPasswordScreen(
              cswdId: result['cswd_id'] ?? '',
              role: result['role'] ?? 'admin',
              displayName: result['display_name'] ?? result['username'] ?? '',
              username: result['username'] ?? '',
            ),
          ),
        );
      } else {
        if (!mounted) return;
        Navigator.push(
          context,
          ContentFadeRoute(
            page: ManageFormsScreen(
              cswdId: result['cswd_id'] ?? '',
              role: result['role'] ?? 'admin',
              displayName: result['display_name'] ?? result['username'] ?? '',
            ),
          ),
        );
      }
    } else {
      _snack(result['message'] ?? 'Login failed.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error
            ? const Color(0xFFE63946)
            : const Color(0xFF2EC4B6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= 900) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1B4E),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _buildLoginPanel(isCompact: true),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B4E),
      body: Row(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D1B4E),
                    Color(0xFF1A3A8F),
                  ],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/Logo/sappiire_logo.png', height: 80),
                      const SizedBox(height: 28),
                      const Text(
                        'SapPIIre',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'City Social Welfare &\nDevelopment Office Portal',
                        style: TextStyle(
                          color: Color(0xFF8BAEE0),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 48),
                      _featureRow(
                        Icons.enhanced_encryption_outlined,
                        'Hybrid cryptosystem PII protection',
                      ),
                      const SizedBox(height: 16),
                      _featureRow(
                        Icons.qr_code_2_outlined,
                        'QR-based autofill for fast intake',
                      ),
                      const SizedBox(height: 16),
                      _featureRow(
                        Icons.admin_panel_settings_outlined,
                        'Role-based staff access control',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 460,
            decoration: const BoxDecoration(
              color: Color(0xFF152257),
              boxShadow: [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 40,
                  offset: Offset(-8, 0),
                ),
              ],
            ),
            child: Center(child: _buildLoginPanel(isCompact: false)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPanel({required bool isCompact}) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 24 : 48,
        vertical: isCompact ? 28 : 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to access the staff dashboard',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(0xFF8BAEE0), fontSize: 14),
          ),
          const SizedBox(height: 40),
          _fieldLabel('Email'),
          const SizedBox(height: 8),
          _styledField(
            controller: _identifierController,
            hint: 'Email',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
          ),
          const SizedBox(height: 20),
          _fieldLabel('Password'),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    _setCapsLock(false);
                  }
                },
                child: _buildPasswordField(),
              ),
              if (_capsLockOn)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFFFFD54F),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Caps Lock is ON \u2014 passwords are case-sensitive',
                        style: TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 0,
            children: [
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  ContentFadeRoute(page: const NewStaffSetupScreen()),
                ),
                child: const Text(
                  'New staff? Set your password',
                  style: TextStyle(color: Color(0xFF6EA8FE), fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  ContentFadeRoute(page: const ForgotPasswordScreen()),
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(color: Color(0xFF8BAEE0), fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C8BF5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Log In to System',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 36),
          const Center(
            child: Text(
              '© 2026 City Social Welfare and Development Office\nSanta Rosa City',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF3D5A99),
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Password field with eye toggle suffix icon.
  Widget _buildPasswordField() {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _onHardwareKey,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B4E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A3F7A), width: 1.5),
        ),
        child: TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _isLoading ? null : _handleLogin(),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: const TextStyle(color: Color(0xFF4A6499), fontSize: 14),
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6EA8FE), size: 20),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF6EA8FE),
                size: 20,
              ),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB8CCF0),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B4E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3F7A), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onEditingComplete: () {
          if (controller == _identifierController) {
            FocusScope.of(context).requestFocus(_passwordFocus);
          }
        },
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A6499), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF6EA8FE), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3570),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF6EA8FE), size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF8BAEE0),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}