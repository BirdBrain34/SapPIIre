import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/mobile/screens/auth/signup_screen.dart';
import 'package:sappiire/mobile/screens/auth/ChangePIN.dart';
import 'package:sappiire/services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = false;
  String _pin = '';
  bool _showIdentifier = true;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.dangerRed : AppColors.successGreen,
    ));
  }

  void _onKeyPress(String key) {
    if (_pin.length >= 6) return;
    setState(() => _pin += key);
    if (_pin.length == 6) _onLoginPressed();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onContinueIdentifier() {
    if (_identifierController.text.trim().isEmpty) {
      _snack('Please enter your username, email, or phone number', error: true);
      return;
    }
    setState(() { _showIdentifier = false; _pin = ''; });
  }

  Future<void> _onLoginPressed() async {
    if (_pin.length < 6) return;
    setState(() => _isLoading = true);

    final result = await _supabaseService.loginWithPin(
      identifier: _identifierController.text.trim(),
      pin: _pin,
    );

    if (!mounted) return;
    setState(() { _isLoading = false; if (!result['success!']) _pin = ''; });

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
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryBlue, AppColors.midBlue],
          ),
        ),
        child: SafeArea(child: _showIdentifier ? _buildIdentifierStep() : _buildPinStep()),
      ),
    );
  }

  Widget _buildIdentifierStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('lib/logo/sappiire_logo.png', height: 160, fit: BoxFit.contain),
          const SizedBox(height: 8),
          const Text(
            'The efficient way to fill forms, and data safe.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.accentBlue,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Enter your username, email, or phone number.', style: TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 20),
                const Text('Username / Email / Phone',
                    style: TextStyle(color: AppColors.labelBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _buildStyledField(
                  controller: _identifierController,
                  hint: 'e.g. john_doe, john@email.com, 09XX',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _onContinueIdentifier,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.highlight,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                _buildDivider(),
                const SizedBox(height: 16),
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
                    child: const Text('Sign Up'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() { _showIdentifier = true; _pin = ''; }),
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(_identifierController.text.trim(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Enter your 6-digit PIN', style: TextStyle(color: Colors.white60, fontSize: 14)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 16 : 14, height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.white : Colors.white.withOpacity(0.25),
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 24,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              _buildKeypad(),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinScreen())),
                child: const Text('Forgot PIN?', style: TextStyle(color: AppColors.lightBlue, fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad() {
    const keys = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: keys.map((row) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((key) => key.isEmpty
              ? const SizedBox(width: 72, height: 72)
              : _buildKey(key)).toList(),
        )).toList(),
      ),
    );
  }

  Widget _buildKey(String key) {
    final isDelete = key == '⌫';
    return GestureDetector(
      onTap: () => isDelete ? _onDelete() : _onKeyPress(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72, height: 72,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDelete ? Colors.transparent : Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
          border: isDelete ? null : Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Center(
          child: isDelete
              ? const Icon(Icons.backspace_outlined, color: Colors.white70, size: 22)
              : Text(key, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildStyledField({required TextEditingController controller, required String hint, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderNavy, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onSubmitted: (_) => _onContinueIdentifier(),
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
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.borderNavy)),
      Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: AppColors.mutedBlue, fontSize: 12))),
      Expanded(child: Divider(color: AppColors.borderNavy)),
    ]);
  }
}