import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'logout_confirmation_dialog.dart';

class SideMenu extends StatelessWidget {
  final String activePath;
  final VoidCallback? onLogout;
  final Function(String)? onNavigate;

  const SideMenu({
    super.key,
    required this.activePath,
    this.onLogout,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B4E), Color(0xFF0A1640)],
        ),
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('lib/Logo/sappiire_logo.png', height: 44),
                const SizedBox(height: 10),
                const Text(
                  'SapPIIre Portal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const Text(
                  'CSWD Santa Rosa',
                  style: TextStyle(
                    color: AppColors.mutedBlue,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: const Color(0xFF1E2E60)),
          const SizedBox(height: 12),

          // ── Nav section label ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Text(
              'MAIN MENU',
              style: TextStyle(
                color: AppColors.mutedBlue.withOpacity(0.6),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          _navItem(
            context,
            Icons.dashboard_outlined,
            'Dashboard',
            'Dashboard',
            activePath,
          ),
          _navItem(
            context,
            Icons.description_outlined,
            'Manage Forms',
            'Forms',
            activePath,
          ),
          _navItem(
            context,
            Icons.people_outline,
            'Applicants',
            'Applicants',
            activePath,
          ),

          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFF1E2E60)),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Text(
              'ADMIN',
              style: TextStyle(
                color: AppColors.mutedBlue.withOpacity(0.6),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          _navItem(
            context,
            Icons.manage_accounts_outlined,
            'Manage Staff',
            'Staff',
            activePath,
          ),
          _navItem(
            context,
            Icons.person_add_outlined,
            'Create Staff',
            'CreateStaff',
            activePath,
          ),

          const Spacer(),
          Container(height: 1, color: const Color(0xFF1E2E60)),

          // ── Logout ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (onLogout != null) {
                    LogoutConfirmationDialog.show(
                      context: context,
                      onConfirm: onLogout!,
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.logout, color: Colors.white38, size: 18),
                      const SizedBox(width: 12),
                      const Text(
                        'Log Out',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label,
    String path,
    String currentPath,
  ) {
    final isActive = currentPath == path;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isActive ? AppColors.highlight.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withOpacity(0.06),
          onTap: () {
            if (!isActive) {
              _handleNavigation(context, path);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                // Active indicator bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.highlight : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Icon(
                  icon,
                  color: isActive ? AppColors.lightBlue : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white60,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleNavigation(BuildContext context, String screenPath) {
    // Import the screen classes at the top for this to work
    // For now, we'll use a generic approach that works without circular imports
    try {
      // The screens will be navigated to based on the path
      // This is called from SideMenu which is in WebShell
      // We need to tell the parent to navigate
      if (onNavigate != null) {
        onNavigate!(screenPath);
      }
    } catch (e) {
      debugPrint("Navigation error: $e");
    }
  }
}
