import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/services/supabase_service.dart';
import 'package:sappiire/mobile/utils/date_utils.dart';

enum SortField { date, formType }
enum SortOrder { asc, desc }

class HistoryController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final _supabase = Supabase.instance.client;
  final String userId;

  List<Map<String, dynamic>> submissions = [];
  List<Map<String, dynamic>> filtered = [];
  bool isLoading = true;
  String username = '';
  SortField sortField = SortField.date;
  SortOrder sortOrder = SortOrder.desc;

  HistoryController({required this.userId});

  Future<void> loadHistory() async {
    isLoading = true;
    notifyListeners();

    try {
      username = await _supabaseService.getUsername(userId) ?? '';
      final rawSubmissions = await _supabaseService.fetchClientSubmissionHistoryByUser(userId);
      submissions = await _resolveAssistedBy(rawSubmissions);
      _applySort();
    } catch (e) {
      debugPrint('_loadHistory error: $e');
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
        debugPrint('HistoryController profile resolution error: $e');
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
        debugPrint('HistoryController account resolution error: $e');
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
