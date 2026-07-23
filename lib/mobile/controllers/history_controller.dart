import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';
import 'package:sappiire/services/forms/user_notification_service.dart';
import 'package:sappiire/mobile/utils/date_utils.dart';

enum SortField { date, formType }
enum SortOrder { asc, desc }

/// Loads the signed-in user's submission history and resolves display names.
///
/// Also subscribes to real-time updates on `form_submission` and
/// `client_submissions` so the citizen sees live status changes.
class HistoryController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final SubmissionService _submissionService = SubmissionService();
  final UserNotificationService _notifService = UserNotificationService();
  final _supabase = Supabase.instance.client;
  final String userId;

  List<Map<String, dynamic>> submissions = [];
  List<Map<String, dynamic>> filtered = [];
  bool isLoading = true;
  String username = '';
  SortField sortField = SortField.date;
  SortOrder sortOrder = SortOrder.desc;

  // Live status tracking: session_id -> latest status from form_submission
  final Map<String, String> _activeStatusMap = {};

  // Realtime subscriptions
  StreamSubscription? _sessionSub;
  StreamSubscription? _notifSub;
  Timer? _pollTimer;

  // Track last known review_status values for change detection
  final Map<dynamic, String> _lastReviewStatuses = {};

  // Callback fired when a review decision (approved/denied) is detected.
  // The HistoryScreen can use this to show a SnackBar.
  void Function(String status, String formType)? onReviewDecision;

  HistoryController({required this.userId});

  /// Start listening for real-time submission status updates.
  void startListening() {
    // Subscribe to form_submission changes for this user
    _sessionSub = _submissionService
        .streamUserSubmissions(userId)
        .listen((rows) {
      bool changed = false;
      for (final row in rows) {
        final sessionId = row['id']?.toString() ?? '';
        final status = row['status']?.toString() ?? '';
        if (sessionId.isNotEmpty && status.isNotEmpty) {
          if (_activeStatusMap[sessionId] != status) {
            _activeStatusMap[sessionId] = status;
            changed = true;
          }
        }
      }
      if (changed) {
        // Merge active statuses into existing submissions
        _applyActiveStatuses();
        notifyListeners();
      }
    });

    // Subscribe to submission notifications — reloads history on approve/deny
    _notifSub = _notifService
        .streamNotifications(userId)
        .listen((rows) {
      final decision = rows.cast<Map<String, dynamic>?>().firstWhere(
        (n) {
          final status = n?['status']?.toString() ?? '';
          return status == 'approved' || status == 'denied';
        },
        orElse: () => null,
      );
      if (decision != null) {
        _handleReviewDecision(
          status: decision['status']?.toString() ?? '',
          formType: decision['form_type']?.toString() ?? '',
          message: decision['message']?.toString() ?? '',
        );
      }
    });

    // Fallback: poll for review_status changes every 20 seconds.
    // This ensures the screen updates even if Realtime is not fully enabled.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _pollReviewStatus());
  }

  /// Check for review_status changes using a lightweight query.
  Future<void> _pollReviewStatus() async {
    if (submissions.isEmpty) return;

    try {
      // Get current session IDs
      final sessionIds = submissions
          .map((s) => s['session_id']?.toString())
          .whereType<String>()
          .toList();

      if (sessionIds.isEmpty) return;

      // Lightweight: only fetch review_status for monitored sessions
      final fresh = await _supabase
          .from('client_submissions')
          .select('id, review_status, form_type')
          .inFilter('session_id', sessionIds);

      if (fresh == null) return;

      for (final row in fresh as List) {
        final id = row['id'];
        final newStatus = row['review_status']?.toString() ?? 'pending';
        final prevStatus = _lastReviewStatuses[id] ?? 'pending';

        if (prevStatus != newStatus && (newStatus == 'approved' || newStatus == 'denied')) {
          _lastReviewStatuses[id] = newStatus;
          final formType = row['form_type']?.toString() ?? '';
          _handleReviewDecision(
            status: newStatus,
            formType: formType,
            message: null,
          );
          return; // one decision per poll cycle
        }
        _lastReviewStatuses[id] = newStatus;
      }
    } catch (_) {
      // Silently ignore poll errors
    }
  }

  /// Called when a review decision is detected — reloads history and
  /// fires the callback so the screen can show a toast.
  void _handleReviewDecision({
    required String status,
    required String formType,
    String? message,
  }) {
    // Reload history immediately
    loadHistory();

    // Fire the callback for a SnackBar toast
    onReviewDecision?.call(status, formType);
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _notifSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Merge active session statuses into the submission list.
  void _applyActiveStatuses() {
    for (var i = 0; i < submissions.length; i++) {
      final sessionId = submissions[i]['session_id']?.toString() ?? '';
      if (sessionId.isNotEmpty && _activeStatusMap.containsKey(sessionId)) {
        submissions[i]['_session_status'] = _activeStatusMap[sessionId];
      }
    }
  }

  /// Get the active session status for a submission item, if available.
  String? getActiveStatus(Map<String, dynamic> item) {
    // Priority: form_submission live status > review_status from client_submissions
    final sessionStatus = item['_session_status']?.toString();
    if (sessionStatus != null && sessionStatus != 'completed') {
      return sessionStatus;
    }
    return null; // falls back to review_status
  }

  Future<void> loadHistory() async {
    isLoading = true;
    notifyListeners();

    try {
      username = await _supabaseService.getUsername(userId) ?? '';
      final fresh = await _supabaseService.fetchClientSubmissionHistoryByUser(userId);

      // Track review_status for change detection next poll cycle
      for (final item in fresh) {
        final id = item['id'];
        final status = item['review_status']?.toString() ?? 'pending';
        _lastReviewStatuses[id] = status;

        if (item['review_status'] == null || item['review_status'].toString().isEmpty) {
          item['review_status'] = 'pending';
        }
      }

      submissions = await _resolveAssistedBy(fresh);
      _applyActiveStatuses();
      _applySort();
    } catch (e) {
      debugPrint('[HistoryController/loadHistory] Error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  bool _looksLikeUuid(String raw) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(raw);
  }

  Future<List<Map<String, dynamic>>> _resolveAssistedBy(
    List<Map<String, dynamic>> submissions,
  ) async {
    // Resolve staff IDs to readable names before the list is rendered.
    final resolved = submissions
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final workerIds = <String>{};
    for (final item in resolved) {
      final editedBy = item['last_edited_by']?.toString().trim() ?? '';
      final createdBy = item['created_by']?.toString().trim() ?? '';
      final raw = editedBy.isNotEmpty ? editedBy : createdBy;
      if (raw.isNotEmpty && _looksLikeUuid(raw)) {
        workerIds.add(raw);
      }
    }

    final fullNameById = <String, String>{};
    final usernameById = <String, String>{};

    if (workerIds.isNotEmpty) {
      try {
        final profiles = await _supabase
            .from('staff_profiles')
            .select('cswd_id, first_name, last_name')
            .inFilter('cswd_id', workerIds.toList());

        for (final row in List<Map<String, dynamic>>.from(profiles)) {
          final cswdId = row['cswd_id']?.toString().trim() ?? '';
          final first = row['first_name']?.toString().trim() ?? '';
          final last = row['last_name']?.toString().trim() ?? '';
          final fullName = [first, last].where((part) => part.isNotEmpty).join(' ');
          if (cswdId.isNotEmpty && fullName.isNotEmpty) {
            fullNameById[cswdId] = fullName;
          }
        }
      } catch (e) {
        debugPrint('[HistoryController/_resolveAssistedBy] Profile lookup failed: $e');
      }

      try {
        final accounts = await _supabase
            .from('staff_accounts')
            .select('cswd_id, username')
            .inFilter('cswd_id', workerIds.toList());

        for (final row in List<Map<String, dynamic>>.from(accounts)) {
          final cswdId = row['cswd_id']?.toString().trim() ?? '';
          final uname = row['username']?.toString().trim() ?? '';
          if (cswdId.isNotEmpty && uname.isNotEmpty) {
            usernameById[cswdId] = uname;
          }
        }
      } catch (e) {
        debugPrint('[HistoryController/_resolveAssistedBy] Account lookup failed: $e');
      }
    }

    for (final item in resolved) {
      final editedBy = item['last_edited_by']?.toString().trim() ?? '';
      final createdBy = item['created_by']?.toString().trim() ?? '';
      final raw = editedBy.isNotEmpty ? editedBy : createdBy;
      if (raw.isEmpty) {
        continue;
      }

      if (!_looksLikeUuid(raw)) {
        item['last_edited_by'] = raw;
        continue;
      }

      final fullName = fullNameById[raw];
      final uname = usernameById[raw];
      if (fullName != null && fullName.isNotEmpty) {
        item['last_edited_by'] = fullName;
      } else if (uname != null && uname.isNotEmpty) {
        item['last_edited_by'] = uname;
      } else {
        item['last_edited_by'] = 'CSWD Staff';
      }
    }

    return resolved;
  }

  void _applySort() {
    // Keep the filtered list aligned with the selected sort settings.
    final sorted = List<Map<String, dynamic>>.from(submissions);
    sorted.sort((a, b) {
      int cmp;
      if (sortField == SortField.date) {
        final aDate = DateTime.tryParse(a['scanned_at'] ?? a['created_at'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['scanned_at'] ?? b['created_at'] ?? '') ?? DateTime(0);
        cmp = aDate.compareTo(bDate);
      } else {
        final aType = (a['form_type'] ?? '').toString().toLowerCase();
        final bType = (b['form_type'] ?? '').toString().toLowerCase();
        cmp = aType.compareTo(bType);
      }
      return sortOrder == SortOrder.desc ? -cmp : cmp;
    });
    filtered = sorted;
  }

  void toggleSortField(SortField field) {
    if (sortField == field) {
      sortOrder = sortOrder == SortOrder.desc ? SortOrder.asc : SortOrder.desc;
    } else {
      sortField = field;
      sortOrder = field == SortField.date ? SortOrder.desc : SortOrder.asc;
    }
    _applySort();
    notifyListeners();
  }

  String formatDate(String? raw) {
    return AppDateUtils.formatDisplay(raw);
  }

  bool looksLikeUuid(String s) {
    return AppDateUtils.looksLikeUuid(s);
  }

  String getWorkerName(Map<String, dynamic> item) {
    return item['last_edited_by']?.toString().trim() ?? '';
  }

  Future<void> signOutCurrentUser() async {
    await _supabaseService.signOutCurrentUser();
  }

}
