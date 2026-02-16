import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'logout_confirmation_dialog.dart';

class SideMenu extends StatelessWidget {
  final String activePath;
  final String role;
  final VoidCallback? onLogout;

  const SideMenu({
    super.key,
    required this.activePath,
    required this.role,
    this.onLogout,
  });

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
          _menuItem(context, Icons.dashboard, "Dashboard", activePath == "Dashboard"),
          _menuItem(context, Icons.description, "Manage Forms", activePath == "Forms"),
          _menuItem(context, Icons.people, "Applicants", activePath == "Applicants"),
          if (role == 'admin')
            _menuItem(context, Icons.manage_accounts, "Manage Staff", activePath == "Staff"),
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

  Widget _menuItem(BuildContext context, IconData icon, String title, bool isActive) {
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
        onTap: () {
          if (title == "Manage Staff") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManageStaffScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}
