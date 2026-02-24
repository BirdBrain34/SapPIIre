import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class NextButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const NextButton({super.key, required this.onTap, this.label = "Next"});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
        ],
      ),
    );
  }
}