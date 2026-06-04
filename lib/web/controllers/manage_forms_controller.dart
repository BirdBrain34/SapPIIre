import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/forms/submission_service.dart';

class ManageFormsController {
  ManageFormsController({SubmissionService? submissionService})
    : _submissionService = submissionService ?? SubmissionService();

  final SubmissionService _submissionService;

  String? fingerprintPayload(Map<String, dynamic> payload) {
    try {
      final normalized = _normalizeForFingerprint(payload);
      return jsonEncode(normalized);
    } catch (_) {
      return payload.toString();
    }
  }

  dynamic _normalizeForFingerprint(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final normalized = <String, dynamic>{};
      for (final key in keys) {
        normalized[key] = _normalizeForFingerprint(value[key]);
      }
      return normalized;
    }
    if (value is List) {
      return value.map(_normalizeForFingerprint).toList();
    }
    return value;
  }

  String buildTempReferencePreview(FormTemplate? template) {
    if (template == null) return 'N/A';
    if (!template.requiresReference) return 'Reference disabled for this form';

    final now = DateTime.now();
    var preview = template.referenceFormat;
    final prefix =
        (template.referencePrefix?.trim().isNotEmpty == true
                ? template.referencePrefix!
                : (template.formCode?.trim().isNotEmpty == true
                      ? template.formCode!
                      : 'FORM'))
            .toUpperCase();

    String pad(int v, int len) => v.toString().padLeft(len, '0');
    final yearStart = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(yearStart).inDays + 1;
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final weekOfYear = ((dayOfYear - 1) ~/ 7) + 1;

    preview = preview.replaceAll('{FORMCODE}', prefix);
    preview = preview.replaceAll('{YYYY}', now.year.toString());
    preview = preview.replaceAll('{YY}', now.year.toString().substring(2));
    preview = preview.replaceAll('{MM}', pad(now.month, 2));
    preview = preview.replaceAll(
      '{MON}',
      const [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ][now.month - 1],
    );
    preview = preview.replaceAll(
      '{MONTH}',
      const [
        'JANUARY',
        'FEBRUARY',
        'MARCH',
        'APRIL',
        'MAY',
        'JUNE',
        'JULY',
        'AUGUST',
        'SEPTEMBER',
        'OCTOBER',
        'NOVEMBER',
        'DECEMBER',
      ][now.month - 1],
    );
    preview = preview.replaceAll('{DD}', pad(now.day, 2));
    preview = preview.replaceAll('{DDD}', pad(dayOfYear, 3));
    preview = preview.replaceAll('{Q}', '$quarter');
    preview = preview.replaceAll('{WW}', pad(weekOfYear, 2));
    preview = preview.replaceAll('{IW}', pad(weekOfYear, 2));
    preview = preview.replaceAll('{HH24}', pad(now.hour, 2));
    preview = preview.replaceAll('{MI}', pad(now.minute, 2));
    preview = preview.replaceAll('{SS}', pad(now.second, 2));

    preview = preview.replaceAll('{########}', '????????');
    preview = preview.replaceAll('{######}', '??????');
    preview = preview.replaceAll('{####}', '????');
    preview = preview.replaceAll('{###}', '???');
    preview = preview.replaceAll('{##}', '??');
    preview = preview.replaceAll('{#}', '?');
    return preview;
  }

  Future<void> preserveComputedValues({
    required FormTemplate template,
    required Map<String, dynamic> targetData,
    required Map<String, dynamic> sourceData,
  }) async {
    for (final field in template.allFields) {
      if (field.fieldType != FormFieldType.computed) continue;
      if (targetData.containsKey(field.fieldName)) continue;

      final scannedValue = sourceData[field.fieldName];
      if (scannedValue == null) continue;
      if (scannedValue.toString().trim().isEmpty) continue;

      targetData[field.fieldName] = scannedValue;
    }
  }

  Future<Map<String, String>?> resolveNameViaCanonicalRpc(String userId) async {
    try {
      final row = await _submissionService.fetchCanonicalNameByUserId(userId);
      if (row == null) return null;

      final last = (row['last'] ?? '').trim();
      final first = (row['first'] ?? '').trim();
      final mid = (row['middle'] ?? '').trim();

      if (last.isEmpty && first.isEmpty) return null;
      return {'last': last, 'first': first, 'middle': mid};
    } catch (e) {
      debugPrint('[ManageFormsController/resolveNameViaCanonicalRpc] Error: $e');
      return null;
    }
  }

  Future<void> embedApplicantName({
    required String currentSessionId,
    required FormTemplate? selectedTemplate,
    required Map<String, dynamic> formData,
  }) async {
    if (currentSessionId != 'WAITING-FOR-SESSION') {
      try {
        final userId = await _submissionService.fetchSessionUserId(currentSessionId);

        if (userId != null && userId.isNotEmpty) {
          final name = await resolveNameViaCanonicalRpc(userId);
          if (name != null) {
            formData['__applicant_name'] = name;
            return;
          }
        }
      } catch (e) {
        debugPrint('[ManageFormsController/embedApplicantName] Error: $e');
      }
    }

    if (selectedTemplate != null) {
      String last = '', first = '', mid = '';
      for (final field in selectedTemplate.allFields) {
        final key = (field.canonicalFieldKey ?? '').trim().toLowerCase();
        final lbl = field.fieldLabel.toLowerCase();
        if (key == 'last_name' || (lbl.contains('last') && lbl.contains('name'))) {
          last = formData[field.fieldName]?.toString() ?? '';
        }
        if (key == 'first_name' || (lbl.contains('first') && lbl.contains('name'))) {
          first = formData[field.fieldName]?.toString() ?? '';
        }
        if (key == 'middle_name' || (lbl.contains('middle') && lbl.contains('name'))) {
          mid = formData[field.fieldName]?.toString() ?? '';
        }
      }
      if (last.isNotEmpty || first.isNotEmpty) {
        formData['__applicant_name'] = {
          'last': last,
          'first': first,
          'middle': mid,
        };
        return;
      }
    }

    String last = '', first = '', mid = '';
    for (final key in formData.keys) {
      final lk = key.toLowerCase();
      final val = formData[key]?.toString() ?? '';
      if (val.isEmpty) continue;
      if (lk.contains('last') && lk.contains('name') && last.isEmpty) {
        last = val;
      }
      if (lk.contains('first') && lk.contains('name') && first.isEmpty) {
        first = val;
      }
      if (lk.contains('middle') && lk.contains('name') && mid.isEmpty) {
        mid = val;
      }
    }
    if (last.isNotEmpty || first.isNotEmpty) {
      formData['__applicant_name'] = {
        'last': last,
        'first': first,
        'middle': mid,
      };
    }
  }
}
