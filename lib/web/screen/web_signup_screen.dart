// lib/web/screen/web_signup_screen.dart
// Web staff signup screen — inserts into staff_accounts and staff_profiles

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';

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
  final SupabaseClient _supabase = Supabase.instance.client;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _handleSignUp() async {
    // Basic validation
    if (_cswdIdController.text.trim().isEmpty ||
        _firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in all required fields.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Passwords do not match.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    if (_passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password must be at least 8 characters.'),
        backgroundColor: Colors.red,
      ));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Username already exists.'),
          backgroundColor: Colors.red,
        ));
        setState(() => _isLoading = false);
        return;
      }

      // 2. Insert into staff_accounts — DO NOT pass cswd_id
      final accountResponse = await _supabase
          .from('staff_accounts')
          .insert({
            'employee_id': _cswdIdController.text.trim(),
            'email': _emailController.text.trim(),
            'username': _usernameController.text.trim(),
            'password_hash': _hashPassword(_passwordController.text),
            'role': 'staff',
            'is_active': true,
          })
          .select('cswd_id')
          .single();

      final String cswdId = accountResponse['cswd_id'].toString();

      // 3. Insert into staff_profiles using returned cswd_id
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
        'email': _emailController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Account created successfully!'),
        backgroundColor: Colors.green,
      ));

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${e.toString()}'),
        backgroundColor: Colors.red,
      ));
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
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      appBar: AppBar(
        title: const Text('Staff Registration'),
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.accentBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  hintText: 'CSWD Employee ID',
                  controller: _cswdIdController,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        hintText: 'First Name',
                        controller: _firstNameController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        hintText: 'Middle Name',
                        controller: _middleNameController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        hintText: 'Last Name',
                        controller: _lastNameController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: CustomTextField(
                        hintText: 'Suffix',
                        controller: _nameSuffixController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        hintText: 'Position',
                        controller: _positionController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        hintText: 'Department',
                        controller: _departmentController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  hintText: 'Phone Number',
                  controller: _phoneController,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  hintText: 'Email Address',
                  controller: _emailController,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  hintText: 'Username',
                  controller: _usernameController,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  hintText: 'Password',
                  obscureText: true,
                  controller: _passwordController,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  hintText: 'Confirm Password',
                  obscureText: true,
                  controller: _confirmPasswordController,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.primaryBlue,
                    ),
                    onPressed: _isLoading ? null : _handleSignUp,
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
                            'CREATE ACCOUNT',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
