// lib/web/screen/manage_staff_screen.dart
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/widgets/confirm_dialog.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/controllers/manage_staff_controller.dart';

class ManageStaffScreen extends StatefulWidget {
  final String role;
  final String cswd_id;
  final String displayName;

  const ManageStaffScreen({
    super.key,
    required this.role,
    required this.cswd_id,
    this.displayName = '',
  });

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  final _controller = ManageStaffController();

  @override
  void initState() {
    super.initState();
    _controller.loadAccounts();
  }

  Future<void> _approveAccount(String cswd_id, String requestedRole) async {
    await _controller.approveAccount(
      cswdId: cswd_id,
      requestedRole: requestedRole,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _rejectAccount(String cswd_id) async {
    await _controller.rejectAccount(
      cswdId: cswd_id,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _deactivateAccount(String cswd_id, String username) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Deactivate Account',
      message:
          'Deactivating "@$username" will prevent them from logging in. '
          'Their data and audit history are preserved. Continue?',
      confirmLabel: 'Deactivate',
      confirmColor: Colors.orange,
    );

    if (!confirmed) return;

    await _controller.deactivateAccount(
      cswdId: cswd_id,
      username: username,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _reactivateAccount(String cswd_id, String username) async {
    await _controller.reactivateAccount(
      cswdId: cswd_id,
      username: username,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  /// Distinct accent color per role so staff are visually differentiated.
  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin':
        return AppColors.highlight;
      case 'admin':
        return AppColors.successGreen;
      default:
        return AppColors.textMuted;
    }
  }

  /// Rounded, color-coded role pill with a leading status dot.
  Widget _roleBadge(String role) {
    final color = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            role,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Tonal action button used for Deactivate / Reactivate.
  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Staff',
      pageTitle: 'Manage Staff Accounts',
      pageSubtitle: 'Review and manage staff access',
      role: widget.role,
      cswd_id: widget.cswd_id,
      displayName: widget.displayName,
      onLogout: () => WebSession.logout(context),
      onNavigate: (screenPath) => WebNavigator.go(
        context,
        screenPath,
        cswdId: widget.cswd_id,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: _controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pending Approvals
                    if (_controller.pendingAccounts.isNotEmpty) ...[
                      const Row(
                        children: [
                          Icon(
                            Icons.hourglass_empty,
                            color: AppColors.textDark,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Pending Approval",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ..._controller.pendingAccounts.map(
                        (acc) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            border: Border.all(color: AppColors.cardBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      acc['username'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${acc['email']} Requested: ${acc['requested_role']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.successGreen,
                                ),
                                onPressed: () => _approveAccount(
                                  acc['cswd_id'],
                                  acc['requested_role'] ?? 'admin',
                                ),
                                child: const Text(
                                  "Approve",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.dangerRed,
                                  side: const BorderSide(
                                    color: AppColors.dangerRed,
                                  ),
                                ),
                                onPressed: () => _rejectAccount(acc['cswd_id']),
                                child: const Text("Reject"),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Active Accounts
                    const Row(
                      children: [
                        Icon(
                          Icons.groups,
                          color: AppColors.textDark,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "All Staff",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        border: Border.all(color: AppColors.cardBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _controller.activeAccounts.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: AppColors.cardBorder),
                        itemBuilder: (_, i) {
                          final acc = _controller.activeAccounts[i];
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.highlight.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.highlight,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            acc['username'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          if (acc['role'] == 'superadmin')
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.highlight,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'SYSTEM',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          if (acc['is_active'] != true)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.warningAmber
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppColors.warningAmber
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: const Text(
                                                'DEACTIVATED',
                                                style: TextStyle(
                                                  color: AppColors.warningAmber,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Text(
                                        acc['email'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Role pill — fixed-width slot so badges align
                                // in a column across every row.
                                SizedBox(
                                  width: 130,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _roleBadge(acc['role'] ?? 'admin'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Action slot — reserved even for superadmin so
                                // the pills above stay aligned.
                                SizedBox(
                                  width: 150,
                                  child: acc['role'] == 'superadmin'
                                      ? const SizedBox.shrink()
                                      : Align(
                                          alignment: Alignment.centerRight,
                                          child: acc['is_active'] == true
                                              ? _actionButton(
                                                  icon: Icons.block,
                                                  label: 'Deactivate',
                                                  color: AppColors.warningAmber,
                                                  onPressed: () =>
                                                      _deactivateAccount(
                                                        acc['cswd_id'],
                                                        acc['username'] ?? '',
                                                      ),
                                                )
                                              : _actionButton(
                                                  icon:
                                                      Icons.check_circle_outline,
                                                  label: 'Reactivate',
                                                  color: AppColors.successGreen,
                                                  onPressed: () =>
                                                      _reactivateAccount(
                                                        acc['cswd_id'],
                                                        acc['username'] ?? '',
                                                      ),
                                                ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
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
