import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class LoginFloatingField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  const LoginFloatingField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: AppColors.lightBlue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: AppColors.lightBlue, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.inputBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
