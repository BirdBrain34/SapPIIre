// lib/mobile/widgets/bottom_navbar.dart
// UPDATED: 4-item nav → Manage Info | AutoFill QR (elevated) | Camera | Fill History

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sappiire/constants/app_colors.dart';

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
      height: 80,
      decoration: const BoxDecoration(
        color: AppColors.primaryBlue,
        border: Border(
          top: BorderSide(color: Colors.white24, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 0 - Manage Info
          Expanded(
            child: _navItem(0, HugeIcons.strokeRoundedUser, "Manage Info"),
          ),
          // 1 - AutoFill QR (elevated pop-out style inline)
          Expanded(
            child: _qrInlineItem(1),
          ),
          // 2 - Camera (ID Scanner)
          Expanded(
            child: _navItem(2, HugeIcons.strokeRoundedCamera02, "Camera"),
          ),
          // 3 - Fill History
          Expanded(
            child: _navItem(3, HugeIcons.strokeRoundedClock01, "History"),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, List<List<dynamic>> icon, String label) {
    final isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: HugeIcon(
              icon: icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 9,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _qrInlineItem(int index) {
    final isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Transform.translate(
        // Lifts the QR button above the nav bar for a pop-out feel
        offset: const Offset(0, -10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? AppColors.highlight : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: isActive
                    ? Border.all(color: Colors.white, width: 2)
                    : Border.all(
                        color: AppColors.borderNavy.withOpacity(0.2), width: 1),
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedQrCode,
                color: isActive ? Colors.white : AppColors.primaryBlue,
                size: 28,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "AutoFill QR",
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}