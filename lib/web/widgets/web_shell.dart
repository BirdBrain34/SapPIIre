// lib/web/widgets/web_shell.dart
// Wrap every post-login screen with this to get consistent layout + topbar

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/screen/change_password_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/widgets/side_menu.dart';

String _roleLabel(String role) {
  switch (role) {
    case 'superadmin':
      return 'Super Administrator';
    case 'admin':
      return 'Administrator';
    default:
      return role;
  }
}

String _safeValue(dynamic value, {String fallback = 'Not set'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

Map<String, dynamic> _asStringDynamicMap(dynamic source) {
  if (source is Map<String, dynamic>) return source;
  if (source is Map) {
    return source.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return <String, dynamic>{};
}

class WebShell extends StatelessWidget {
  final String activePath;
  final String pageTitle;
  final String pageSubtitle;
  final String role;
  final String cswdId;
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
    required this.cswdId,
    this.displayName = '',
    required this.child,
    required this.onLogout,
    this.headerActions,
    this.onNavigate,
  });

  Future<void> _showAccountPanel(BuildContext context) async {
    final rootContext = context;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          child: _AccountPanel(
            cswdId: cswdId,
            role: role,
            displayName: displayName,
            onClose: () => Navigator.of(dialogContext).pop(),
            onChangePassword: (resolvedName) {
              Navigator.of(dialogContext).pop();
              Navigator.push(
                rootContext,
                ContentFadeRoute(
                  page: ChangePasswordScreen(
                    cswdId: cswdId,
                    role: role,
                    displayName: resolvedName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAccountButton(BuildContext context, {required bool isNarrow}) {
    return _AccountButton(
      displayName: displayName,
      role: role,
      isNarrow: isNarrow,
      onTap: () => _showAccountPanel(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 960;
    final scaffoldKey = GlobalKey<ScaffoldState>();

    void onMenuTap() {
      final scaffoldState = scaffoldKey.currentState;
      if (scaffoldState == null) return;

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

/// My Account dialog: a clean profile card — tinted header with avatar + role,
/// then full-width detail tiles (so long values like email never clip).
class _AccountPanel extends StatefulWidget {
  final String cswdId;
  final String role;
  final String displayName;
  final VoidCallback onClose;
  final void Function(String resolvedName) onChangePassword;

  const _AccountPanel({
    required this.cswdId,
    required this.role,
    required this.displayName,
    required this.onClose,
    required this.onChangePassword,
  });

  @override
  State<_AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<_AccountPanel> {
  bool _loading = true;

  String _email = 'Not set';
  String _username = 'Not set';
  String _department = 'Not set';
  String _position = 'Not set';
  String _first = '';
  String _last = '';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// First + last only, so the panel header matches the top-bar button and
  /// never balloons with a middle name.
  String get _displayName {
    final parts = [_first, _last].where((s) => s.trim().isNotEmpty).toList();
    final name = parts.join(' ').trim();
    if (name.isNotEmpty) return name;
    return widget.displayName.trim().isEmpty ? 'My Account' : widget.displayName.trim();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;

      final accountResult = await client.functions.invoke('manage-staff-account', body: {
        'action': 'fetch_account',
        'cswdId': widget.cswdId,
      });
      final account = _asStringDynamicMap(
        (accountResult.data as Map<String, dynamic>?)?['account'],
      );

      final profileResult = await client.functions.invoke('manage-staff-account', body: {
        'action': 'fetch_profile',
        'cswdId': widget.cswdId,
      });
      final profile = _asStringDynamicMap(
        (profileResult.data as Map<String, dynamic>?)?['profile'],
      );

      _first = (profile['first_name'] ?? '').toString().trim();
      _last = (profile['last_name'] ?? '').toString().trim();
      _phone = (profile['phone_number'] ?? '').toString().trim();
      _email = _safeValue(account['email']);
      _username = _safeValue(account['username']);
      _department = _safeValue(profile['department']);
      _position = _safeValue(profile['position']);
    } catch (_) {
      // Leave fallbacks in place.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _detailTile(Icons.email_outlined, 'Email', _email),
                        const SizedBox(height: 6),
                        _detailTile(Icons.phone_outlined, 'Phone',
                            _phone.isEmpty ? 'Not set' : _phone),
                        const SizedBox(height: 6),
                        _detailTile(Icons.business_outlined, 'Department', _department),
                        const SizedBox(height: 6),
                        _detailTile(Icons.work_outline, 'Position', _position),
                        const SizedBox(height: 6),
                        _detailTile(Icons.alternate_email, 'Username', _username),
                        const SizedBox(height: 22),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.highlight.withValues(alpha:  0.16),
            AppColors.highlight.withValues(alpha:  0.04),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.highlight.withValues(alpha:  0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.person, color: AppColors.highlight, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.highlight.withValues(alpha:  0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _roleLabel(widget.role),
              style: const TextStyle(
                color: AppColors.highlight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.pageBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.textMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                softWrap: true,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: widget.onClose,
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Close'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => widget.onChangePassword(_displayName),
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Change Password'),
        ),
      ],
    );
  }
}

/// Top-bar account entry point. Hover-aware pill with a gradient avatar; fixed
/// name width so it never resizes as the name length changes.
class _AccountButton extends StatefulWidget {
  final String displayName;
  final String role;
  final bool isNarrow;
  final VoidCallback onTap;

  const _AccountButton({
    required this.displayName,
    required this.role,
    required this.isNarrow,
    required this.onTap,
  });

  @override
  State<_AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<_AccountButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.displayName.isEmpty ? 'My Account' : widget.displayName;

    return Tooltip(
      message: 'My Account',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.highlight.withValues(alpha:  0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              // No resting border — only a faint one on hover for feedback.
              border: Border.all(
                color: _hovered
                    ? AppColors.highlight.withValues(alpha:  0.30)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.highlight, AppColors.primaryBlue],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.highlight.withValues(alpha:  0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 19),
                ),
                if (!widget.isNarrow) ...[
                  const SizedBox(width: 11),
                  // Fixed width keeps the button from resizing as name length
                  // changes (e.g. with/without a middle name).
                  SizedBox(
                    width: 150,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _roleLabel(widget.role),
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
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: _hovered ? AppColors.highlight : AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
