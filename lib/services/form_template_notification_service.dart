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
  final Set<String> _knownNotificationIds = <String>{};
  final Map<String, String> _notificationFingerprints = <String, String>{};

  final StreamController<TemplateNotification> _notificationController =
      StreamController<TemplateNotification>.broadcast();

  Stream<TemplateNotification> get notificationStream =>
      _notificationController.stream;

  /// Start listening for template changes.
  /// Call this when ManageInfoScreen is mounted.
  Future<void> startListening() async {
    await stopListening();
    _knownNotificationIds.clear();
    _notificationFingerprints.clear();
    try {
      // Seed known IDs so only notifications created after opening the screen are shown.
      final existingRows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('form_template_notifications')
            .select('id, change_type, change_summary, created_at')
            .order('created_at', ascending: false)
            .limit(50),
      );
      for (final row in existingRows) {
        final rowId = row['id']?.toString();
        if (rowId == null || rowId.isEmpty) continue;
        _knownNotificationIds.add(rowId);
        _notificationFingerprints[rowId] = _fingerprintRow(row);
      }

      _subscription = _supabase
          .from('form_template_notifications')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(50)
          .listen((List<Map<String, dynamic>> data) {
            if (data.isEmpty) return;

            // Emit all unseen rows in chronological order. This catches rapid
            // consecutive inserts, including field-level notifications.
            final orderedRows = List<Map<String, dynamic>>.from(data.reversed);
            for (final row in orderedRows) {
              final rowId = row['id']?.toString();
              if (rowId == null || rowId.isEmpty) continue;

              final nextFingerprint = _fingerprintRow(row);
              final isKnown = _knownNotificationIds.contains(rowId);
              final hasChanged = _notificationFingerprints[rowId] != nextFingerprint;
              if (isKnown && !hasChanged) continue;

              _knownNotificationIds.add(rowId);
              _notificationFingerprints[rowId] = nextFingerprint;

              try {
                final notification = TemplateNotification.fromMap(row);
                _notificationController.add(notification);
              } catch (e) {
                debugPrint('FormTemplateNotificationService parse error: $e');
              }
            }
            // Keep memory bounded while still avoiding duplicate emissions.
            if (_knownNotificationIds.length > 500) {
              final latestIds = data
                  .map((row) => row['id']?.toString())
                  .whereType<String>()
                  .toSet();
              final latestFingerprints = <String, String>{};
              for (final row in data) {
                final rowId = row['id']?.toString();
                if (rowId == null || rowId.isEmpty) continue;
                latestFingerprints[rowId] = _fingerprintRow(row);
              }
              _knownNotificationIds
                ..clear()
                ..addAll(latestIds);
              _notificationFingerprints
                ..clear()
                ..addAll(latestFingerprints);
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

  String _fingerprintRow(Map<String, dynamic> row) {
    final changeType = row['change_type']?.toString() ?? '';
    final changeSummary = row['change_summary']?.toString() ?? '';
    final createdAt = row['created_at']?.toString() ?? '';
    return '$changeType|$changeSummary|$createdAt';
  }

  void dispose() {
    stopListening();
    _notificationController.close();
  }
}
