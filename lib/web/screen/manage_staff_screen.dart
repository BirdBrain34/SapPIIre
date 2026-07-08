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
  final String cswdId;
  final String displayName;

  const ManageStaffScreen({
    super.key,
    required this.role,
    required this.cswdId,
    this.displayName = '',
  });

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  final _controller = ManageStaffController();

  // Database search — applied only when Search is pressed / Enter hit.
  final _dbSearchController = TextEditingController();
  String _dbQuery = '';

  // 'active' | 'deactivated' | 'all'
  String _statusFilter = 'active';

  // Page-size selector: 10 / 15 / 25 / 50 / 100.
  int _pageSize = 25;
  int _currentPage = 0;

  static const _pageSizeOptions = [10, 15, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    _controller.loadAccounts();
  }

  @override
  void dispose() {
    _dbSearchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _approveAccount(String cswdId, String requestedRole) async {
    await _controller.approveAccount(
      cswdId: cswdId,
      requestedRole: requestedRole,
      actorId: widget.cswdId,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _rejectAccount(String cswdId) async {
    await _controller.rejectAccount(
      cswdId: cswdId,
      actorId: widget.cswdId,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _deactivateAccount(String cswdId, String username) async {
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
      cswdId: cswdId,
      username: username,
      actorId: widget.cswdId,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  Future<void> _reactivateAccount(String cswdId, String username) async {
    await _controller.reactivateAccount(
      cswdId: cswdId,
      username: username,
      actorId: widget.cswdId,
      actorName: widget.displayName,
      actorRole: widget.role,
    );
  }

  // --- Search / filter actions ---------------------------------------------

  void _applyDbSearch() {
    setState(() {
      _dbQuery = _dbSearchController.text.trim();
      _currentPage = 0;
    });
  }

  void _clearDbSearch() {
    setState(() {
      _dbSearchController.clear();
      _dbQuery = '';
      _currentPage = 0;
    });
  }

  bool _matchesQuery(Map<String, dynamic> acc, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final username = (acc['username'] ?? '').toString().toLowerCase();
    final email = (acc['email'] ?? '').toString().toLowerCase();
    return username.contains(q) || email.contains(q);
  }

  bool _matchesStatus(Map<String, dynamic> acc) {
    switch (_statusFilter) {
      case 'active':
        return acc['is_active'] == true;
      case 'deactivated':
        return acc['is_active'] != true;
      default:
        return true;
    }
  }

  // --- Styling helpers ------------------------------------------------------

  /// Distinct accent color per role so staff are visually differentiated.
  Color _roleColor(String role) {
    switch (role) {
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
        color: color.withValues(alpha:  0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha:  0.3)),
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

  /// Active / Deactivated pill for the Status column.
  Widget _statusBadge(bool isActive) {
    final color = isActive ? AppColors.successGreen : AppColors.warningAmber;
    final label = isActive ? 'Active' : 'Deactivated';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha:  0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha:  0.3)),
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
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
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
        backgroundColor: color.withValues(alpha:  0.08),
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

  /// Bordered shell shared by the status + page-size dropdowns.
  Widget _dropdownShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'Staff',
      pageTitle: 'Manage Staff Accounts',
      pageSubtitle: 'Review and manage staff access',
      role: widget.role,
      cswdId: widget.cswdId,
      displayName: widget.displayName,
      onLogout: () => WebSession.logout(context),
      onNavigate: (screenPath) => WebNavigator.go(
        context,
        screenPath,
        cswdId: widget.cswdId,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // --- Derived pipeline: status -> db search -> page slice -> page filter
          final statusFiltered = _controller.activeAccounts
              .where(_matchesStatus)
              .toList();
          final searched = statusFiltered
              .where((acc) => _matchesQuery(acc, _dbQuery))
              .toList();

          final totalFiltered = searched.length;
          final pageCount =
              totalFiltered == 0 ? 1 : (totalFiltered / _pageSize).ceil();
          final currentPage = _currentPage.clamp(0, pageCount - 1);

          final visible = searched
              .skip(currentPage * _pageSize)
              .take(_pageSize)
              .toList();

          return Padding(
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
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
                                acc['cswdId'],
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
                              onPressed: () => _rejectAccount(acc['cswdId']),
                              child: const Text("Reject"),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // All Staff header
                  const Row(
                    children: [
                      Icon(Icons.groups, color: AppColors.textDark, size: 20),
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

                  // Filter bar
                  _buildFilterBar(),
                  const SizedBox(height: 16),

                  // Staff table
                  _buildStaffTable(visible),
                  const SizedBox(height: 16),

                  // Pagination
                  _buildPagination(
                    currentPage: currentPage,
                    pageCount: pageCount,
                    totalFiltered: totalFiltered,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Filter bar -----------------------------------------------------------

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          // Row 1 — database search + Search/Clear + status + page size
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _dbSearchController,
                  onSubmitted: (_) => _applyDbSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search all staff by name or email...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.pageBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _applyDbSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.highlight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _clearDbSearch,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: const BorderSide(color: AppColors.cardBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Clear'),
              ),
              const SizedBox(width: 12),
              _dropdownShell(
                child: DropdownButton<String>(
                  value: _statusFilter,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'deactivated',
                      child: Text('Deactivated'),
                    ),
                    DropdownMenuItem(value: 'all', child: Text('All Staff')),
                  ],
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                  onChanged: (v) {
                    setState(() {
                      _statusFilter = v ?? 'active';
                      _currentPage = 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              _dropdownShell(
                child: DropdownButton<int>(
                  value: _pageSize,
                  isDense: true,
                  items: _pageSizeOptions
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('Show $n'),
                        ),
                      )
                      .toList(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                  onChanged: (v) {
                    setState(() {
                      _pageSize = v ?? 25;
                      _currentPage = 0;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Table ----------------------------------------------------------------

  Widget _buildStaffTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          Divider(height: 1, color: AppColors.cardBorder),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No staff match your filters.',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.cardBorder),
              itemBuilder: (_, i) => _buildStaffRow(rows[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: const [
          Expanded(flex: 3, child: _TableHeader('USER')),
          Expanded(flex: 3, child: _TableHeader('EMAIL')),
          SizedBox(width: 130, child: _TableHeader('ROLE')),
          SizedBox(width: 130, child: _TableHeader('STATUS')),
          SizedBox(width: 150, child: _TableHeader('ACTION')),
        ],
      ),
    );
  }

  Widget _buildStaffRow(Map<String, dynamic> acc) {
    final isActive = acc['is_active'] == true;
    final username = (acc['username'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // USER
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withValues(alpha:  0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: AppColors.highlight,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // EMAIL
          Expanded(
            flex: 3,
            child: Text(
              acc['email'] ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          // ROLE
          SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _roleBadge(acc['role'] ?? 'admin'),
            ),
          ),
          // STATUS
          SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(isActive),
            ),
          ),
          // ACTION
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerRight,
              child: isActive
                  ? _actionButton(
                      icon: Icons.block,
                      label: 'Deactivate',
                      color: AppColors.warningAmber,
                      onPressed: () => _deactivateAccount(
                        acc['cswdId'],
                        username,
                      ),
                    )
                  : _actionButton(
                      icon: Icons.check_circle_outline,
                      label: 'Reactivate',
                      color: AppColors.successGreen,
                      onPressed: () => _reactivateAccount(
                        acc['cswdId'],
                        username,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Pagination -----------------------------------------------------------

  Widget _buildPagination({
    required int currentPage,
    required int pageCount,
    required int totalFiltered,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: currentPage > 0
              ? () => setState(() => _currentPage = currentPage - 1)
              : null,
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          'Page ${currentPage + 1} of $pageCount  ($totalFiltered staff)',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: currentPage < pageCount - 1
              ? () => setState(() => _currentPage = currentPage + 1)
              : null,
          icon: const Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}
