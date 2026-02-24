import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/mobile/screens/auth/signup_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.dangerRed : AppColors.successGreen,
    ));
  }

  Future<void> _onLoginPressed() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _snack('Please enter username and password', error: true);
      return;
    }
    setState(() => _isLoading = true);
    final result = await _supabaseService.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      _snack('Welcome back, ${result['username']}!');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ManageInfoScreen(userId: result['user_id'])),
      );
    } else {
      _snack(result['message'], error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use ResizeToAvoidBottomInset to prevent keyboard from breaking layout
      resizeToAvoidBottomInset: false, 
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryBlue, AppColors.midBlue],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Centers the content vertically
              children: [
                // 1. Reduced Logo Size to fit screen without scrolling
                Image.asset(
                  'lib/logo/sappiire_logo.png',
                  height: 200, 
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                const Text(
                  'The efficient way to fill forms, and data safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 24),

                // 2. The Login Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // Prevents card from expanding
                    children: [
                      const Text(
                        'Sign In', 
                        style: TextStyle(
                          color: Colors.white, 
                          fontSize: 20, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),

                      _fieldLabel("Username"),
                      const SizedBox(height: 6),
                      _buildStyledField(
                        controller: _usernameController,
                        hint: 'Enter your username',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel("Password"),
                      const SizedBox(height: 6),
                      _buildStyledField(
                        controller: _passwordController,
                        hint: 'Enter your password',
                        icon: Icons.lock_outline,
                        obscure: true,
                      ),
                      
                      // 3. Added Forgot Account Link (Right Aligned)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // No functionality yet
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text(
                            'Forgot account?',
                            style: TextStyle(
                              color: AppColors.lightBlue,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onLoginPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.highlight,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _isLoading 
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Log In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),

                      const SizedBox(height: 16),
                      _buildDivider(),
                      const SizedBox(height: 16),

                      // Register Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.borderNavy, width: 1.5),
                            foregroundColor: AppColors.mutedBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Sign Up"),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Helpers ---

  Widget _fieldLabel(String text) => Text(
        text, 
        style: const TextStyle(
          color: AppColors.labelBlue, 
          fontSize: 12, 
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildStyledField({required TextEditingController controller, required String hint, required IconData icon, bool obscure = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg, 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderNavy, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.hintText, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.lightBlue, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.borderNavy)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12), 
          child: Text('or', style: TextStyle(color: AppColors.mutedBlue, fontSize: 12)),
        ),
        Expanded(child: Divider(color: AppColors.borderNavy)),
      ],
    );
  }
}