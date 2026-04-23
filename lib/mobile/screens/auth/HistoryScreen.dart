import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/controllers/history_controller.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/mobile/widgets/history_card.dart';
import 'package:sappiire/mobile/widgets/history_detail_dialog.dart';
import 'package:sappiire/mobile/widgets/sort_chip_widget.dart';

class HistoryScreen extends StatefulWidget {
  final String userId;
  final bool embedded;

  const HistoryScreen({super.key, required this.userId, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HistoryController(userId: widget.userId);
    _controller.addListener(() => setState(() {}));
    _controller.loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    await _controller.signOutCurrentUser();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: widget.embedded ? null : _buildAppBar(),
      body: _controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _controller.submissions.isEmpty
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
              Text(_controller.username.isEmpty ? 'User' : _controller.username, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white, size: 22), onPressed: _controller.loadHistory),
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
          Text('${_controller.filtered.length} submission${_controller.filtered.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          const Spacer(),
          const Text('Sort by:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SortChip(
            label: 'Date',
            icon: Icons.calendar_today_outlined,
            isActive: _controller.sortField == SortField.date,
            isDesc: _controller.sortOrder == SortOrder.desc,
            onTap: () => _controller.toggleSortField(SortField.date),
          ),
          const SizedBox(width: 6),
          SortChip(
            label: 'Form',
            icon: Icons.article_outlined,
            isActive: _controller.sortField == SortField.formType,
            isDesc: _controller.sortOrder == SortOrder.desc,
            onTap: () => _controller.toggleSortField(SortField.formType),
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
          TextButton.icon(onPressed: () => _controller.loadHistory(), icon: const Icon(Icons.refresh), label: const Text('Refresh')),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: () => _controller.loadHistory(),
      color: AppColors.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _controller.filtered.length,
        itemBuilder: (context, index) => HistoryCard(
          item: _controller.filtered[index],
          onTap: () => HistoryDetailDialog.show(context, _controller.filtered[index]),
        ),
      ),
    );
  }
}
