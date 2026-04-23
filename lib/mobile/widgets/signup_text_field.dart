import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class SignupTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool enabled;

  const SignupTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.suffixIcon,
    this.keyboardType,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      enabled: enabled,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.lightBlue, fontSize: 12, fontWeight: FontWeight.w600),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.lightBlue, size: 20) : null,
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderNavy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
