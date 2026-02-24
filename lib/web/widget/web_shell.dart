// lib/web/widget/web_shell.dart
// Wrap every post-login screen with this to get consistent layout + topbar

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/side_menu.dart';

class WebShell extends StatelessWidget {
  final String activePath;
  final String pageTitle;
  final String pageSubtitle;
  final Widget child;
  final VoidCallback onLogout;
  final List<Widget>? headerActions;
  final Function(String)? onNavigate;

  const WebShell({
    super.key,
    required this.activePath,
    required this.pageTitle,
    required this.pageSubtitle,
    required this.child,
    required this.onLogout,
    this.headerActions,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Row(
        children: [
          // Sidebar — static, never transitions
          SideMenu(
            activePath: activePath,
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
                      // Staff avatar placeholder
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.highlight.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.highlight,
                          size: 20,
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
