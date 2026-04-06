import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

enum _SortField { date, formType }

enum _SortOrder { asc, desc }

class HistoryScreen extends StatefulWidget {
  final String userId;
  final bool embedded;

  const HistoryScreen({
    super.key,
    required this.userId,
    this.embedded = false,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _submissions = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String _username = '';

  _SortField _sortField = _SortField.date;
  _SortOrder _sortOrder = _SortOrder.desc;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // ── Logout ────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerRed,
            ),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _supabaseService.signOutCurrentUser();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ── Load ──────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final usernameFuture = _supabaseService.getUsername(widget.userId);
      final submissionsFuture =
          _supabaseService.fetchClientSubmissionHistoryByUser(widget.userId);

      final username = await usernameFuture;
      final submissions = await submissionsFuture;

      setState(() {
        _username = username ?? '';
        _submissions = submissions;
        _filtered = List.from(submissions);
        _isLoading = false;
      });

      _applySort();
    } catch (e) {
      debugPrint('_loadHistory error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── Sort ──────────────────────────────────────────────────
  void _applySort() {
    final sorted = List<Map<String, dynamic>>.from(_submissions);
    sorted.sort((a, b) {
      int cmp;
      if (_sortField == _SortField.date) {
        // Sort by scanned_at (when the citizen scanned), fall back to created_at
        final aDate =
            DateTime.tryParse(a['scanned_at'] ?? a['created_at'] ?? '') ??
            DateTime(0);
        final bDate =
            DateTime.tryParse(b['scanned_at'] ?? b['created_at'] ?? '') ??
            DateTime(0);
        cmp = aDate.compareTo(bDate);
      } else {
        final aType = (a['form_type'] ?? '').toString().toLowerCase();
        final bType = (b['form_type'] ?? '').toString().toLowerCase();
        cmp = aType.compareTo(bType);
      }
      return _sortOrder == _SortOrder.desc ? -cmp : cmp;
    });
    setState(() => _filtered = sorted);
  }

  void _toggleSortField(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortOrder = _sortOrder == _SortOrder.desc
            ? _SortOrder.asc
            : _SortOrder.desc;
      } else {
        _sortField = field;
        _sortOrder =
            field == _SortField.date ? _SortOrder.desc : _SortOrder.asc;
      }
    });
    _applySort();
  }

  // ── Worker name helper ────────────────────────────────────
  // last_edited_by stores name (already resolved from UUID in supabase_service)
  String _getWorkerName(Map<String, dynamic> item) {
    return item['last_edited_by']?.toString().trim() ?? '';
  }

  // ── Date formatter ────────────────────────────────────────
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: widget.embedded ? null : _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                _buildSortBar(),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Submission History',
                style: TextStyle(color: Colors.white60, fontSize: 10),
              ),
              Text(
                _username.isEmpty ? 'User' : _username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
          onPressed: _loadHistory,
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 22),
          onPressed: _handleLogout,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSortBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '${_filtered.length} submission${_filtered.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const Text(
            'Sort by:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: 'Date',
            icon: Icons.calendar_today_outlined,
            isActive: _sortField == _SortField.date,
            isDesc: _sortOrder == _SortOrder.desc,
            onTap: () => _toggleSortField(_SortField.date),
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: 'Form',
            icon: Icons.article_outlined,
            isActive: _sortField == _SortField.formType,
            isDesc: _sortOrder == _SortOrder.desc,
            onTap: () => _toggleSortField(_SortField.formType),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_toggle_off_outlined,
              size: 40,
              color: AppColors.primaryBlue.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No submissions yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your form transmissions will appear here\nonce a staff member saves your record.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _filtered.length,
        itemBuilder: (context, index) => _buildCard(_filtered[index]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final formType = item['form_type'] as String? ?? 'Unknown Form';
    final intakeRef = item['intake_reference'] as String?;

    // scanned_at = when citizen QR scanned (injected by supabase_service)
    final scannedAt = item['scanned_at'] as String?;
    // last_edited_at = when staff processed/saved
    final processedAt = item['last_edited_at'] as String?;
    // Worker name — already resolved from UUID to display name
    final workerName = _getWorkerName(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.qr_code_scanner,
                color: AppColors.primaryBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form type + status badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formType,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Submitted',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Intake reference
                  if (intakeRef != null && intakeRef.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.tag,
                          size: 12,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          intakeRef,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Scanned at (when citizen scanned QR)
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Scanned: ${_formatDate(scannedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Assisted by (worker name)
                  if (workerName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 12,
                          color: AppColors.primaryBlue.withOpacity(0.7),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Assisted by: $workerName',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryBlue.withOpacity(0.85),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Processed at (when staff saved)
                  if (processedAt != null && processedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Processed: ${_formatDate(processedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort chip widget ───────────────────────────────────────────
class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDesc;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isDesc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryBlue.withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.primaryBlue.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color:
                  isActive ? AppColors.primaryBlue : Colors.grey.shade500,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? AppColors.primaryBlue
                    : Colors.grey.shade600,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 3),
              Icon(
                isDesc ? Icons.arrow_downward : Icons.arrow_upward,
                size: 11,
                color: AppColors.primaryBlue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}