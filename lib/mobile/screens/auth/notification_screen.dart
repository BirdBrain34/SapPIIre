import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/services/forms/user_notification_service.dart';
import 'package:sappiire/mobile/widgets/status_badge_widget.dart';

class NotificationScreen extends StatefulWidget {
  final String userId;

  const NotificationScreen({super.key, required this.userId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  final _supabaseService = SupabaseService();
  final _userNotifService = UserNotificationService();

  late final TabController _tabCtrl;

  // Template notification state (existing)
  List<Map<String, dynamic>> _notifications = [];
  Set<String> _readIds = {};
  final Set<String> _expandedIds = {};
  bool _isLoading = true;

  // Submission notification state
  List<Map<String, dynamic>> _submissionNotifs = [];
  bool _isLoadingSubs = true;

  StreamSubscription? _subNotifSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadNotifications();
    _loadSubmissionNotifications();
    _listenToSubmissionNotifs();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _subNotifSub?.cancel();
    super.dispose();
  }

  void _listenToSubmissionNotifs() {
    _subNotifSub = _userNotifService
        .streamNotifications(widget.userId)
        .listen((rows) {
      if (mounted) {
        setState(() {
          _submissionNotifs = rows;
          _isLoadingSubs = false;
        });
      }
    });
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

  Future<void> _loadSubmissionNotifications() async {
    final rows = await _userNotifService.fetchNotifications(
      userId: widget.userId,
      limit: 100,
    );
    if (mounted) {
      setState(() {
        _submissionNotifs = rows;
        _isLoadingSubs = false;
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

  Future<void> _markAllSubsRead() async {
    await _userNotifService.markAllRead(widget.userId);
    if (mounted) {
      setState(() {
        for (final n in _submissionNotifs) {
          n['is_read'] = true;
        }
      });
    }
  }

  Future<void> _markOneRead(String id) async {
    if (_readIds.contains(id)) return;
    await _supabaseService.markNotificationsRead(
      userId: widget.userId,
      notificationIds: [id],
    );
    if (mounted) setState(() => _readIds.add(id));
  }

  Future<void> _markOneSubRead(String id) async {
    await _userNotifService.markRead(id);
    if (mounted) {
      setState(() {
        for (final n in _submissionNotifs) {
          if (n['id'] == id) n['is_read'] = true;
        }
      });
    }
  }

  Future<void> _toggleExpanded(String id) async {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
    await _markOneRead(id);
  }

  int get _unreadCount =>
      _notifications.where((n) => !_readIds.contains(n['id'] as String)).length;

  int get _unreadSubCount =>
      _submissionNotifs.where((n) => n['is_read'] != true).length;

  // ── Template Notification Helpers (existing) ─────────────────────────

  List<String> _getBullets(Map<String, dynamic> notification) {
    final raw = notification['details'];
    if (raw == null || raw is! Map) return [];
    final details = Map<String, dynamic>.from(raw);
    final changesRaw = details['changes'];
    if (changesRaw == null || changesRaw is! List) return [];

    final bullets = <String>[];
    for (final item in changesRaw) {
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

  // ── Submission Notification Helpers (new) ────────────────────────────

  IconData _subIconFor(String status) {
    switch (status) {
      case 'scanned':    return Icons.qr_code_scanner;
      case 'completed':  return Icons.save_outlined;
      case 'approved':   return Icons.check_circle_outline;
      case 'denied':     return Icons.cancel_outlined;
      default:           return Icons.notifications_outlined;
    }
  }

  Color _subColorFor(String status) {
    switch (status) {
      case 'scanned':    return const Color(0xFF3B82F6);   // blue
      case 'completed':  return const Color(0xFF6B7280);   // gray
      case 'approved':   return const Color(0xFF10B981);   // green
      case 'denied':     return const Color(0xFFEF4444);   // red
      default:           return const Color(0xFF1565C0);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primaryBlue,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Template Updates'),
                      if (_unreadCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(_unreadCount),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('My Submissions'),
                      if (_unreadSubCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(_unreadSubCount),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTemplateTab(),
                _buildSubmissionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.highlight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
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

  // ── Template Updates Tab (existing) ──────────────────────────────────

  Widget _buildTemplateTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notifications.isEmpty) {
      return _buildEmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        subtitle: 'Form updates and changes\nwill appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: AppColors.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _notifications.length,
        itemBuilder: (context, i) =>
            _buildNotificationTile(_notifications[i]),
      ),
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
      onTap: () async {
        if (canExpand) {
          await _toggleExpanded(id);
        } else {
          await _markOneRead(id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.white
              : AppColors.primaryBlue.withValues(alpha:  0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded
                ? accentColor.withValues(alpha:  0.4)
                : isRead
                    ? const Color(0xFFEEEEF5)
                    : AppColors.primaryBlue.withValues(alpha:  0.18),
            width: isExpanded ? 1.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:  isRead ? 0.03 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha:  0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
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
                                color: accentColor.withValues(alpha:  0.10),
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
                        if (canExpand && !isExpanded) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: accentColor.withValues(alpha:  0.6)),
                              const SizedBox(width: 2),
                              Text(
                                'Tap to see what changed',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: accentColor.withValues(alpha:  0.7),
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: accentColor.withValues(alpha:  0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canExpand && isExpanded)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: 1,
                      color: accentColor.withValues(alpha:  0.15),
                      indent: 14,
                      endIndent: 14,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha:  0.04),
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

  // ── My Submissions Tab (new) ─────────────────────────────────────────

  Widget _buildSubmissionsTab() {
    if (_isLoadingSubs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_submissionNotifs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_toggle_off_outlined,
        title: 'No submission updates',
        subtitle: 'Status updates for your forms\nwill appear here when staff processes them.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSubmissionNotifications,
      color: AppColors.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _submissionNotifs.length + 1, // +1 for "Mark all read" header
        itemBuilder: (context, i) {
          if (i == 0) {
            return _buildSubsListHeader();
          }
          return _buildSubmissionNotifTile(_submissionNotifs[i - 1]);
        },
      ),
    );
  }

  Widget _buildSubsListHeader() {
    if (_unreadSubCount == 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$_unreadSubCount unread',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _markAllSubsRead,
            child: Text(
              'Mark all read',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionNotifTile(Map<String, dynamic> notif) {
    final id = notif['id']?.toString() ?? '';
    final status = notif['status']?.toString() ?? '';
    final message = notif['message']?.toString() ?? '';
    final formType = notif['form_type']?.toString() ?? '';
    final intakeRef = notif['intake_reference']?.toString() ?? '';
    final createdAt = notif['created_at']?.toString() ?? '';
    final isRead = notif['is_read'] == true;

    final accentColor = _subColorFor(status);
    final icon = _subIconFor(status);

    return GestureDetector(
      onTap: () => _markOneSubRead(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : accentColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead
                ? const Color(0xFFEEEEF5)
                : accentColor.withValues(alpha: 0.25),
            width: isRead ? 1.2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isRead ? 0.03 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusBadgeWidget(
                          status: status,
                          compact: true,
                          fontSize: 9,
                        ),
                        const Spacer(),
                        Text(
                          _timeAgo(createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (formType.isNotEmpty)
                      Text(
                        formType,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: isRead
                            ? Colors.grey.shade600
                            : const Color(0xFF1A1A2E),
                        fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    if (intakeRef.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Ref: $intakeRef',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryBlue,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared ────────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 40,
              color: AppColors.primaryBlue.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}