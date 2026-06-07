import 'package:flutter/material.dart';
import 'package:sappiire/models/form_template_models.dart';

class ApplicantGroup {
  final String key;
  final String displayName;
  final List<Map<String, dynamic>> submissions;

  const ApplicantGroup({
    required this.key,
    required this.displayName,
    required this.submissions,
  });
}

enum RecordSortOrder { latestFirst, oldestFirst }

class ApplicantsController {
  const ApplicantsController();

  String getApplicantName(
    Map<String, dynamic> submission,
    Map<String, FormTemplate> templateCache,
  ) {
    final directName = _resolveDirectApplicantName(submission);
    if (directName != null) {
      return directName;
    }

    var data = submission['data'];

    if (data is! Map) {
      return 'Unknown Applicant (Encrypted)';
    }

    final dataMap = Map<String, dynamic>.from(data);

    if (dataMap['__applicant_name'] is Map) {
      final n = dataMap['__applicant_name'] as Map<String, dynamic>;
      final embeddedNameLooksValid = hasUsableEmbeddedApplicantName(dataMap);
      if (embeddedNameLooksValid) {
        final name = formatName(n);
        if (name != null) return name;
      }
    }

    final last = findNameValue(dataMap, [
      'last_name',
      'Last Name',
      'lastname',
      'Apelyido',
    ]);
    final first = findNameValue(dataMap, [
      'first_name',
      'First Name',
      'firstname',
      'Pangalan',
    ]);
    final middle = findNameValue(dataMap, [
      'middle_name',
      'Middle Name',
      'middle_name',
      'Gitnang Pangalan',
    ]);

    if (last.isEmpty && first.isEmpty) {
      final formType = submission['form_type'] as String? ?? '';
      final template = templateCache[formType];
      if (template != null) {
        String tLast = '', tFirst = '', tMid = '';
        for (final field in template.allFields) {
          final key = (field.canonicalFieldKey ?? '').trim().toLowerCase();
          final lbl = field.fieldLabel.toLowerCase();
          final val = dataMap[field.fieldName]?.toString() ?? '';
          if (val.isEmpty) continue;
          if (key == 'last_name' ||
              lbl.contains('last') && lbl.contains('name')) {
            tLast = val;
          }
          if (key == 'first_name' ||
              lbl.contains('first') && lbl.contains('name')) {
            tFirst = val;
          }
          if (key == 'middle_name' ||
              lbl.contains('middle') && lbl.contains('name')) {
            tMid = val;
          }
        }
        final tName = formatName({
          'last': tLast,
          'first': tFirst,
          'middle': tMid,
        });
        if (tName != null) return tName;
      }
    }

    if (first.isEmpty && last.isEmpty) return 'Unknown Applicant';
    return formatName({'last': last, 'first': first, 'middle': middle}) ??
        'Unknown Applicant';
  }

  String? formatName(Map<dynamic, dynamic> n) {
    final last = (n['last'] ?? '').toString().trim();
    final first = (n['first'] ?? '').toString().trim();
    final mid = (n['middle'] ?? '').toString().trim();
    if (last.isEmpty && first.isEmpty) return null;
    return '$last, $first${mid.isNotEmpty ? ' ${mid[0]}.' : ''}'.trim();
  }

  String findNameValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final val = data[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  String? _resolveDirectApplicantName(Map<String, dynamic> submission) {
    final directMapCandidates = [
      submission['applicant_name'],
      submission['display_name'],
      submission['full_name'],
    ];

    for (final candidate in directMapCandidates) {
      if (candidate is Map) {
        final name = formatName(Map<dynamic, dynamic>.from(candidate));
        if (name != null && name.trim().isNotEmpty) return name;
        continue;
      }

      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    final first = submission['first_name']?.toString().trim() ?? '';
    final middle = submission['middle_name']?.toString().trim() ?? '';
    final last = submission['last_name']?.toString().trim() ?? '';
    if (first.isEmpty && middle.isEmpty && last.isEmpty) {
      return null;
    }

    return formatName({'last': last, 'first': first, 'middle': middle});
  }

  bool hasUsableEmbeddedApplicantName(Map<String, dynamic> data) {
    final raw = data['__applicant_name'];
    if (raw is! Map) return false;

    final last = (raw['last'] ?? '').toString().trim();
    final first = (raw['first'] ?? '').toString().trim();

    if (last.isEmpty && first.isEmpty) return false;
    if (looksEncryptedToken(last) || looksEncryptedToken(first)) {
      return false;
    }
    return true;
  }

  bool looksEncryptedToken(String value) {
    final v = value.trim();
    if (v.length < 24) return false;
    if (v.contains(' ') || v.contains(',')) return false;
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(v)) return false;
    return RegExp(r'[0-9+/=]').hasMatch(v);
  }

  String? findApplicantId(Map<String, dynamic> submission) {
    final data = submission['data'] is Map
        ? Map<String, dynamic>.from(submission['data'] as Map)
        : <String, dynamic>{};
    final candidates = [
      submission['applicant_id'],
      submission['user_id'],
      submission['session_id'],
      submission['sessionId'],
      submission['submission_session_id'],
      data['__applicant_id'],
      data['applicant_id'],
      data['client_id'],
      data['user_id'],
      data['__user_id'],
    ];
    for (final c in candidates) {
      final v = (c ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  DateTime parseCreatedAt(Map<String, dynamic> submission) {
    final created = submission['created_at']?.toString();
    if (created == null || created.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(created) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<ApplicantGroup> groupedApplicants({
    required List<Map<String, dynamic>> submissions,
    required String searchQuery,
    required Map<String, FormTemplate> templateCache,
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final groupName = <String, String>{};

    for (final s in submissions) {
      final applicantId = findApplicantId(s);
      final displayName = getApplicantName(s, templateCache);
      final key = applicantId != null && applicantId.isNotEmpty
          ? 'id:$applicantId'
          : 'name:${displayName.toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(s);
      groupName[key] = displayName;
    }

    final q = searchQuery.trim().toLowerCase();
    final groups = <ApplicantGroup>[];

    for (final entry in grouped.entries) {
      final sortedSubmissions = List<Map<String, dynamic>>.from(entry.value)
        ..sort((a, b) => parseCreatedAt(b).compareTo(parseCreatedAt(a)));

      final name = groupName[entry.key] ?? 'Unknown Applicant';
      if (q.isNotEmpty) {
        final matchesGroup =
            name.toLowerCase().contains(q) ||
            entry.key.toLowerCase().contains(q);
        if (!matchesGroup) continue;
      }

      groups.add(
        ApplicantGroup(
          key: entry.key,
          displayName: name,
          submissions: sortedSubmissions,
        ),
      );
    }

    groups.sort((a, b) {
      final ad = a.submissions.isNotEmpty
          ? parseCreatedAt(a.submissions.first)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.submissions.isNotEmpty
          ? parseCreatedAt(b.submissions.first)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return groups;
  }

  List<Map<String, dynamic>> sortedSubmissionsForGroup({
    required ApplicantGroup group,
    required String formTypeFilter,
    required RecordSortOrder sortOrder,
  }) {
    final sorted = List<Map<String, dynamic>>.from(group.submissions);

    if (formTypeFilter != 'All') {
      sorted.removeWhere(
        (s) => (s['form_type']?.toString() ?? '') != formTypeFilter,
      );
    }

    sorted.sort((a, b) {
      final compare = parseCreatedAt(a).compareTo(parseCreatedAt(b));
      return sortOrder == RecordSortOrder.latestFirst ? -compare : compare;
    });
    return sorted;
  }

  List<String> formTypeOptionsForGroup(ApplicantGroup group) {
    final options = <String>{'All'};
    for (final submission in group.submissions) {
      final formType = submission['form_type']?.toString().trim() ?? '';
      if (formType.isNotEmpty) options.add(formType);
    }
    final types = options.where((o) => o != 'All').toList()..sort();
    return ['All', ...types];
  }

  String getFormattedDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String getIntakeRefLabel(Map<String, dynamic> submission) {
    final ref = (submission['intake_reference'] as String?)?.trim();
    if (ref == null || ref.isEmpty) return 'No reference';
    return ref;
  }

  String formTypeBadgeText(String formType) {
    final trimmed = formType.trim();
    if (trimmed.isEmpty) return 'FORM';
    if (!trimmed.contains(' ') && trimmed.length <= 8) {
      return trimmed.toUpperCase();
    }
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.map((p) => p[0].toUpperCase()).join();
    return initials.isEmpty ? 'FORM' : initials;
  }

  Color formTypeBadgeColor(String formType) {
    final key = formType.toLowerCase();
    if (key.contains('gis') || key.contains('general intake')) {
      return const Color(0xFF1FA663);
    }
    if (key.contains('eafic')) {
      return const Color(0xFF2B74E4);
    }
    if (key.contains('case')) {
      return const Color(0xFF8A6BDB);
    }
    return const Color(0xFF4F8A8B);
  }
}
