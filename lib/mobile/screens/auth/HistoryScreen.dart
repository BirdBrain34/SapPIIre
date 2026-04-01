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
  const HistoryScreen({super.key, required this.userId, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
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

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final username = await _supabaseService.getUsername(widget.userId);
      debugPrint('🔍 Loading history for userId: ${widget.userId}');

      // Step 1: get all session IDs from form_submission where user_id matches
      final sessionRows = await _supabase
          .from('form_submission')
          .select('id')
          .eq('user_id', widget.userId);

      final sessionIds = (sessionRows as List)
          .map((r) => r['id']?.toString())
          .whereType<String>()
          .toList();

      debugPrint('📋 Sessions found for user: ${sessionIds.length} → $sessionIds');

      List<Map<String, dynamic>> submissions = [];

      if (sessionIds.isNotEmpty) {
        // Step 2a: match via session_id column (populated by newer web saves)
        final byColumn = await _supabase
            .from('client_submissions')
            .select('id, form_type, intake_reference, created_at, session_id, data')
            .inFilter('session_id', sessionIds)
            .order('created_at', ascending: false);

        debugPrint('✅ Matched by session_id column: ${(byColumn as List).length}');
        submissions = List<Map<String, dynamic>>.from(byColumn);

        // Step 2b: match via data->>'__session_id' JSONB field
        // This mirrors exactly how applicants_screen.dart (web) resolves names —
        // it traces client_submissions.data.__session_id → form_submission.user_id
        // We do the reverse: user_id → session IDs → match JSONB field
        try {
          final byJsonb = await _supabase
              .from('client_submissions')
              .select('id, form_type, intake_reference, created_at, session_id, data')
              .inFilter('data->>__session_id', sessionIds)
              .order('created_at', ascending: false);

          debugPrint('✅ Matched by JSONB __session_id: ${(byJsonb as List).length}');

          // Merge without duplicates (dedup by id)
          final seen = <dynamic>{for (final s in submissions) s['id']};
          for (final s in byJsonb) {
            if (!seen.contains(s['id'])) {
              submissions.add(Map<String, dynamic>.from(s));
              seen.add(s['id']);
            }
          }
        } catch (e) {
          // JSONB filter may not be supported on all Supabase plans — safe to skip
          debugPrint('⚠️ JSONB filter failed (non-critical): $e');
        }

        debugPrint('📦 Total unique submissions after merge: ${submissions.length}');
      } else {
        debugPrint('❌ No sessions found for user — check that form_submission.user_id is being set when client scans QR');
      }

      setState(() {
        _username = username ?? '';
        _submissions = submissions;
        _filtered = List.from(submissions);
        _isLoading = false;
      });

      _applySort();
    } catch (e) {
      debugPrint('❌ _loadHistory error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applySort() {
    final sorted = List<Map<String, dynamic>>.from(_submissions);
    sorted.sort((a, b) {
      int cmp;
      if (_sortField == _SortField.date) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
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
        _sortOrder =
            _sortOrder == _SortOrder.desc ? _SortOrder.asc : _SortOrder.desc;
      } else {
        _sortField = field;
        _sortOrder =
            field == _SortField.date ? _SortOrder.desc : _SortOrder.asc;
      }
    });
    _applySort();
  }

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
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '—';
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
    final createdAt = item['created_at'] as String?;
    final intakeRef = item['intake_reference'] as String?;

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
                            horizontal: 8, vertical: 3),
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
                  if (intakeRef != null && intakeRef.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.tag,
                            size: 12, color: AppColors.primaryBlue),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 5),
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort chip ──────────────────────────────────────────────────
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
            Icon(icon,
                size: 12,
                color: isActive
                    ? AppColors.primaryBlue
                    : Colors.grey.shade500),
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