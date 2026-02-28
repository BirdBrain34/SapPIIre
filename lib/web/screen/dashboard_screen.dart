import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';

class DashboardScreen extends StatefulWidget {
  final String cswd_id;
  final String role;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.cswd_id,
    required this.role,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Dashboard',
      pageTitle: 'Dashboard',
      pageSubtitle: 'Overview of CSWD form activity',
      onLogout: widget.onLogout,
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  _buildDashboardCard(
                    title: "Total Forms",
                    value: "0",
                    icon: Icons.description,
                    color: AppColors.highlight,
                  ),
                  const SizedBox(width: 20),
                  _buildDashboardCard(
                    title: "Active Sessions",
                    value: "0",
                    icon: Icons.qr_code_2,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(width: 20),
                  _buildDashboardCard(
                    title: "Completed",
                    value: "0",
                    icon: Icons.check_circle,
                    color: AppColors.highlight,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Quick Actions",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      "Dashboard content will be added here.",
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Forms':
        nextScreen = ManageFormsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Staff':
        nextScreen = ManageStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'CreateStaff':
        nextScreen = CreateStaffScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
        );
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}