import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SlaComplianceSummary {
  final int compliant;
  final int breached;

  const SlaComplianceSummary({required this.compliant, required this.breached});

  int get total => compliant + breached;
}

class IssueTrendItem {
  final String label;
  final int currentCount;
  final int previousCount;

  const IssueTrendItem({
    required this.label,
    required this.currentCount,
    required this.previousCount,
  });

  int get delta => currentCount - previousCount;
}

class DashboardAnalyticsService {
  static final DashboardAnalyticsService _instance =
      DashboardAnalyticsService._internal();

  factory DashboardAnalyticsService() => _instance;

  DashboardAnalyticsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, int>> fetchCountsByFormType() async {
    try {
      final rows = await _supabase
          .from('client_submissions')
          .select('form_type');
      final counts = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final formType = row['form_type']?.toString().trim();
        final key = (formType == null || formType.isEmpty)
            ? 'Unknown'
            : formType;
        counts[key] = (counts[key] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      debugPrint('fetchCountsByFormType error: $e');
      return {};
    }
  }

  Future<SlaComplianceSummary> fetchCitizenCharterCompliance({
    int targetMinutes = 60,
  }) async {
    try {
      final sessions = await _supabase
          .from('form_submission')
          .select('id, created_at');

      final submissions = await _supabase
          .from('client_submissions')
          .select('session_id, created_at');

      final sessionStart = <String, DateTime>{};
      for (final row in List<Map<String, dynamic>>.from(sessions)) {
        final id = row['id']?.toString();
        final createdAt = DateTime.tryParse(
          row['created_at']?.toString() ?? '',
        );
        if (id == null || id.isEmpty || createdAt == null) {
          continue;
        }
        sessionStart[id] = createdAt;
      }

      var compliant = 0;
      var breached = 0;

      for (final row in List<Map<String, dynamic>>.from(submissions)) {
        final sessionId = row['session_id']?.toString();
        final completedAt = DateTime.tryParse(
          row['created_at']?.toString() ?? '',
        );
        if (sessionId == null || completedAt == null) {
          continue;
        }

        final startedAt = sessionStart[sessionId];
        if (startedAt == null) {
          continue;
        }

        final duration = completedAt.difference(startedAt).inMinutes;
        if (duration <= targetMinutes) {
          compliant++;
        } else {
          breached++;
        }
      }

      return SlaComplianceSummary(compliant: compliant, breached: breached);
    } catch (e) {
      debugPrint('fetchCitizenCharterCompliance error: $e');
      return const SlaComplianceSummary(compliant: 0, breached: 0);
    }
  }

  Future<Map<String, int>> fetchPendingVsCompletedLoad() async {
    try {
      final rows = await _supabase.from('form_submission').select('status');
      final output = <String, int>{'Pending': 0, 'Completed': 0};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final status = row['status']?.toString().trim().toLowerCase() ?? '';
        if (status == 'completed') {
          output['Completed'] = (output['Completed'] ?? 0) + 1;
        } else {
          output['Pending'] = (output['Pending'] ?? 0) + 1;
        }
      }

      return output;
    } catch (e) {
      debugPrint('fetchPendingVsCompletedLoad error: $e');
      return {'Pending': 0, 'Completed': 0};
    }
  }

  Future<Map<String, int>> fetchStaffWorkloadDistribution({
    int topN = 8,
  }) async {
    try {
      final rows = await _supabase
          .from('audit_logs')
          .select('actor_id, actor_name')
          .order('created_at', ascending: false)
          .limit(500);

      final actorIds = List<Map<String, dynamic>>.from(rows)
          .map((row) => row['actor_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final nameByActorId = await _fetchStaffDisplayNames(actorIds);

      final output = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final actorId = row['actor_id']?.toString().trim() ?? '';
        final actorName = row['actor_name']?.toString().trim() ?? '';

        var label = nameByActorId[actorId] ?? '';
        if (label.isEmpty) {
          label = _sanitizeActorLabel(actorName);
        }
        if (label.isEmpty) {
          label = _sanitizeActorLabel(actorId);
        }

        if (label.isEmpty) {
          continue;
        }

        output[label] = (output[label] ?? 0) + 1;
      }

      final sorted = output.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return {for (final entry in sorted.take(topN)) entry.key: entry.value};
    } catch (e) {
      debugPrint('fetchStaffWorkloadDistribution error: $e');
      return {};
    }
  }

  Future<Map<String, String>> _fetchStaffDisplayNames(
    List<String> actorIds,
  ) async {
    if (actorIds.isEmpty) {
      return {};
    }

    try {
      final accounts = await _supabase
          .from('staff_accounts')
          .select('cswd_id, username, email')
          .inFilter('cswd_id', actorIds);
      final profiles = await _supabase
          .from('staff_profiles')
          .select('cswd_id, first_name, middle_name, last_name')
          .inFilter('cswd_id', actorIds);

      final profileById = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(profiles)) {
        final id = row['cswd_id']?.toString().trim() ?? '';
        if (id.isEmpty) {
          continue;
        }
        profileById[id] = row;
      }

      final displayNames = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(accounts)) {
        final id = row['cswd_id']?.toString().trim() ?? '';
        if (id.isEmpty) {
          continue;
        }

        final profile = profileById[id] ?? const <String, dynamic>{};
        final first = profile['first_name']?.toString().trim() ?? '';
        final middle = profile['middle_name']?.toString().trim() ?? '';
        final last = profile['last_name']?.toString().trim() ?? '';

        final middleInitial = middle.isNotEmpty ? ' ${middle[0]}.' : '';
        final fullName = '$first$middleInitial $last'.trim();
        final username = row['username']?.toString().trim() ?? '';
        final email = row['email']?.toString().trim() ?? '';

        var label = fullName;
        if (label.isEmpty) {
          label = _sanitizeActorLabel(username);
        }
        if (label.isEmpty) {
          label = _sanitizeActorLabel(email);
        }

        if (label.isNotEmpty) {
          displayNames[id] = label;
        }
      }

      return displayNames;
    } catch (e) {
      debugPrint('_fetchStaffDisplayNames error: $e');
      return {};
    }
  }

  String _sanitizeActorLabel(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return '';
    }

    if (_isUuid(value)) {
      return '';
    }

    if (value.contains('@')) {
      final localPart = value.split('@').first.trim();
      return _isUuid(localPart) ? '' : localPart;
    }

    return value;
  }

  bool _isUuid(String value) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(value);
  }

  Future<Map<String, int>> fetchGenderRatio({String formType = 'All'}) async {
    try {
      final rows = await _fetchSubmissionDataRows(formType: formType);
      final dist = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final value = _extractFieldValue(data, 'Kasarian');
        if (value.isEmpty) {
          continue;
        }

        final normalized = _normalizeGenderLabel(value);
        if (normalized.isEmpty) {
          continue;
        }

        dist[normalized] = (dist[normalized] ?? 0) + 1;
      }

      return dist;
    } catch (e) {
      debugPrint('fetchGenderRatio error: $e');
      return {};
    }
  }

  Future<Map<String, int>> fetchAgeBracketDistribution({
    String formType = 'All',
  }) async {
    try {
      final rows = await _fetchSubmissionDataRows(formType: formType);
      final dist = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final age = _extractAge(data);
        if (age == null) {
          continue;
        }

        final bucket = _ageBucket(age);
        dist[bucket] = (dist[bucket] ?? 0) + 1;
      }

      return dist;
    } catch (e) {
      debugPrint('fetchAgeBracketDistribution error: $e');
      return {};
    }
  }

  Future<Map<String, int>> fetchBarangayVolume({
    String formType = 'All',
    int topN = 10,
  }) async {
    try {
      final rows = await _fetchSubmissionDataRows(formType: formType);
      final dist = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final value = _extractFieldValue(data, 'Barangay');
        if (value.isEmpty) {
          continue;
        }
        dist[value] = (dist[value] ?? 0) + 1;
      }

      final sorted = dist.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return {for (final entry in sorted.take(topN)) entry.key: entry.value};
    } catch (e) {
      debugPrint('fetchBarangayVolume error: $e');
      return {};
    }
  }

  Future<List<IssueTrendItem>> fetchIssueTrends({
    String formType = 'All',
    int topN = 6,
  }) async {
    try {
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final previousMonthStart = DateTime(now.year, now.month - 1, 1);

      final rows = formType == 'All'
          ? await _supabase
                .from('client_submissions')
                .select('data, created_at')
                .gte('created_at', previousMonthStart.toIso8601String())
          : await _supabase
                .from('client_submissions')
                .select('data, created_at')
                .eq('form_type', formType)
                .gte('created_at', previousMonthStart.toIso8601String());

      final current = <String, int>{};
      final previous = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final createdAt = DateTime.tryParse(
          row['created_at']?.toString() ?? '',
        );
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        if (createdAt == null) {
          continue;
        }

        final value = _extractIssueValue(data);
        if (value.isEmpty) {
          continue;
        }

        if (createdAt.isBefore(currentMonthStart)) {
          previous[value] = (previous[value] ?? 0) + 1;
        } else {
          current[value] = (current[value] ?? 0) + 1;
        }
      }

      final labels = <String>{...current.keys, ...previous.keys};
      final items = labels.map((label) {
        return IssueTrendItem(
          label: label,
          currentCount: current[label] ?? 0,
          previousCount: previous[label] ?? 0,
        );
      }).toList();

      items.sort((a, b) {
        final byDelta = b.delta.compareTo(a.delta);
        if (byDelta != 0) {
          return byDelta;
        }
        return b.currentCount.compareTo(a.currentCount);
      });

      return items.take(topN).toList();
    } catch (e) {
      debugPrint('fetchIssueTrends error: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> searchClientsByName(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      return [];
    }

    try {
      final rpcResult =
          await _supabase.rpc(
                'search_users_by_name_canonical',
                params: {'p_search': text, 'p_limit': 12},
              )
              as List<dynamic>;

      return rpcResult
          .cast<Map<String, dynamic>>()
          .map((row) {
            final uid = row['user_id']?.toString() ?? '';
            final last = (row['last_name'] as String?)?.trim() ?? '';
            final first = (row['first_name'] as String?)?.trim() ?? '';
            final middle = (row['middle_name'] as String?)?.trim() ?? '';
            final full =
                '$last, $first${middle.isNotEmpty ? ' ${middle[0]}.' : ''}'
                    .trim();

            return {
              'user_id': uid,
              'name': full.isEmpty ? 'Unknown Client' : full,
            };
          })
          .where((row) => (row['user_id'] ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('searchClientsByName error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchClientHistory(String userId) async {
    try {
      final sessions = await _supabase
          .from('form_submission')
          .select('id')
          .eq('user_id', userId);

      final sessionIds = List<Map<String, dynamic>>.from(sessions)
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (sessionIds.isEmpty) {
        return [];
      }

      final history = await _supabase
          .from('client_submissions')
          .select('id, form_type, created_at, intake_reference')
          .inFilter('session_id', sessionIds)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(history);
    } catch (e) {
      debugPrint('fetchClientHistory error: $e');
      return [];
    }
  }

  Future<Map<String, String>> fetchEligibilityFrequencyFlags(
    String userId,
  ) async {
    try {
      final history = await fetchClientHistory(userId);
      if (history.isEmpty) {
        return {};
      }

      final year = DateTime.now().year;
      final yearly = history.where((item) {
        final createdAt = DateTime.tryParse(
          item['created_at']?.toString() ?? '',
        );
        return createdAt != null && createdAt.year == year;
      }).toList();

      final perService = <String, int>{};
      for (final item in yearly) {
        final formType =
            item['form_type']?.toString().trim() ?? 'Unknown Service';
        perService[formType] = (perService[formType] ?? 0) + 1;
      }

      final flags = <String, String>{};
      perService.forEach((service, count) {
        if (count >= 3) {
          flags[service] = 'High frequency this year ($count)';
        } else if (count == 2) {
          flags[service] = 'Watch: repeat availment ($count)';
        }
      });

      return flags;
    } catch (e) {
      debugPrint('fetchEligibilityFrequencyFlags error: $e');
      return {};
    }
  }

  Future<Map<String, int>> fetchFieldDistribution({
    required String formType,
    required String fieldName,
    bool isNumeric = false,
    bool isMultiSelect = false,
    int topN = 10,
  }) async {
    try {
      final rows = await _supabase
          .from('client_submissions')
          .select('data')
          .eq('form_type', formType);

      final dist = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final raw = data[fieldName];

        if (raw == null) {
          continue;
        }

        if (isMultiSelect && raw is List) {
          for (final item in raw) {
            final value = item.toString().trim();
            if (value.isEmpty) {
              continue;
            }
            dist[value] = (dist[value] ?? 0) + 1;
          }
          continue;
        }

        if (isNumeric) {
          final parsed = double.tryParse(raw.toString().trim());
          if (parsed == null) {
            continue;
          }

          final bucket = _numericBucket(parsed);
          dist[bucket] = (dist[bucket] ?? 0) + 1;
          continue;
        }

        final value = raw.toString().trim();
        if (value.isEmpty) {
          continue;
        }
        dist[value] = (dist[value] ?? 0) + 1;
      }

      if (dist.length > topN) {
        final sorted = dist.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final top = sorted.take(topN).toList();
        final otherCount = sorted
            .skip(topN)
            .fold<int>(0, (sum, e) => sum + e.value);

        final trimmed = <String, int>{
          for (final entry in top) entry.key: entry.value,
        };

        if (otherCount > 0) {
          trimmed['Other'] = otherCount;
        }

        return trimmed;
      }

      return dist;
    } catch (e) {
      debugPrint('fetchFieldDistribution error: $e');
      return {};
    }
  }

  Future<Map<String, int>> fetchSubmissionCountsByFormType() async {
    return fetchCountsByFormType();
  }

  Future<int> fetchTotalCount() async {
    final counts = await fetchSubmissionCountsByFormType();
    return counts.values.fold<int>(0, (sum, count) => sum + count);
  }

  Future<List<Map<String, dynamic>>> fetchSubmissionsForFormType(
    String formType,
  ) async {
    try {
      final rows = formType == 'All'
          ? await _supabase
                .from('client_submissions')
                .select('id, form_type, data, created_at')
                .order('created_at', ascending: false)
          : await _supabase
                .from('client_submissions')
                .select('id, form_type, data, created_at')
                .eq('form_type', formType)
                .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint(
        'DashboardAnalyticsService.fetchSubmissionsForFormType error: $e',
      );
      return [];
    }
  }

  Future<Map<String, int>> getFieldDistribution(
    String formType,
    String fieldKey,
  ) async {
    try {
      final rows = formType == 'All'
          ? await _supabase
                .from('client_submissions')
                .select('data')
                .order('created_at', ascending: false)
          : await _supabase
                .from('client_submissions')
                .select('data')
                .eq('form_type', formType)
                .order('created_at', ascending: false);

      final distribution = <String, int>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final data =
            (row['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

        if (fieldKey == '__age_group') {
          final age = _extractAge(data);
          if (age == null) {
            continue;
          }
          final bucket = _ageBucket(age);
          distribution[bucket] = (distribution[bucket] ?? 0) + 1;
          continue;
        }

        if (fieldKey == '__membership') {
          final membershipDist = _membershipDistributionForSubmission(data);
          membershipDist.forEach((key, value) {
            distribution[key] = (distribution[key] ?? 0) + value;
          });
          continue;
        }

        final value = _extractFieldValue(data, fieldKey);
        if (value.isEmpty) {
          continue;
        }

        distribution[value] = (distribution[value] ?? 0) + 1;
      }

      return distribution;
    } catch (e) {
      debugPrint('DashboardAnalyticsService.getFieldDistribution error: $e');
      return {};
    }
  }

  String _numericBucket(double value) {
    if (value < 5000) {
      return 'Below P5,000';
    }
    if (value < 10000) {
      return 'P5,000-P10,000';
    }
    if (value < 20000) {
      return 'P10,000-P20,000';
    }
    if (value < 50000) {
      return 'P20,000-P50,000';
    }
    return 'Above P50,000';
  }

  Future<List<String>> fetchAvailableFormTypes() async {
    final counts = await fetchSubmissionCountsByFormType();
    final types = counts.keys.toList()..sort();
    return types;
  }

  Future<Map<String, int>> fetchMonthlyTrend(String formType) async {
    try {
      final rows = formType == 'All'
          ? await _supabase
                .from('client_submissions')
                .select('created_at')
                .order('created_at', ascending: true)
          : await _supabase
                .from('client_submissions')
                .select('created_at')
                .eq('form_type', formType)
                .order('created_at', ascending: true);

      final trend = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final createdAtRaw = row['created_at']?.toString();
        if (createdAtRaw == null || createdAtRaw.isEmpty) {
          continue;
        }

        final createdAt = DateTime.tryParse(createdAtRaw);
        if (createdAt == null) {
          continue;
        }

        final monthKey =
            '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}';
        trend[monthKey] = (trend[monthKey] ?? 0) + 1;
      }

      final sortedEntries = trend.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return {for (final entry in sortedEntries) entry.key: entry.value};
    } catch (e) {
      debugPrint('DashboardAnalyticsService.fetchMonthlyTrend error: $e');
      return {};
    }
  }

  String _extractFieldValue(Map<String, dynamic> data, String fieldKey) {
    final keyCandidates = _fieldKeyAliases[fieldKey] ?? <String>[fieldKey];

    for (final candidate in keyCandidates) {
      if (data.containsKey(candidate)) {
        return data[candidate]?.toString().trim() ?? '';
      }
    }

    final normalizedData = <String, dynamic>{};
    for (final entry in data.entries) {
      normalizedData[_normalize(entry.key)] = entry.value;
    }

    for (final candidate in keyCandidates) {
      final normalizedKey = _normalize(candidate);
      if (!normalizedData.containsKey(normalizedKey)) {
        continue;
      }

      final value = normalizedData[normalizedKey]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  int? _extractAge(Map<String, dynamic> data) {
    final ageRaw = _extractFieldValue(data, 'Age');
    if (ageRaw.isEmpty) {
      return null;
    }

    final number = int.tryParse(ageRaw.replaceAll(RegExp(r'[^0-9]'), ''));
    return number;
  }

  String _ageBucket(int age) {
    if (age <= 17) {
      return 'Youth (<=17)';
    }
    if (age <= 25) {
      return 'Young Adult (18-25)';
    }
    if (age <= 40) {
      return 'Adult (26-40)';
    }
    if (age <= 60) {
      return 'Middle Age (41-60)';
    }
    return 'Senior (61+)';
  }

  Map<String, int> _membershipDistributionForSubmission(
    Map<String, dynamic> data,
  ) {
    final output = <String, int>{
      '4Ps Member': 0,
      'PWD': 0,
      'Solo Parent': 0,
      'PHIC Member': 0,
      'None': 0,
    };

    final membership =
        (data['__membership'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    var hasMembership = false;

    if (membership['four_ps_member'] == true) {
      output['4Ps Member'] = 1;
      hasMembership = true;
    }
    if (membership['pwd'] == true) {
      output['PWD'] = 1;
      hasMembership = true;
    }
    if (membership['solo_parent'] == true) {
      output['Solo Parent'] = 1;
      hasMembership = true;
    }
    if (membership['phic_member'] == true) {
      output['PHIC Member'] = 1;
      hasMembership = true;
    }

    if (!hasMembership) {
      output['None'] = 1;
    }

    return output;
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _normalizeGenderLabel(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final token = _normalize(trimmed);
    if (token.isEmpty) {
      return '';
    }

    if (token == 'm' ||
        token.contains('male') ||
        token.contains('lalaki') ||
        token.contains('boy') ||
        token.startsWith('m_')) {
      return 'Male';
    }

    if (token == 'f' ||
        token.contains('female') ||
        token.contains('babae') ||
        token.contains('girl') ||
        token.startsWith('f_')) {
      return 'Female';
    }

    return trimmed;
  }

  static const Map<String, List<String>> _fieldKeyAliases = {
    'Kasarian': ['Kasarian', 'kasarian', 'kasarian_sex', 'sex', 'gender'],
    'Age': ['Age', 'age', 'edad'],
    'Barangay': ['Barangay', 'barangay', 'brgy', 'address.barangay'],
    'Issue': [
      'Issue',
      'issue',
      'issue_type',
      'need',
      'needs',
      'top_need',
      'concern',
      'problem',
      'service_need',
      'assistance_type',
      'reason',
    ],
    'Buwanang Kita (A)': [
      'Buwanang Kita (A)',
      'buwanang_kita_a',
      'buwanang_kita',
      'monthly_income',
      'income',
    ],
  };

  String _extractIssueValue(Map<String, dynamic> data) {
    final value = _extractFieldValue(data, 'Issue');
    String codedValue = '';

    if (value.isNotEmpty) {
      if (!_isNumericCode(value)) {
        return value;
      }
      codedValue = value;
    }

    final structuredLabel = _extractIssueLabelFromStructuredData(
      data,
      codedValue: codedValue,
    );
    if (structuredLabel.isNotEmpty) {
      return structuredLabel;
    }

    final keys = data.keys.toList();
    for (final key in keys) {
      final normalized = _normalize(key);
      if (!(normalized.contains('issue') ||
          normalized.contains('need') ||
          normalized.contains('concern') ||
          normalized.contains('problem') ||
          normalized.contains('assistance') ||
          normalized.contains('service'))) {
        continue;
      }

      final raw = data[key];
      if (raw is List && raw.isNotEmpty) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            final label = _extractReadableLabelFromMap(
              item,
              codedValue: codedValue,
            );
            if (label.isNotEmpty) {
              return label;
            }
            continue;
          }

          final text = item.toString().trim();
          if (text.isEmpty) {
            continue;
          }
          if (_isNumericCode(text)) {
            codedValue = codedValue.isEmpty ? text : codedValue;
            continue;
          }
          return text;
        }
      }

      if (raw is Map<String, dynamic>) {
        final label = _extractReadableLabelFromMap(raw, codedValue: codedValue);
        if (label.isNotEmpty) {
          return label;
        }
        continue;
      }

      final text = raw?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        if (_isNumericCode(text)) {
          codedValue = codedValue.isEmpty ? text : codedValue;
          continue;
        }
        return text;
      }
    }

    return codedValue.isEmpty ? '' : 'Need Code $codedValue';
  }

  String _extractIssueLabelFromStructuredData(
    Map<String, dynamic> data, {
    required String codedValue,
  }) {
    for (final entry in data.entries) {
      final normalizedKey = _normalize(entry.key);
      if (!(normalizedKey.contains('issue') ||
          normalizedKey.contains('need') ||
          normalizedKey.contains('concern') ||
          normalizedKey.contains('problem') ||
          normalizedKey.contains('assistance') ||
          normalizedKey.contains('service') ||
          normalizedKey.contains('reason'))) {
        continue;
      }

      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final label = _extractReadableLabelFromMap(
          value,
          codedValue: codedValue,
        );
        if (label.isNotEmpty) {
          return label;
        }
      }
    }

    return '';
  }

  String _extractReadableLabelFromMap(
    Map<String, dynamic> mapValue, {
    required String codedValue,
  }) {
    const preferredKeys = ['label', 'name', 'title', 'text'];
    for (final key in preferredKeys) {
      final value = mapValue[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && !_isNumericCode(value)) {
        return value;
      }
    }

    if (codedValue.isNotEmpty) {
      const matchKeys = ['value', 'id', 'code'];
      for (final key in matchKeys) {
        final v = mapValue[key]?.toString().trim() ?? '';
        if (v == codedValue) {
          for (final preferred in preferredKeys) {
            final label = mapValue[preferred]?.toString().trim() ?? '';
            if (label.isNotEmpty && !_isNumericCode(label)) {
              return label;
            }
          }
        }
      }
    }

    return '';
  }

  bool _isNumericCode(String value) {
    return RegExp(r'^\d+$').hasMatch(value.trim());
  }

  Future<List<Map<String, dynamic>>> _fetchSubmissionDataRows({
    required String formType,
  }) async {
    if (formType == 'All') {
      final rows = await _supabase.from('client_submissions').select('data');
      return List<Map<String, dynamic>>.from(rows);
    }

    final rows = await _supabase
        .from('client_submissions')
        .select('data')
        .eq('form_type', formType);
    return List<Map<String, dynamic>>.from(rows);
  }
}
