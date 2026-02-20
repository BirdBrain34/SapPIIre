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
      backgroundColor: isError ? Colors.red : Colors.green,
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
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      appBar: AppBar(
        title: const Text('Staff Registration'),
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color:AppColors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(
          color: AppColors.white,
        )
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
                DropdownButtonFormField<String>(
                  value: _selectedRequestedRole,
                  decoration: InputDecoration(
                    labelText: 'Requested Role',
                    labelStyle: const TextStyle(color: AppColors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.grey),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.grey),
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
