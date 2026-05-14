// lib/web/screen/manage_staff_screen.dart
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widgets/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
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

  Future<void> _updateRole(String cswd_id, String newRole) async {
    await _controller.updateRole(
      cswdId: cswd_id,
      newRole: newRole,
      actorId: widget.cswd_id,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _deactivateAccount(String cswd_id, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Account'),
        content: Text(
          'Deactivating "@$username" will prevent them from logging in. '
          'Their data and audit history are preserved. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text(
              'Deactivate',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => WebNavigator.go(
        context,
        screenPath,
        cswdId: widget.cswd_id,
        role: widget.role,
        displayName: widget.displayName,
        onLogout: () => Navigator.pop(context),
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
                    // â”€â”€ Pending Approvals â”€â”€
                    if (_controller.pendingAccounts.isNotEmpty) ...[
                      const Text(
                        "â³ Pending Approval",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
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
                                      '${acc['email']}  â€¢  Requested: ${acc['requested_role']}',
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
                                  acc['requested_role'] ?? 'viewer',
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

                    // â”€â”€ Active Accounts â”€â”€
                    const Text(
                      "ðŸ‘¥ All Staff",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
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
                        separatorBuilder: (_, __) =>
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
                                                color: Colors.orange
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: const Text(
                                                'DEACTIVATED',
                                                style: TextStyle(
                                                  color: Colors.orange,
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
                                acc['role'] == 'superadmin'
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.highlight
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          'superadmin',
                                          style: TextStyle(
                                            color: AppColors.highlight,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      )
                                    : DropdownButton<String>(
                                        value: acc['role'] ?? 'viewer',
                                        items:
                                            ['viewer', 'form_editor', 'admin']
                                                .map(
                                                  (r) => DropdownMenuItem(
                                                    value: r,
                                                    child: Text(r),
                                                  ),
                                                )
                                                .toList(),
                                        onChanged: (newRole) {
                                          if (newRole != null) {
                                            _updateRole(
                                              acc['cswd_id'],
                                              newRole,
                                            );
                                          }
                                        },
                                      ),
                                if (acc['role'] != 'superadmin') ...[
                                  const SizedBox(width: 12),
                                  if (acc['is_active'] == true)
                                    TextButton.icon(
                                      onPressed: () => _deactivateAccount(
                                        acc['cswd_id'],
                                        acc['username'] ?? '',
                                      ),
                                      icon: const Icon(
                                        Icons.block,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                      label: const Text(
                                        'Deactivate',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  else
                                    TextButton.icon(
                                      onPressed: () => _reactivateAccount(
                                        acc['cswd_id'],
                                        acc['username'] ?? '',
                                      ),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 16,
                                        color: AppColors.successGreen,
                                      ),
                                      label: const Text(
                                        'Reactivate',
                                        style: TextStyle(
                                          color: AppColors.successGreen,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
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
