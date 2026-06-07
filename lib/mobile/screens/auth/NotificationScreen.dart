import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';

class NotificationScreen extends StatefulWidget {
  final String userId;

  const NotificationScreen({super.key, required this.userId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _notifications = [];
  Set<String> _readIds = {};
  Set<String> _expandedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final result = await _supabaseService.fetchAppNotifications(widget.userId);
    if (mounted) {
      setState(() {
        _notifications = result['notifications'] as List<Map<String, dynamic>>;
        _readIds = Set<String>.from(result['readIds'] as List<String>);
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final unreadIds = _notifications
        .map((n) => n['id'] as String)
        .where((id) => !_readIds.contains(id))
        .toList();
    if (unreadIds.isEmpty) return;
    await _supabaseService.markNotificationsRead(
      userId: widget.userId,
      notificationIds: unreadIds,
    );
    if (mounted) setState(() => _readIds.addAll(unreadIds));
  }

  Future<void> _markOneRead(String id) async {
    if (_readIds.contains(id)) return;
    await _supabaseService.markNotificationsRead(
      userId: widget.userId,
      notificationIds: [id],
    );
    if (mounted) setState(() => _readIds.add(id));
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
    _markOneRead(id);
  }

  int get _unreadCount =>
      _notifications.where((n) => !_readIds.contains(n['id'] as String)).length;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extract bullet-point change lines from the details JSONB.
  /// details shape: { "changes": [ { "action": "added"|"updated"|"removed", "field": "Field Label" } ] }
  List<String> _getBullets(Map<String, dynamic> notification) {
    final raw = notification['details'];
    if (raw == null || raw is! Map) return [];
    final details = Map<String, dynamic>.from(raw as Map);
    final changesRaw = details['changes'];
    if (changesRaw == null || changesRaw is! List) return [];

    final bullets = <String>[];
    for (final item in changesRaw as List) {
      if (item is! Map) continue;
      final action = item['action']?.toString() ?? '';
      final field  = item['field']?.toString()  ?? '';
      if (field.isEmpty) continue;
      switch (action) {
        case 'added':   bullets.add('• Added "$field"');   break;
        case 'removed': bullets.add('• Removed "$field"'); break;
        case 'updated': bullets.add('• Updated "$field"'); break;
        default:        bullets.add('• "$field"');
      }
    }
    return bullets;
  }

  bool _hasExpandableContent(Map<String, dynamic> notification) =>
      _getBullets(notification).isNotEmpty;

  IconData _iconFor(String changeType) {
    switch (changeType) {
      case 'field_added':     return Icons.add_circle_outline_rounded;
      case 'field_updated':
      case 'updated':         return Icons.edit_note_rounded;
      case 'field_deleted':   return Icons.remove_circle_outline_rounded;
      case 'pushed_to_mobile':
      case 'added':           return Icons.new_releases_outlined;
      case 'archived':
      case 'deleted':         return Icons.archive_outlined;
      default:                return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String changeType) {
    switch (changeType) {
      case 'field_added':     return const Color(0xFF2E7D32);
      case 'field_updated':
      case 'updated':         return const Color(0xFF0277BD);
      case 'field_deleted':   return const Color(0xFFC62828);
      case 'pushed_to_mobile':
      case 'added':           return const Color(0xFF0D47A1);
      case 'archived':
      case 'deleted':         return const Color(0xFFBF360C);
      default:                return const Color(0xFF1565C0);
    }
  }

  String _changeTypeLabel(String changeType) {
    switch (changeType) {
      case 'field_added':      return 'Field Added';
      case 'field_updated':    return 'Field Updated';
      case 'field_deleted':    return 'Field Removed';
      case 'pushed_to_mobile': return 'New Form';
      case 'added':            return 'Form Added';
      case 'archived':         return 'Form Archived';
      case 'deleted':          return 'Form Deleted';
      case 'published':        return 'Published';
      case 'updated':          return 'Form Updated';
      default:                 return changeType;
    }
  }

  String _timeAgo(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  color: AppColors.primaryBlue,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _notifications.length,
                    itemBuilder: (context, i) =>
                        _buildNotificationTile(_notifications[i]),
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context, _readIds),
        tooltip: 'Back',
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Notifications',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (_unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.highlight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_unreadCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_unreadCount > 0)
          TextButton.icon(
            onPressed: _markAllRead,
            icon: const Icon(Icons.done_all_rounded,
                color: Colors.white70, size: 18),
            label: const Text('Mark all read',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notification) {
    final id           = notification['id'] as String;
    final isRead       = _readIds.contains(id);
    final isExpanded   = _expandedIds.contains(id);
    final changeType   = notification['change_type'] as String? ?? 'updated';
    final summary      = notification['change_summary'] as String? ?? '';
    final templateName = notification['template_name'] as String? ?? '';
    final createdAt    = notification['created_at'] as String? ?? '';
    final canExpand    = _hasExpandableContent(notification);
    final bullets      = canExpand ? _getBullets(notification) : <String>[];

    final accentColor  = _colorFor(changeType);
    final icon         = _iconFor(changeType);
    final label        = _changeTypeLabel(changeType);

    return GestureDetector(
      onTap: () => canExpand ? _toggleExpanded(id) : _markOneRead(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.white
              : AppColors.primaryBlue.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded
                ? accentColor.withOpacity(0.4)
                : isRead
                    ? const Color(0xFFEEEEF5)
                    : AppColors.primaryBlue.withOpacity(0.18),
            width: isExpanded ? 1.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isRead ? 0.03 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main content row ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon badge
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                    letterSpacing: 0.3),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _timeAgo(createdAt),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (templateName.isNotEmpty)
                          Text(
                            templateName,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          summary,
                          style: TextStyle(
                              fontSize: 13,
                              color: isRead
                                  ? Colors.grey.shade600
                                  : const Color(0xFF1A1A2E),
                              fontWeight: isRead
                                  ? FontWeight.w400
                                  : FontWeight.w500,
                              height: 1.4),
                        ),
                        // "See changes" hint when collapsed and expandable
                        if (canExpand && !isExpanded) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: accentColor.withOpacity(0.6)),
                              const SizedBox(width: 2),
                              Text(
                                'Tap to see what changed',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: accentColor.withOpacity(0.7),
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Chevron
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: accentColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Expanded bullet list ──────────────────────────────────────
            if (canExpand && isExpanded)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: 1,
                      color: accentColor.withOpacity(0.15),
                      indent: 14,
                      endIndent: 14,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.04),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: bullets.map((line) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.4),
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: 40,
                color: AppColors.primaryBlue.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 6),
          Text(
            'Form updates and changes\nwill appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}