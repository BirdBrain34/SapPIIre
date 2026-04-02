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
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 960;
    final scaffoldKey = GlobalKey<ScaffoldState>();

    void onMenuTap() {
      final scaffoldState = scaffoldKey.currentState;
      if (scaffoldState == null) {
        return;
      }

      if (scaffoldState.isDrawerOpen) {
        Navigator.of(scaffoldState.context).pop();
      } else {
        scaffoldState.openDrawer();
      }
    }

    void onNavigateWithDrawerClose(String path) {
      final scaffoldState = scaffoldKey.currentState;
      if (isNarrow && scaffoldState?.isDrawerOpen == true) {
        Navigator.of(scaffoldState!.context).pop();
      }
      onNavigate?.call(path);
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.pageBg,
      drawer: isNarrow
          ? Drawer(
              child: SideMenu(
                activePath: activePath,
                role: role,
                onLogout: onLogout,
                onNavigate: onNavigateWithDrawerClose,
              ),
            )
          : null,
      body: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(context, isNarrow: true, onMenuTap: onMenuTap),
                Expanded(child: child),
              ],
            )
          : Row(
              children: [
                SideMenu(
                  activePath: activePath,
                  role: role,
                  onLogout: onLogout,
                  onNavigate: onNavigateWithDrawerClose,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(context, isNarrow: false, onMenuTap: null),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool isNarrow,
    required VoidCallback? onMenuTap,
  }) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 14 : 32),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                children: [
                  if (isNarrow)
                    IconButton(
                      onPressed: onMenuTap,
                      icon: const Icon(Icons.menu),
                    ),
                  SizedBox(
                    width: isNarrow ? 200 : 320,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pageTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          pageSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!isNarrow && headerActions != null) ...headerActions!,
                  if (!isNarrow) const SizedBox(width: 16),
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
                          color: AppColors.highlight.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.highlight.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.highlight.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                color: AppColors.highlight,
                                size: 18,
                              ),
                            ),
                            if (!isNarrow) ...[
                              const SizedBox(width: 10),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName.isEmpty
                                          ? 'My Account'
                                          : displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      _roleLabel(role),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.expand_more,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
