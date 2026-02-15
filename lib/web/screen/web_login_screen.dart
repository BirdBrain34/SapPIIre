// lib/web/screen/web_login_screen.dart
// Web portal entry point for CSWD Staff.
// Simple worker portal UI — logic uses `WebAuthService` for auth.

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/services/web_auth_service.dart';
import 'package:sappiire/web/screen/web_signup_screen.dart';

class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Staff auth service
  final WebAuthService _authService = WebAuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // LOGIN HANDLER — uses WebAuthService.login
  Future<void> _handleLogin() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your username and password.'),
          backgroundColor: Colors.red,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome, ${result['username']}!'),
          backgroundColor: Colors.green,
        ),
      );
      // ManageFormsScreen takes NO constructor args — keep it exactly as it was
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ManageFormsScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Login failed.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'lib/Logo/sappiire_logo.png',
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              const Text(
                'WORKER PORTAL',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 40),

              // Login Card
              Container(
                width: 450,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Staff Login',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Enter your credentials to access the CSWD dashboard',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 35),

                    // Username
                    CustomTextField(
                      hintText: 'Username',
                      controller: _usernameController,
                      prefixIcon: const Icon(Icons.badge, color: AppColors.white),
                    ),
                    const SizedBox(height: 20),

                    // Password
                    CustomTextField(
                      hintText: 'Password',
                      obscureText: true,
                      controller: _passwordController,
                      prefixIcon: const Icon(Icons.vpn_key, color: AppColors.white),
                    ),

                    const SizedBox(height: 40),

                    // Login Button
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryBlue,
                                ),
                              )
                            : const Text(
                                'LOG IN TO SYSTEM',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        // TODO: implement forgot password flow
                      },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: AppColors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WebSignupScreen()),
                        );
                      },
                      child: const Text(
                        "Don't have an account? Register",
                        style: TextStyle(color: AppColors.white),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),
              const Text(
                '© 2026 City Social Welfare and Development Office',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
