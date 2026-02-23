// lib/web/screen/create_staff_screen.dart
// Dedicated screen for superadmin to create new staff accounts

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/side_menu.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class CreateStaffScreen extends StatefulWidget {
  final String role;
  final String cswd_id;

  const CreateStaffScreen({
    super.key,
    required this.role,
    required this.cswd_id,
  });

  @override
  State<CreateStaffScreen> createState() => _CreateStaffScreenState();
}

class _CreateStaffScreenState extends State<CreateStaffScreen> {
  final _supabase = Supabase.instance.client;

  // Account creation form controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _selectedRole = 'viewer';
  final List<String> _availableRoles = ['viewer', 'form_editor', 'admin'];
  bool _isCreatingAccount = false;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _generateTemporaryPassword() {
    return 'Temp${DateTime.now().millisecondsSinceEpoch}'.substring(0, 12);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  void _clearCreateForm() {
    _firstNameController.clear();
    _lastNameController.clear();
    _emailController.clear();
    _usernameController.clear();
    _positionController.clear();
    _departmentController.clear();
    _phoneController.clear();
    setState(() => _selectedRole = 'viewer');
  }

  Future<void> _createStaffAccount() async {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty) {
      _showSnackBar('Please fill in all required fields.', isError: true);
      return;
    }

    setState(() => _isCreatingAccount = true);

    try {
      // Check username not taken
      final existing = await _supabase
          .from('staff_accounts')
          .select('username')
          .eq('username', _usernameController.text.trim())
          .maybeSingle();

      if (existing != null) {
        _showSnackBar('Username already exists.', isError: true);
        setState(() => _isCreatingAccount = false);
        return;
      }

      // Generate temporary password
      final tempPassword = _generateTemporaryPassword();

      // Insert into staff_accounts
      final accountResponse = await _supabase
          .from('staff_accounts')
          .insert({
            'email': _emailController.text.trim(),
            'username': _usernameController.text.trim(),
            'password_hash': _hashPassword(tempPassword),
            'role': _selectedRole,
            'requested_role': _selectedRole,
            'account_status': 'active',
            'is_active': true,
          })
          .select('cswd_id')
          .single();

      final String? cswdId = accountResponse['cswd_id']?.toString();

      if (cswdId == null || cswdId.isEmpty) {
        _showSnackBar('Account created but failed to get ID. Contact developer.', isError: true);
        setState(() => _isCreatingAccount = false);
        return;
      }

      // Insert into staff_profiles
      await _supabase.from('staff_profiles').insert({
        'cswd_id': cswdId,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'position': _positionController.text.trim().isEmpty ? null : _positionController.text.trim(),
        'department': _departmentController.text.trim().isEmpty ? null : _departmentController.text.trim(),
        'phone_number': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      });

      if (!mounted) return;

      // Show confirmation dialog with credentials
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Account Created Successfully! ✓'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Share these credentials with the staff member:'),
                const SizedBox(height: 20),
                _buildCredentialField('Username', _usernameController.text.trim()),
                const SizedBox(height: 12),
                _buildCredentialField('Temporary Password', tempPassword),
                const SizedBox(height: 20),
                const Text(
                  '⚠️ Note: Save these credentials now. The password will not be displayed again.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      _clearCreateForm();
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isCreatingAccount = false);
    }
  }

  Widget _buildCredentialField(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FE),
      body: Row(
        children: [
          SideMenu(
            activePath: "CreateStaff",
            role: widget.role,
            cswd_id: widget.cswd_id,
            onLogout: () => Navigator.pop(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(35.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Create New Staff Account",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Fill in the form below to create a new staff account. A temporary password will be generated automatically.",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 35),
                    Container(
                      width: 700,
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _firstNameController,
                                  decoration: InputDecoration(
                                    labelText: 'First Name *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _lastNameController,
                                  decoration: InputDecoration(
                                    labelText: 'Last Name *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    labelText: 'Email Address *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    labelText: 'Username *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _positionController,
                                  decoration: InputDecoration(
                                    labelText: 'Position',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _departmentController,
                                  decoration: InputDecoration(
                                    labelText: 'Department',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  decoration: InputDecoration(
                                    labelText: 'Phone Number',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedRole,
                                  decoration: InputDecoration(
                                    labelText: 'Role',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: _availableRoles.map((role) {
                                    return DropdownMenuItem<String>(
                                      value: role,
                                      child: Text(role),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedRole = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _isCreatingAccount ? null : _createStaffAccount,
                              child: _isCreatingAccount
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'CREATE ACCOUNT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
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
        ],
      ),
    );
  }
}
