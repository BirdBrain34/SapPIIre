// Service for managing active display sessions.
//
// The `display_sessions` table acts as the bridge between the Worker Dashboard
// and the Customer Display monitor.  When a worker starts/changes a session the
// row is upserted, and the /display screen picks up changes via Supabase
// Realtime.
//
// Table: display_sessions
//   station_id   text   PK   (e.g. "desk_1")
//   session_id   text          FK → form_submission.id (nullable)
//   template_id  text          FK → form_templates.id (nullable)
//   form_name    text          human-readable template name
//   status       text          'active' | 'standby'
//   updated_at   timestamptz   default now()

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class DisplaySessionService {
  static final DisplaySessionService _instance = DisplaySessionService._();
  factory DisplaySessionService() => _instance;
  DisplaySessionService._();

  final _supabase = Supabase.instance.client;

  static const _table = 'display_sessions';

  /// Upsert the display session row for [stationId].
  /// Called from the Worker Dashboard whenever a new QR session starts.
  Future<void> pushSession({
    required String stationId,
    required String sessionId,
    required String templateId,
    required String formName,
  }) async {
    await _supabase.from(_table).upsert({
      'station_id': stationId,
      'session_id': sessionId,
      'template_id': templateId,
      'form_name': formName,
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Reset the station back to standby (called after finalize / session end).
  Future<void> resetStation(String stationId) async {
    await _supabase.from(_table).upsert({
      'station_id': stationId,
      'session_id': null,
      'template_id': null,
      'form_name': null,
      'status': 'standby',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Subscribe to realtime changes for a specific [stationId].
  /// Returns a StreamSubscription so the caller can cancel it.
  StreamSubscription<List<Map<String, dynamic>>> listenStation(
    String stationId,
    void Function(Map<String, dynamic>? row) onUpdate,
  ) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['station_id'])
        .eq('station_id', stationId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isEmpty) {
            onUpdate(null);
          } else {
            onUpdate(data.first);
          }
        });
  }
}
