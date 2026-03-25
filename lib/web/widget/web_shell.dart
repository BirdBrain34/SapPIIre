// lib/web/widget/web_shell.dart
// Wrap every post-login screen with this to get consistent layout + topbar

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/screen/change_password_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/widget/side_menu.dart';

class WebShell extends StatelessWidget {
  final String activePath;
  final String pageTitle;
  final String pageSubtitle;
  final String role;
  final String cswd_id;
  final String displayName;
  final Widget child;
  final VoidCallback onLogout;
  final List<Widget>? headerActions;
  final Function(String)? onNavigate;

  const WebShell({
    super.key,
    required this.activePath,
    required this.pageTitle,
    required this.pageSubtitle,
    required this.role,
    required this.cswd_id,
    this.displayName = '',
    required this.child,
    required this.onLogout,
    this.headerActions,
    this.onNavigate,
  });

  String _roleLabel(String role) {
    switch (role) {
      case 'superadmin':
        return 'Super Administrator';
      case 'admin':
        return 'Administrator';
      case 'form_editor':
        return 'Form Editor';
      case 'viewer':
        return 'Staff';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Row(
        children: [
          // Sidebar — static, never transitions
          SideMenu(
            activePath: activePath,
            role: role,
            onLogout: onLogout,
            onNavigate: onNavigate,
          ),

          // Content area — this is what fades on navigation
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top bar ──────────────────────────────────────
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: const BoxDecoration(
                    color: AppColors.cardBg,
                    border: Border(
                      bottom: BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Page title
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pageTitle,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            pageSubtitle,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Header action buttons (optional)
                      if (headerActions != null) ...headerActions!,
                      const SizedBox(width: 16),
                      Tooltip(
                        message: 'Change Password',
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            ContentFadeRoute(
                              page: ChangePasswordScreen(
                                cswd_id: cswd_id,
                                role: role,
                                displayName: displayName,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.highlight.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.highlight.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: AppColors.highlight.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.highlight,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName.isEmpty
                                          ? 'My Account'
                                          : displayName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      _roleLabel(role),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.expand_more,
                                  size: 16,
                                  color: AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Page content ─────────────────────────────────
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
