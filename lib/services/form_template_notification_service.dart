// Service for subscribing to real-time form template change notifications.
// Uses Supabase Realtime to listen to the form_template_notifications table.
// This table is populated by database triggers when form_templates are
// created, updated, published, or pushed to mobile.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TemplateNotification {
  final String id;
  final String? templateId;
  final String templateName;
  final String changeType; // 'added', 'updated', 'deleted', 'field_added', 'field_updated', 'field_deleted', 'pushed_to_mobile', 'published', 'archived'
  final String changeSummary;
  final DateTime createdAt;

  const TemplateNotification({
    required this.id,
    this.templateId,
    required this.templateName,
    required this.changeType,
    required this.changeSummary,
    required this.createdAt,
  });

  factory TemplateNotification.fromMap(Map<String, dynamic> map) {
    return TemplateNotification(
      id: map['id']?.toString() ?? '',
      templateId: map['template_id']?.toString(),
      templateName: map['template_name']?.toString() ?? 'Unknown Form',
      changeType: map['change_type']?.toString() ?? 'updated',
      changeSummary: map['change_summary']?.toString() ?? 'A form has been updated.',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class FormTemplateNotificationService {
  static final FormTemplateNotificationService _instance =
      FormTemplateNotificationService._internal();
  factory FormTemplateNotificationService() => _instance;
  FormTemplateNotificationService._internal();

  final _supabase = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  /// Only rows with created_at strictly after this time are emitted.
  DateTime _cutoffTime = DateTime(1970);

  final StreamController<TemplateNotification> _notificationController =
      StreamController<TemplateNotification>.broadcast();

  Stream<TemplateNotification> get notificationStream =>
      _notificationController.stream;

  /// Start listening for template changes.
  /// Call this when ManageInfoScreen is mounted.
  Future<void> startListening() async {
    await stopListening();

    try {
      // Query the most recent notification timestamp.
      // Anything created before or at this moment is considered "already seen".
      final latestRow = await _supabase
          .from('form_template_notifications')
          .select('created_at')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _cutoffTime = DateTime.tryParse(
            latestRow?['created_at']?.toString() ?? '',
          ) ??
          DateTime(1970);

      _subscription = _supabase
          .from('form_template_notifications')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(50)
          .listen((List<Map<String, dynamic>> data) {
            if (data.isEmpty) return;

            // Collect rows that are strictly newer than our cutoff.
            final newRows = <Map<String, dynamic>>[];
            DateTime? maxEmittedTime;
            for (final row in data) {
              final createdAt = DateTime.tryParse(
                row['created_at']?.toString() ?? '',
              );
              if (createdAt == null) continue;
              if (createdAt.isAfter(_cutoffTime)) {
                newRows.add(row);
                if (maxEmittedTime == null ||
                    createdAt.isAfter(maxEmittedTime)) {
                  maxEmittedTime = createdAt;
                }
              }
            }

            if (newRows.isEmpty) return;

            // Emit in chronological order (oldest first) so the UI shows
            // notifications in the order they happened.
            newRows.sort((a, b) {
              final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                  DateTime(1970);
              final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                  DateTime(1970);
              return aTime.compareTo(bTime);
            });

            for (final row in newRows) {
              try {
                final notification = TemplateNotification.fromMap(row);
                _notificationController.add(notification);
              } catch (e) {
                debugPrint('FormTemplateNotificationService parse error: $e');
              }
            }

            // Advance the cutoff so these rows are never emitted again.
            if (maxEmittedTime != null) {
              _cutoffTime = maxEmittedTime;
            }
          }, onError: (e) {
            debugPrint('FormTemplateNotificationService.stream error: $e');
          });
    } catch (e) {
      debugPrint('FormTemplateNotificationService.startListening error: $e');
    }
  }

  /// Stop listening. Call this when ManageInfoScreen is disposed.
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopListening();
    _notificationController.close();
  }
}
