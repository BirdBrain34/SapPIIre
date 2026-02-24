import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';


class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;
  final bool outlineButton;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor = AppColors.highlight, // Default background
    this.textColor = AppColors.white, // Default text color
    this.outlineButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, // Take full width
      height: 50,
      child: outlineButton
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.white, width: 2), // White outline
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                foregroundColor: AppColors.white, // Ripple color
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                foregroundColor: textColor, // Ripple color
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}