import 'package:flutter/material.dart';

class InfoScannerButton extends StatelessWidget {
  final VoidCallback onTap;

  const InfoScannerButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onTap,
      backgroundColor: Color(0xFF42A5F5), 
      elevation: 4,
      child: const Icon(
        Icons.camera_alt, // The white camera icon
        color: Colors.white,
        size: 28,
      ),
    );
  }
}