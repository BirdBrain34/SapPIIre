import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/widgets/custom_button.dart';
import 'package:sappiire/mobile/widgets/custom_text_field.dart';
import 'package:sappiire/mobile/widgets/InfoScannerButton.dart'; 
import 'package:sappiire/mobile/screens/auth/InfoScannerScreen.dart'; 
import 'package:sappiire/models/id_information.dart'; 
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final PageController _pageController = PageController();
  final SupabaseService _supabaseService = SupabaseService();
  
  int _currentPage = 0; // Internal pages: 0 to 4
  bool _isLoading = false;

  // Controllers (All from your original code)
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emailOtpController = TextEditingController(); 
  final TextEditingController _phoneController = TextEditingController(); 
  final TextEditingController _phoneOtpController = TextEditingController(); 
  final TextEditingController _usernameController = TextEditingController(); 
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Re-bind listeners so the "Next" button color updates as you type
    final List<TextEditingController> controllers = [
      _firstNameController, _lastNameController, _dobController, _emailController,
      _emailOtpController, _phoneController, _phoneOtpController, 
      _usernameController, _passwordController, _confirmPasswordController
    ];
    for (var c in controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  // Helper for progress display
  String _getStepTitle() {
    if (_currentPage <= 1) return "Step 1 of 3";
    if (_currentPage <= 3) return "Step 2 of 3";
    return "Step 3 of 3";
  }

  // ORIGINAL DATE PICKER LOGIC
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
        _dobController.text = '${pickedDate.month}/${pickedDate.day}/${pickedDate.year}';
      });
    }
  }

  Future<void> _handleInfoScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InfoScannerScreen()),
    );
    if (result != null && result is IdInformation) {
      setState(() {
        _firstNameController.text = result.firstName;
        _middleNameController.text = result.middleName;
        _lastNameController.text = result.lastName;
        _dobController.text = result.dateOfBirth;
      });
    }
  }

  // Validation Logic for Step Transitions
  bool _isPageValid() {
    switch (_currentPage) {
      case 0: return _firstNameController.text.isNotEmpty && _lastNameController.text.isNotEmpty && _dobController.text.isNotEmpty && _emailController.text.contains('@');
      case 1: return _emailOtpController.text.length >= 4;
      case 2: return _phoneController.text.isNotEmpty;
      case 3: return _phoneOtpController.text.isNotEmpty;
      case 4: return _usernameController.text.isNotEmpty && _passwordController.text == _confirmPasswordController.text && _passwordController.text.isNotEmpty;
      default: return false;
    }
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _onCreateAccount();
    }
  }

  // ORIGINAL ACCOUNT CREATION LOGIC (Now correctly mapped to all controllers)
  Future<void> _onCreateAccount() async {
    setState(() => _isLoading = true);
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

    if (result['success']) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SignUpSuccessScreen(userId: result['user_id'])),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      resizeToAvoidBottomInset: false, // PREVENTS FOOTER JUMPING
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentPage > 0) {
              _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(_getStepTitle(), style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: (_currentPage == 0 && MediaQuery.of(context).viewInsets.bottom == 0) 
          ? Padding(
              padding: const EdgeInsets.only(bottom: 120.0, left: 10.0), 
              child: InfoScannerButton(onTap: _handleInfoScan),
            )
          : null,

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildBasicInfoPage(),
                  _buildEmailVerifyPage(),
                  _buildPhoneInfoPage(),
                  _buildPhoneVerifyPage(),
                  _buildCredentialsPage(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // --- UI PAGES (RESTORED ORIGINAL DATE PICKER UI) ---

  Widget _buildBasicInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Basic Information', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          CustomTextField(hintText: 'First Name', controller: _firstNameController),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Middle Name', controller: _middleNameController),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Last Name', controller: _lastNameController),
          const SizedBox(height: 10),
          
          // RESTORED DATE PICKER UI
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.buttonOutlineBlue, width: 2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.white, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    _dobController.text.isEmpty ? 'Date of Birth' : _dobController.text,
                    style: TextStyle(color: _dobController.text.isEmpty ? AppColors.white.withOpacity(0.6) : AppColors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Email', controller: _emailController),
        ],
      ),
    );
  }

  Widget _buildEmailVerifyPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_read, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          const Text('Verify Email', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("Sent to ${_emailController.text}", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 30),
          CustomTextField(hintText: 'Enter Code', controller: _emailOtpController),
        ],
      ),
    );
  }

  Widget _buildPhoneInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text('Phone Number', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          CustomTextField(hintText: '09XXXXXXXXX', controller: _phoneController),
        ],
      ),
    );
  }

  Widget _buildPhoneVerifyPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sms, size: 80, color: Colors.white),
          const SizedBox(height: 20),
          const Text('Verify Phone', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          CustomTextField(hintText: 'Enter Phone OTP', controller: _phoneOtpController),
        ],
      ),
    );
  }

  Widget _buildCredentialsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Account Credentials', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          CustomTextField(hintText: 'Username', controller: _usernameController, prefixIcon: const Icon(Icons.person, color: Colors.white)),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Password', controller: _passwordController, obscureText: true, prefixIcon: const Icon(Icons.lock, color: Colors.white)),
          const SizedBox(height: 10),
          CustomTextField(hintText: 'Confirm Password', controller: _confirmPasswordController, obscureText: true, prefixIcon: const Icon(Icons.lock, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          if (_isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            CustomButton(
              text: _currentPage == 4 ? 'Create Account' : 'Next',
              onPressed: _isPageValid() ? _nextPage : () {}, 
              backgroundColor: _isPageValid() ? AppColors.white : Colors.grey,
              textColor: AppColors.primaryBlue,
            ),
          const SizedBox(height: 10),
          if (_currentPage > 0)
            TextButton(
              onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
              child: const Text('Back', style: TextStyle(color: Colors.white70)),
            ),
        ],
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