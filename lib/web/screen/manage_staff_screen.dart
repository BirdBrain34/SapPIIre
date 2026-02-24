// lib/web/screen/manage_staff_screen.dart
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/web_shell.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageStaffScreen extends StatefulWidget {
  final String role;
  final String cswd_id;

  const ManageStaffScreen({
    super.key,
    required this.role,
    required this.cswd_id,
  });

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pendingAccounts = [];
  List<Map<String, dynamic>> _activeAccounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      // Fetch pending accounts
      final pending = await _supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, requested_role, created_at')
          .eq('account_status', 'pending')
          .order('created_at');

      // Fetch active accounts
      final active = await _supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, role, account_status, is_active')
          .neq('account_status', 'pending')
          .order('username');

      setState(() {
        _pendingAccounts = List<Map<String, dynamic>>.from(pending);
        _activeAccounts = List<Map<String, dynamic>>.from(active);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approveAccount(String cswd_id, String requestedRole) async {
    await _supabase.from('staff_accounts').update({
      'role': requestedRole,
      'account_status': 'active',
      'is_active': true,
    }).eq('cswd_id', cswd_id);
    _loadAccounts();
  }

  Future<void> _rejectAccount(String cswd_id) async {
    await _supabase.from('staff_accounts').update({
      'account_status': 'deactivated',
      'is_active': false,
    }).eq('cswd_id', cswd_id);
    _loadAccounts();
  }

  Future<void> _updateRole(String cswd_id, String newRole) async {
    await _supabase.from('staff_accounts')
        .update({'role': newRole})
        .eq('cswd_id', cswd_id);
    _loadAccounts();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Staff',
      pageTitle: 'Manage Staff Accounts',
      pageSubtitle: 'Review and manage staff access',
      onLogout: () => Navigator.pop(context),
      onNavigate: (screenPath) => _navigateToScreen(context, screenPath),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Pending Approvals ──
                    if (_pendingAccounts.isNotEmpty) ...[
                      const Text(
                        "⏳ Pending Approval",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._pendingAccounts.map((acc) => Container(
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
                                    '${acc['email']}  •  Requested: ${acc['requested_role']}',
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
                                side: const BorderSide(color: AppColors.dangerRed),
                              ),
                              onPressed: () => _rejectAccount(acc['cswd_id']),
                              child: const Text("Reject"),
                            ),
                          ],
                        ),
                      )),
                      const SizedBox(height: 32),
                    ],

                    // ── Active Accounts ──
                    const Text(
                      "👥 All Staff",
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
                        itemCount: _activeAccounts.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppColors.cardBorder,
                        ),
                        itemBuilder: (_, i) {
                          final acc = _activeAccounts[i];
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.highlight.withOpacity(0.15),
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        acc['username'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textDark,
                                        ),
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
                                DropdownButton<String>(
                                  value: acc['role'] ?? 'viewer',
                                  items: ['viewer', 'form_editor', 'admin', 'superadmin']
                                      .map((r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(r),
                                          ))
                                      .toList(),
                                  onChanged: (newRole) {
                                    if (newRole != null) {
                                      _updateRole(acc['cswd_id'], newRole);
                                    }
                                  },
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
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenPath) {
    Widget nextScreen;
    switch (screenPath) {
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: widget.cswd_id,
          role: widget.role,
          onLogout: () => Navigator.pop(context),
        );
        break;
      case 'Forms':
        nextScreen = ManageFormsScreen(
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
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }
}
