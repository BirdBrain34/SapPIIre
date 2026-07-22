import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for citizens to fetch and stream submission status notifications.
///
/// Notifications are inserted by DB triggers on `form_submission` and
/// `client_submissions` status changes. This service provides the client-side
/// subscription and read/unread management.
class UserNotificationService {
  final SupabaseClient _supabase;

  UserNotificationService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Stream submission notifications for a user in real-time.
  Stream<List<Map<String, dynamic>>> streamNotifications(String userId) {
    return _supabase
        .from('user_submission_notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Fetch the initial batch of notifications (newest first).
  Future<List<Map<String, dynamic>>> fetchNotifications({
    required String userId,
    int limit = 50,
  }) async {
    try {
      final rows = await _supabase
          .from('user_submission_notifications')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[UserNotificationService/fetchNotifications] Error: $e');
      return [];
    }
  }

  /// Get the count of unread notifications.
  Future<int> fetchUnreadCount(String userId) async {
    try {
      final rows = await _supabase
          .from('user_submission_notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (rows as List).length;
    } catch (e) {
      debugPrint('[UserNotificationService/fetchUnreadCount] Error: $e');
      return 0;
    }
  }

  /// Mark a single notification as read.
  Future<void> markRead(String notificationId) async {
    try {
      await _supabase
          .from('user_submission_notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('[UserNotificationService/markRead] Error: $e');
    }
  }

  /// Mark all notifications as read for a user.
  Future<void> markAllRead(String userId) async {
    try {
      await _supabase
          .from('user_submission_notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('[UserNotificationService/markAllRead] Error: $e');
    }
  }

  /// Fetch the unread count periodically (streaming with filters not supported).
  Future<int> fetchUnreadCountOnce(String userId) async {
    return fetchUnreadCount(userId);
  }
}