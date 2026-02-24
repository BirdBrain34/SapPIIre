// lib/web/screen/web_login_screen.dart

import 'package:flutter/material.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/services/web_auth_service.dart';
import 'package:sappiire/web/screen/web_signup_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';

class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final WebAuthService _authService = WebAuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _snack('Please enter your username and password.', error: true);
      return;
    }
    setState(() => _isLoading = true);
    final result = await _authService.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      _snack('Welcome, ${result['username']}!');
      Navigator.push(
        context,
        ContentFadeRoute(
          page: ManageFormsScreen(
            cswd_id: result['cswd_id'] ?? '',
            role: result['role'] ?? 'viewer',
          ),
        ),
      );
    } else {
      _snack(result['message'] ?? 'Login failed.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFE63946) : const Color(0xFF2EC4B6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Deep navy — primary brand blue
      backgroundColor: const Color(0xFF0D1B4E),
      body: Row(
        children: [
          // ── LEFT: branding panel ──────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D1B4E), // deep navy
                    Color(0xFF1A3A8F), // rich blue
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
                      // Logo + app name
                      Image.asset('lib/Logo/sappiire_logo.png', height: 80),
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
                          color: Color(0xFF8BAEE0), // muted light blue
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Feature chips
                      _featureRow(Icons.enhanced_encryption_outlined,
                          'Hybrid cryptosystem PII protection'),
                      const SizedBox(height: 16),
                      _featureRow(Icons.qr_code_2_outlined,
                          'QR-based autofill for fast intake'),
                      const SizedBox(height: 16),
                      _featureRow(Icons.admin_panel_settings_outlined,
                          'Role-based staff access control'),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── RIGHT: login card ─────────────────────────────────────
          Container(
            width: 460,
            decoration: const BoxDecoration(
              // Slightly lighter blue-navy for contrast
              color: Color(0xFF152257),
              boxShadow: [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 40,
                  offset: Offset(-8, 0),
                ),
              ],
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
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
                      style: TextStyle(
                        color: Color(0xFF8BAEE0),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Username field
                    _fieldLabel('Username'),
                    const SizedBox(height: 8),
                    _styledField(
                      controller: _usernameController,
                      hint: 'Enter your username',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 20),

                    // Password field
                    _fieldLabel('Password'),
                    const SizedBox(height: 8),
                    _styledField(
                      controller: _passwordController,
                      hint: 'Enter your password',
                      icon: Icons.lock_outline,
                      obscure: true,
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Color(0xFF6EA8FE),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          // Gold/amber accent — complementary to blue (color theory)
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

                    const SizedBox(height: 24),
                    // Divider
                    Row(children: [
                      const Expanded(child: Divider(color: Color(0xFF2A3F7A))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style: TextStyle(
                                color: Color(0xFF8BAEE0), fontSize: 13)),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2A3F7A))),
                    ]),
                    const SizedBox(height: 20),

                    // Register button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2A3F7A), width: 1.5),
                          foregroundColor: const Color(0xFF8BAEE0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          ContentFadeRoute(page: const WebSignupScreen()),
                        ),
                        child: const Text(
                          "Don't have an account? Register",
                          style: TextStyle(fontSize: 14),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

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

  /// Custom field styled for dark blue background — fully visible
  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B4E), // darkest navy for contrast
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3F7A), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF4A6499), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF6EA8FE), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

