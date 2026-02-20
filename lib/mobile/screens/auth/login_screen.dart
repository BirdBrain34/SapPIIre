import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/mobile/screens/auth/signup_screen.dart';
import 'package:sappiire/mobile/screens/auth/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Authenticate user with Supabase and navigate to ManageInfoScreen
  Future<void> _onLoginPressed() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter username and password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Call authentication service
    final result = await _authService.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    // Navigate to main screen on success
    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${result['username']}!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ManageInfoScreen(userId: result['user_id']),
        ),
      );
    } else {
      // Show error message on failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Image.asset(
                'lib/logo/sappiire_logo.png',
                height: 250,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 3),

              const Text(
                'Secured autofill application of\nPersonally Identifiable Information',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The efficient way to fill forms, and data safe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'LOG IN',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    SizedBox(
                      height: 45,
                      child: CustomTextField(
                        hintText: 'Username',
                        controller: _usernameController,
                        prefixIcon: const Icon(
                          Icons.person,
                          color: AppColors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      height: 45,
                      child: CustomTextField(
                        hintText: 'Password',
                        obscureText: true,
                        controller: _passwordController,
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: AppColors.white,
                          size: 18,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : SizedBox(
                            height: 40,
                            width: double.infinity,
                            child: CustomButton(
                              text: 'Log in',
                              onPressed: _onLoginPressed,
                              backgroundColor: Colors.white,
                              textColor: Colors.black,
                            ),
                          ),

                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.white)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.white)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    SizedBox(
                      height: 40,
                      width: double.infinity,
                      child: CustomButton(
                        text: 'Sign up',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignUpScreen(),
                            ),
                          );
                        },
                        backgroundColor: Colors.transparent,
                        outlineButton: true,
                        textColor: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
