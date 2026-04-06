import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

enum _SortField { date, formType }
enum _SortOrder { asc, desc }

class HistoryScreen extends StatefulWidget {
  final String userId;
  final bool embedded;

  const HistoryScreen({super.key, required this.userId, this.embedded = false});

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

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
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

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final username = await _supabaseService.getUsername(widget.userId);
      final submissions = await _supabaseService.fetchClientSubmissionHistoryByUser(widget.userId);
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

  void _applySort() {
    final sorted = List<Map<String, dynamic>>.from(_submissions);
    sorted.sort((a, b) {
      int cmp;
      if (_sortField == _SortField.date) {
        final aDate = DateTime.tryParse(a['scanned_at'] ?? a['created_at'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['scanned_at'] ?? b['created_at'] ?? '') ?? DateTime(0);
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
        _sortOrder = _sortOrder == _SortOrder.desc ? _SortOrder.asc : _SortOrder.desc;
      } else {
        _sortField = field;
        _sortOrder = field == _SortField.date ? _SortOrder.desc : _SortOrder.asc;
      }
    });
    _applySort();
  }

  String _getWorkerName(Map<String, dynamic> item) {
    return item['last_edited_by']?.toString().trim() ?? '';
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  // ── Detail popup ──────────────────────────────────────────
  void _showDetailDialog(Map<String, dynamic> item) {
    final formType = item['form_type'] as String? ?? 'Unknown Form';
    final intakeRef = item['intake_reference'] as String?;
    final scannedAt = item['scanned_at'] as String?;
    final processedAt = item['last_edited_at'] as String?;
    final createdAt = item['created_at'] as String?;
    final workerName = _getWorkerName(item);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.qr_code_scanner, color: AppColors.primaryBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formType,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Submitted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Detail rows
              if (intakeRef != null && intakeRef.isNotEmpty)
                _detailRow(
                  icon: Icons.tag,
                  label: 'Reference No.',
                  value: intakeRef,
                  valueStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                    fontFamily: 'monospace',
                  ),
                ),

              _detailRow(
                icon: Icons.qr_code_scanner,
                label: 'Scanned at',
                value: _formatDate(scannedAt),
              ),

              if (workerName.isNotEmpty)
                _detailRow(
                  icon: Icons.person_outline,
                  label: 'Assisted by',
                  value: workerName,
                  valueStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                )
              else
                _detailRow(
                  icon: Icons.person_outline,
                  label: 'Assisted by',
                  value: 'Not yet processed',
                  valueStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                ),

              _detailRow(
                icon: Icons.edit_outlined,
                label: 'Processed at',
                value: processedAt != null && processedAt.isNotEmpty
                    ? _formatDate(processedAt)
                    : 'Pending',
                valueStyle: processedAt != null && processedAt.isNotEmpty
                    ? null
                    : TextStyle(fontSize: 13, color: Colors.orange.shade600, fontStyle: FontStyle.italic),
              ),

              _detailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Record created',
                value: _formatDate(createdAt),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: valueStyle ?? const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: widget.embedded ? null : _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
          ? _buildEmptyState()
          : Column(children: [_buildSortBar(), Expanded(child: _buildList())]),
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
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.history, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Submission History', style: TextStyle(color: Colors.white60, fontSize: 10)),
              Text(_username.isEmpty ? 'User' : _username, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white, size: 22), onPressed: _loadHistory),
        IconButton(icon: const Icon(Icons.logout, color: Colors.white, size: 22), onPressed: _handleLogout),
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
          Text('${_filtered.length} submission${_filtered.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          const Spacer(),
          const Text('Sort by:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
            decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(Icons.history_toggle_off_outlined, size: 40, color: AppColors.primaryBlue.withOpacity(0.4)),
          ),
          const SizedBox(height: 16),
          const Text('No submissions yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(
            'Your form transmissions will appear here\nonce a staff member saves your record.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton.icon(onPressed: _loadHistory, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
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
    final scannedAt = item['scanned_at'] as String?;
    final processedAt = item['last_edited_at'] as String?;
    final workerName = _getWorkerName(item);

    return GestureDetector(
      onTap: () => _showDetailDialog(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEF5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.qr_code_scanner, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(formType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Submitted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                        ),
                      ],
                    ),

                    if (intakeRef != null && intakeRef.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.tag, size: 12, color: AppColors.primaryBlue),
                          const SizedBox(width: 4),
                          Text(intakeRef, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryBlue, fontFamily: 'monospace')),
                        ],
                      ),
                    ],

                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.qr_code_scanner, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 5),
                        Expanded(child: Text('Scanned: ${_formatDate(scannedAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                      ],
                    ),

                    if (workerName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 12, color: AppColors.primaryBlue.withOpacity(0.7)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Assisted by: $workerName',
                              style: TextStyle(fontSize: 12, color: AppColors.primaryBlue.withOpacity(0.85), fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (processedAt != null && processedAt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 5),
                          Expanded(child: Text('Processed: ${_formatDate(processedAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                        ],
                      ),
                    ],

                    // Tap hint
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Tap for details', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        const SizedBox(width: 2),
                        Icon(Icons.info_outline, size: 11, color: Colors.grey.shade400),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sort chip widget ──────────────────────────────────────────
class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDesc;
  final VoidCallback onTap;

  const _SortChip({required this.label, required this.icon, required this.isActive, required this.isDesc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryBlue.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? AppColors.primaryBlue.withOpacity(0.4) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? AppColors.primaryBlue : Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppColors.primaryBlue : Colors.grey.shade600)),
            if (isActive) ...[
              const SizedBox(width: 3),
              Icon(isDesc ? Icons.arrow_downward : Icons.arrow_upward, size: 11, color: AppColors.primaryBlue),
            ],
          ],
        ),
      ),
    );
  }
}