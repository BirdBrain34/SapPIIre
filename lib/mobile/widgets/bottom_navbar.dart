import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sappiire/constants/app_colors.dart'; // Ensure this path is correct

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Main Navigation Bar
          Container(
            height: 85,
            decoration: const BoxDecoration(
              color: AppColors.primaryBlue, // Updated to your brand Blue
              border: Border(
                top: BorderSide(
                  color: Colors.white24, // Subtle white border
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _navItem(0, HugeIcons.strokeRoundedUser, "Manage Info"),
                ),
                const Expanded(
                  child: SizedBox(), // Middle spacer for the QR button
                ),
                Expanded(
                  child: _navItem(2, HugeIcons.strokeRoundedClock01, "Fill History"),
                ),
              ],
            ),
          ),

          // Pop-out QR Code Button
          Positioned(
            top: 0,
            child: _qrNavItem(1),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, List<List<dynamic>> icon, String label) {
    bool isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              // Active indicator using a lighter blue or white with opacity
              color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: HugeIcon(
              icon: icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _qrNavItem(int index) {
    bool isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // The QR button remains white unless active, then brand blue
              color: isActive ? AppColors.primaryBlue : Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: isActive 
                ? Border.all(color: Colors.white, width: 2) 
                : null,
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedQrCode,
              color: isActive ? Colors.white : AppColors.primaryBlue,
              size: 35,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "AutoFill QR",
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}