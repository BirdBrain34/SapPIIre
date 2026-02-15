import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'logout_confirmation_dialog.dart';

class SideMenu extends StatelessWidget {
  final String activePath;
  final VoidCallback? onLogout;
  const SideMenu({super.key, required this.activePath, this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: AppColors.primaryBlue,
      child: Column(
        children: [
          const SizedBox(height: 50),
          Image.asset('lib/Logo/sappiire_logo.png', height: 120),
          const SizedBox(height: 40),
          _menuItem(Icons.dashboard, "Dashboard", activePath == "Dashboard"),
          _menuItem(Icons.description, "Manage Forms", activePath == "Forms"),
          _menuItem(Icons.people, "Applicants", activePath == "Applicants"),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.white),
            title: const Text(
              "Log Out",
              style: TextStyle(color: AppColors.white),
            ),
            onTap: () {
              if (onLogout != null) {
                LogoutConfirmationDialog.show(
                  context: context,
                  onConfirm: onLogout!,
                );
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? AppColors.accentBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.white),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () {},
      ),
    );
  }
}
