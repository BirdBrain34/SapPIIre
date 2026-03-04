import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class CustomTextField extends StatelessWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController? controller;
  final Icon? prefixIcon;
  final FormFieldValidator<String>? validator;
  final bool isDarkBackground;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  const CustomTextField({
    super.key,
    required this.hintText,
    this.obscureText = false,
    this.controller,
    this.prefixIcon,
    this.validator,
    this.isDarkBackground = true,
    this.focusNode,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    // Adjust colors based on background (dark or light)
    final Color contentColor = isDarkBackground ? Colors.white : AppColors.primaryBlue;
    final Color fillColor = isDarkBackground 
        ? Colors.white.withOpacity(0.15) 
        : const Color.fromARGB(255, 255, 255, 255).withOpacity(0.1);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: contentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        validator: validator,
        onFieldSubmitted: onSubmitted,
        textInputAction: textInputAction,
        style: TextStyle(color: contentColor, fontSize: 14), 
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: contentColor.withOpacity(0.5),
          ),
          prefixIcon: prefixIcon != null 
              ? Icon(prefixIcon!.icon, color: contentColor.withOpacity(0.7)) 
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}