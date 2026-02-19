// lib/web/screen/manage_staff_screen.dart
import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/widget/side_menu.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FE),
      body: Row(
        children: [
          SideMenu(
            activePath: "Staff",
            role: 'admin',
            cswd_id: 'admin',
            onLogout: () => Navigator.pop(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(35.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Manage Staff Accounts",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 30),

                        // ── Pending Approvals ──
                        if (_pendingAccounts.isNotEmpty) ...[
                          const Text(
                            "⏳ Pending Approval",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._pendingAccounts.map((acc) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(acc['username'] ?? ''),
                              subtitle: Text(
                                '${acc['email']}  •  Requested: ${acc['requested_role']}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
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
                                      foregroundColor: Colors.red,
                                    ),
                                    onPressed: () => _rejectAccount(acc['cswd_id']),
                                    child: const Text("Reject"),
                                  ),
                                ],
                              ),
                            ),
                          )),
                          const SizedBox(height: 20),
                        ],

                        // ── Active Accounts ──
                        const Text(
                          "👥 All Staff",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _activeAccounts.length,
                            itemBuilder: (_, i) {
                              final acc = _activeAccounts[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.person),
                                  title: Text(acc['username'] ?? ''),
                                  subtitle: Text(acc['email'] ?? ''),
                                  trailing: DropdownButton<String>(
                                    value: acc['role'] ?? 'viewer',
                                    items: ['viewer', 'form_editor', 'admin']
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
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
