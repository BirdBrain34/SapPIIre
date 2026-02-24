// lib/web/screen/web_signup_screen.dart
// Web staff signup screen — inserts into staff_accounts and staff_profiles

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sappiire/constants/app_colors.dart';

class WebSignupScreen extends StatefulWidget {
  const WebSignupScreen({super.key});

  @override
  State<WebSignupScreen> createState() => _WebSignupScreenState();
}

class _WebSignupScreenState extends State<WebSignupScreen> {
  final TextEditingController _cswdIdController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nameSuffixController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String _selectedRequestedRole = 'viewer';
  final List<String> _requestedRoles = ['viewer', 'form_editor'];
  final SupabaseClient _supabase = Supabase.instance.client;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.dangerRed : AppColors.successGreen,
    ));
  }

  Future<void> _handleSignUp() async {
    // Basic validation
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all required fields.', isError: true);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    if (_passwordController.text.length < 8) {
      _showSnackBar('Password must be at least 8 characters.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Check username not taken
      final existing = await _supabase
          .from('staff_accounts')
          .select('username')
          .eq('username', _usernameController.text.trim())
          .maybeSingle();

      if (existing != null) {
        _showSnackBar('Username already exists.', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      // 2. Insert into staff_accounts and get back cswd_id
      final accountResponse = await _supabase
          .from('staff_accounts')
          .insert({
            'employee_id': _cswdIdController.text.trim().isEmpty
                ? null
                : _cswdIdController.text.trim(),
            'email': _emailController.text.trim(),
            'username': _usernameController.text.trim(),
            'password_hash': _hashPassword(_passwordController.text),
            'role': 'viewer',           // always starts as viewer, never admin
            'requested_role': _selectedRequestedRole, // what they want
            'account_status': 'pending', // admin must approve
            'is_active': false,          // cannot log in until approved
          })
          .select('cswd_id')
          .single();

      // 3. Guard — make sure we actually got the cswd_id back
      final String? cswdId = accountResponse['cswd_id']?.toString();

      if (cswdId == null || cswdId.isEmpty) {
        _showSnackBar(
          'Account created but failed to get ID. Contact developer.',
          isError: true,
        );
        setState(() => _isLoading = false);
        return;
      }

      // 4. Insert into staff_profiles using the cswd_id
      await _supabase.from('staff_profiles').insert({
        'cswd_id': cswdId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim().isEmpty
            ? null
            : _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'name_suffix': _nameSuffixController.text.trim().isEmpty
            ? null
            : _nameSuffixController.text.trim(),
        'position': _positionController.text.trim(),
        'department': _departmentController.text.trim(),
        'phone_number': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      });

      if (!mounted) return;
      _showSnackBar('Account created successfully!', isError: false);

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // Show the FULL error so you can see exactly what failed
      _showSnackBar('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _cswdIdController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nameSuffixController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: screenWidth > 900
          ? _buildDesktopLayout()
          : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // ── Left Panel: Branding ──────────────────────────────────
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1B4E), Color(0xFF1A3A8F)],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Image.asset('lib/Logo/sappiire_logo.png', height: 64),
                    const SizedBox(height: 24),
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
                      'Join the Portal',
                      style: TextStyle(
                        color: AppColors.lightBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 48),
                    _buildFeatureChip('🔐', 'Secure Access'),
                    const SizedBox(height: 16),
                    _buildFeatureChip('📋', 'Form Management'),
                    const SizedBox(height: 16),
                    _buildFeatureChip('👥', 'Team Collaboration'),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Right Panel: Registration Form ────────────────────────
        Expanded(
          child: Container(
            color: Color(0xFF152257),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Register as a team member',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _styledField('CSWD Employee ID', _cswdIdController, false),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _styledField('First Name', _firstNameController, false),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _styledField('Middle Name', _middleNameController, false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _styledField('Last Name', _lastNameController, false),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: _styledField('Suffix', _nameSuffixController, false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _styledField('Position', _positionController, false),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _styledField('Department', _departmentController, false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _styledField('Phone Number', _phoneController, false),
                      const SizedBox(height: 16),
                      _styledField('Email Address', _emailController, false),
                      const SizedBox(height: 16),
                      _styledField('Username', _usernameController, false),
                      const SizedBox(height: 16),
                      _buildRoleDropdown(),
                      const SizedBox(height: 16),
                      _styledField('Password', _passwordController, true),
                      const SizedBox(height: 16),
                      _styledField('Confirm Password', _confirmPasswordController, true),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.highlight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleSignUp,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'CREATE ACCOUNT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                color: AppColors.highlight,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('lib/Logo/sappiire_logo.png', height: 48),
              const SizedBox(height: 16),
              const Text(
                'Create Account',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _styledField('CSWD Employee ID', _cswdIdController, false),
              const SizedBox(height: 16),
              _styledField('First Name', _firstNameController, false),
              const SizedBox(height: 16),
              _styledField('Middle Name', _middleNameController, false),
              const SizedBox(height: 16),
              _styledField('Last Name', _lastNameController, false),
              const SizedBox(height: 16),
              _styledField('Suffix', _nameSuffixController, false),
              const SizedBox(height: 16),
              _styledField('Position', _positionController, false),
              const SizedBox(height: 16),
              _styledField('Department', _departmentController, false),
              const SizedBox(height: 16),
              _styledField('Phone Number', _phoneController, false),
              const SizedBox(height: 16),
              _styledField('Email Address', _emailController, false),
              const SizedBox(height: 16),
              _styledField('Username', _usernameController, false),
              const SizedBox(height: 16),
              _buildRoleDropdown(),
              const SizedBox(height: 16),
              _styledField('Password', _passwordController, true),
              const SizedBox(height: 16),
              _styledField('Confirm Password', _confirmPasswordController, true),
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleSignUp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Sign in',
                      style: TextStyle(
                        color: AppColors.highlight,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styledField(
    String label,
    TextEditingController controller,
    bool obscure,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Color(0xFF0D1B4E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF4C8BF5),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF4C8BF5),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF6EA8FE),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            hintStyle: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
          cursorColor: AppColors.highlight,
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REQUESTED ROLE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedRequestedRole,
          dropdownColor: Color(0xFF0D1B4E),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Color(0xFF0D1B4E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF4C8BF5),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF4C8BF5),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF6EA8FE),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          items: _requestedRoles.map((role) {
            return DropdownMenuItem<String>(
              value: role,
              child: Text(role),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedRequestedRole = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildFeatureChip(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.lightBlue.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
