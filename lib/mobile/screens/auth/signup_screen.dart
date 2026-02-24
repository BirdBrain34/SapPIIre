import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Create new user account in Supabase with profile data
  Future<void> _onCreateAccount() async {
    if (_dobController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your date of birth'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);

      // Call signup service with user data
      final result = await _supabaseService.signUp(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        email: _emailController.text.trim(),
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        dateOfBirth: _dobController.text,
        phoneNumber: _phoneController.text.trim(),
      );

      setState(() => _isLoading = false);

      if (!mounted) return;

      // Navigate to success screen on successful signup
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignUpSuccessScreen(userId: result['user_id']),
          ),
        );
      } else {
        // Show error message on failure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _nonEmptyValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+");
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _passwordMatchValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  // Open date picker and format selected date as MM/DD/YYYY
  Future<void> _selectDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A237E),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _dobController.text =
            '${pickedDate.month}/${pickedDate.day}/${pickedDate.year}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // This line turns the back arrow (and all other icons in the bar) white
          iconTheme: const IconThemeData(color: Colors.white), 
          title: const Text(
            'Sign Up',
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Basic Information',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'First Name',
                  controller: _firstNameController,
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Middle Name',
                  controller: _middleNameController,
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Last Name',
                  controller: _lastNameController,
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _selectDate,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.buttonOutlineBlue,
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          color: AppColors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _dobController.text.isEmpty
                                ? 'Date of Birth'
                                : _dobController.text,
                            style: TextStyle(
                              color: _dobController.text.isEmpty
                                  ? AppColors.white.withOpacity(0.6)
                                  : AppColors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Email',
                  controller: _emailController,
                  validator: _emailValidator,
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Phone Number (09XXXXXXXXX)',
                  controller: _phoneController,
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 20),

                const Text(
                  'Account Credentials',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Username',
                  controller: _usernameController,
                  prefixIcon: const Icon(
                    Icons.person,
                    color: AppColors.white,
                    size: 18,
                  ),
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  prefixIcon: const Icon(
                    Icons.lock,
                    color: AppColors.white,
                    size: 18,
                  ),
                  validator: _nonEmptyValidator,
                ),
                const SizedBox(height: 10),
                CustomTextField(
                  hintText: 'Confirm Password',
                  controller: _confirmPasswordController,
                  obscureText: true,
                  prefixIcon: const Icon(
                    Icons.lock,
                    color: AppColors.white,
                    size: 18,
                  ),
                  validator: _passwordMatchValidator,
                ),
                const SizedBox(height: 30),

                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : CustomButton(
                        text: 'Create Account',
                        onPressed: _onCreateAccount,
                        backgroundColor: AppColors.white,
                        textColor: AppColors.primaryBlue,
                      ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.white)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'or',
                        style: TextStyle(color: AppColors.white),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.white)),
                  ],
                ),
                const SizedBox(height: 10),
                CustomButton(
                  text: 'Back to login',
                  onPressed: () => Navigator.pop(context),
                  outlineButton: true,
                  backgroundColor: Colors.transparent,
                  textColor: AppColors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignUpSuccessScreen extends StatelessWidget {
  final String userId;

  const SignUpSuccessScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 80,
              ),
              const SizedBox(height: 20),
              const Text(
                'All signed up!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome to SapPIIre Autofill App',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.white, fontSize: 16),
              ),
              const SizedBox(height: 30),
              CustomButton(
                text: 'Proceed',
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageInfoScreen(userId: userId),
                    ),
                  );
                },
                backgroundColor: AppColors.white,
                textColor: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}