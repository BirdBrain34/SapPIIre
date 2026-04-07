// lib/web/widget/web_shell.dart
// Wrap every post-login screen with this to get consistent layout + topbar

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  String _safeValue(dynamic value, {String fallback = 'Not set'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic source) {
    if (source is Map<String, dynamic>) {
      return source;
    }

    if (source is Map) {
      return source.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return <String, dynamic>{};
  }

  String _composeProfileName(Map<String, dynamic> profile) {
    final first = _safeValue(profile['first_name'], fallback: '');
    final middle = _safeValue(profile['middle_name'], fallback: '');
    final last = _safeValue(profile['last_name'], fallback: '');
    final suffix = _safeValue(profile['name_suffix'], fallback: '');

    final parts = <String>[
      if (first.isNotEmpty) first,
      if (middle.isNotEmpty) middle,
      if (last.isNotEmpty) last,
    ];

    var fullName = parts.join(' ').trim();
    if (suffix.isNotEmpty) {
      fullName = fullName.isEmpty ? suffix : '$fullName, $suffix';
    }
    return fullName;
  }

  Map<String, String> _fallbackAccountInfo() {
    final name = displayName.trim().isEmpty ? 'My Account' : displayName.trim();

    return {
      'name': name,
      'role': _roleLabel(role),
      'email': 'Not set',
      'department': 'Not set',
      'position': 'Not set',
      'phone': 'Not set',
      'username': 'Not set',
    };
  }

  Future<Map<String, String>> _loadAccountInfo() async {
    final fallback = _fallbackAccountInfo();

    try {
      final client = Supabase.instance.client;

      final accountResponse = await client
          .from('staff_accounts')
          .select('email, username')
          .eq('cswd_id', cswd_id)
          .maybeSingle();

      final profileResponse = await client
          .from('staff_profiles')
          .select(
            'first_name, middle_name, last_name, name_suffix, department, position, phone_number',
          )
          .eq('cswd_id', cswd_id)
          .maybeSingle();

      final account = _asStringDynamicMap(accountResponse);
      final profile = _asStringDynamicMap(profileResponse);

      final resolvedName = _composeProfileName(profile);

      return {
        'name': resolvedName.isEmpty ? fallback['name']! : resolvedName,
        'role': fallback['role']!,
        'email': _safeValue(account['email']),
        'department': _safeValue(profile['department']),
        'position': _safeValue(profile['position']),
        'phone': _safeValue(profile['phone_number']),
        'username': _safeValue(account['username']),
      };
    } catch (_) {
      return fallback;
    }
  }

  Widget _accountInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountPanel(BuildContext context) async {
    final fallback = _fallbackAccountInfo();
    final rootContext = context;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: FutureBuilder<Map<String, String>>(
              future: _loadAccountInfo(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 240,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }

                final info = snapshot.data ?? fallback;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Account',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Staff account details and security settings',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _accountInfoRow(
                      icon: Icons.person_outline,
                      label: 'Name',
                      value: info['name'] ?? fallback['name']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.verified_user_outlined,
                      label: 'Role',
                      value: info['role'] ?? fallback['role']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: info['email'] ?? fallback['email']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.business_outlined,
                      label: 'Department',
                      value: info['department'] ?? fallback['department']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.work_outline,
                      label: 'Position',
                      value: info['position'] ?? fallback['position']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone Number',
                      value: info['phone'] ?? fallback['phone']!,
                    ),
                    _accountInfoRow(
                      icon: Icons.alternate_email,
                      label: 'Username',
                      value: info['username'] ?? fallback['username']!,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.highlight,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.push(
                              rootContext,
                              ContentFadeRoute(
                                page: ChangePasswordScreen(
                                  cswd_id: cswd_id,
                                  role: role,
                                  displayName:
                                      info['name'] ?? fallback['name']!,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('Change Password'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountButton(BuildContext context, {required bool isNarrow}) {
    return Tooltip(
      message: 'My Account',
      child: GestureDetector(
        onTap: () => _showAccountPanel(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  color: AppColors.highlight.withValues(alpha: 0.15),
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
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? 'My Account' : displayName,
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
    );
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
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
                      if (!isNarrow && headerActions != null) ...[
                        const SizedBox(width: 12),
                        ...headerActions!,
                      ],
                    ],
                  ),
                  const SizedBox(width: 16),
                  _buildAccountButton(context, isNarrow: isNarrow),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
