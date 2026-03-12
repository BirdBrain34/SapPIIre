import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/supabase_service.dart';

class HistoryScreen extends StatefulWidget {
  final String userId;
  final bool embedded;  // ← add this
  const HistoryScreen({super.key, required this.userId, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  final _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _submissions = [];
  bool _isLoading = true;
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final username = await _supabaseService.getUsername(widget.userId);
      final response = await _supabase
          .from('form_submission')
          .select('id, form_type, scanned_at')
          .not('scanned_at', 'is', null)
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);

      setState(() {
        _username = username ?? '';
        _submissions = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('HistoryScreen._loadHistory error: $e');
    }
    setState(() => _isLoading = false);
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
            child: const Text('Log Out',
                style: TextStyle(color: Colors.white)),
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

  // ── Helpers ───────────────────────────────────────────────

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scanned':    return const Color(0xFF2196F3);
      case 'completed':  return const Color(0xFF4CAF50);
      case 'closed':     return const Color(0xFF9E9E9E);
      case 'expired':    return const Color(0xFFFF5722);
      default:           return const Color(0xFFFF9800);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'scanned':    return Icons.qr_code_scanner;
      case 'completed':  return Icons.check_circle_outline;
      case 'closed':     return Icons.archive_outlined;
      case 'expired':    return Icons.timer_off_outlined;
      default:           return Icons.pending_outlined;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'scanned':    return 'Transmitted';
      case 'completed':  return 'Completed';
      case 'closed':     return 'Closed';
      case 'expired':    return 'Expired';
      default:           return 'Pending';
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: widget.embedded ? null : _buildAppBar(),  // ← hide when embedded
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
              ? _buildEmptyState()
              : _buildList(),
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
        tooltip: 'Back',
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
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w400),
              ),
              Text(
                _username.isEmpty ? 'User' : _username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
          onPressed: _loadHistory,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
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
            'Your form transmissions will appear here.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _submissions.length,
        itemBuilder: (context, index) {
          final item = _submissions[index];
          return _buildCard(item, index);
        },
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item, int index) {
    final formType = item['form_type'] as String? ?? 'Unknown Form';
    final scannedAt = item['scanned_at'] as String?;

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
            // Left icon
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

            // Content
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Transmitted',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.qr_code_scanner,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 5),
                      Text(
                        scannedAt != null
                            ? 'Transmitted: ${_formatDate(scannedAt)}'
                            : 'Transmission date unavailable',
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