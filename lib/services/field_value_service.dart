// Saves/loads field values for ANY template using field_id as the key.
// Works for GIS and every custom template — no migration needed per form.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_template_models.dart';
import 'form_template_service.dart';

class FieldValueService {
  static final FieldValueService _instance = FieldValueService._internal();
  factory FieldValueService() => _instance;
  FieldValueService._internal();

  final _supabase = Supabase.instance.client;

  // Field types stored in dedicated tables or derived — skip from generic save.
  static const _skipTypes = {
    FormFieldType.familyTable,
    FormFieldType.supportingFamilyTable,
    FormFieldType.membershipGroup,
  };
  static const _clearedSentinel = '__CLEARED__';

  // ── SAVE: upsert all field values to user_field_values ────
  Future<bool> saveUserFieldValues({
    required String userId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      final eligibleFieldIds = eligible.map((f) => f.fieldId).toList();
      if (eligibleFieldIds.isEmpty) return true;

      // Build rows for fields that currently have values.
      final rows = _buildFieldRows(
        template,
        formData,
        (field, strValue) => {
          'user_id': userId,
          'field_id': field.fieldId,
          'field_value': strValue,
        },
      );

      final keys = await HybridCryptoService.fetchUserFieldKeys(userId);
      final encryptableIndices = <int>[];
      final plaintexts = <String>[];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final fieldValue = row['field_value'] as String? ?? '';
        if (fieldValue.isEmpty || fieldValue == _clearedSentinel) {
          row['iv'] = null;
          row['encryption_version'] = 0;
          continue;
        }

        encryptableIndices.add(i);
        plaintexts.add(fieldValue);
      }

      if (plaintexts.isNotEmpty) {
        final results = await HybridCryptoService.encryptFieldBatch(
          plaintexts,
          keys,
        );

        if (results.length != encryptableIndices.length) {
          throw Exception('Batch encryption result length mismatch.');
        }

        for (var i = 0; i < encryptableIndices.length; i++) {
          final row = rows[encryptableIndices[i]];
          final encrypted = results[i];
          row['field_value'] = encrypted.ciphertext;
          row['iv'] = encrypted.iv;
          row['encryption_version'] = 2;
        }
      }

      final savedFieldIds = rows
          .map((r) => r['field_id'] as String?)
          .whereType<String>()
          .toSet();

      // Fields that are now empty are marked as cleared so cross-form
      // fallback won't repopulate values the user intentionally removed.
      final clearedFieldIds = eligibleFieldIds
          .where((id) => !savedFieldIds.contains(id))
          .toList();

      final clearedRows = clearedFieldIds
          .map(
            (id) => <String, dynamic>{
              'user_id': userId,
              'field_id': id,
              'field_value': _clearedSentinel,
              'iv': null,
              'encryption_version': 0,
            },
          )
          .toList();

      final allRows = [...rows, ...clearedRows];
      if (allRows.isEmpty) return true;

      // Delete first, then insert fresh rows. This avoids relying on upsert
      // conflict constraints for correctness.
      for (var i = 0; i < eligibleFieldIds.length; i += 50) {
        final chunk = eligibleFieldIds.sublist(
          i,
          (i + 50).clamp(0, eligibleFieldIds.length),
        );
        await _supabase
            .from('user_field_values')
            .delete()
            .eq('user_id', userId)
            .inFilter('field_id', chunk);
      }

      for (var i = 0; i < allRows.length; i += 50) {
        final chunk = allRows.sublist(i, (i + 50).clamp(0, allRows.length));
        await _supabase.from('user_field_values').insert(chunk);
      }
      return true;
    } catch (e) {
      debugPrint('[FieldValueService/saveUserFieldValues] Error: $e');
      return false;
    }
  }


  // Load saved values and map field_id back to field_name.
  Future<Map<String, dynamic>> loadUserFieldValues({
    required String userId,
    required FormTemplate template,
  }) async {
    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) return {};

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, iv, encryption_version')
          .eq('user_id', userId)
          .inFilter('field_id', eligible.map((f) => f.fieldId).toList())
          .order('updated_at', ascending: false);

      final keys = await HybridCryptoService.fetchUserFieldKeys(userId);

      // If duplicates still exist before DB migration runs, keep the newest row
      // per field_id for deterministic reads.
      final seenFieldIds = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final fid = row['field_id'] as String?;
        if (fid != null && seenFieldIds.add(fid)) {
          deduped.add(row);
        }
      }

      // Build reverse maps from field IDs to names and types.
      final idToName = {for (final f in eligible) f.fieldId: f.fieldName};
      final idToType = {for (final f in eligible) f.fieldId: f.fieldType};
      final result = <String, dynamic>{};
      final encryptedRows = <Map<String, dynamic>>[];
      final encryptedItems = <({String ciphertext, String iv})>[];

      void applyResolvedValue(String fid, String resolvedValue) {
        if (resolvedValue.isEmpty || resolvedValue == _clearedSentinel) {
          return;
        }

        final name = idToName[fid];
        if (name == null) return;

        if (idToType[fid] == FormFieldType.memberTable) {
          try {
            result[name] = (jsonDecode(resolvedValue) as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (_) {
            result[name] = <Map<String, dynamic>>[];
          }
          return;
        }

        result[name] = resolvedValue;
      }

      for (final row in deduped) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null || fval == null || fval.isEmpty) {
          continue;
        }

        final rawVersion = row['encryption_version'];
        final version = rawVersion is int
            ? rawVersion
            : int.tryParse(rawVersion?.toString() ?? '') ?? 0;
        if (version == 2) {
          encryptedRows.add(row);
          encryptedItems.add((
            ciphertext: fval,
            iv: row['iv'] as String? ?? '',
          ));
          continue;
        } else if (version == 0) {
          applyResolvedValue(fid, fval);
        } else {
          continue; // Unsupported encryption versions are skipped safely
        }
      }

      if (encryptedItems.isNotEmpty) {
        final decrypted = await HybridCryptoService.decryptFieldBatch(
          encryptedItems,
          keys,
        );
        for (var i = 0; i < decrypted.length; i++) {
          final row = encryptedRows[i];
          final fid = row['field_id'] as String?;
          final fval = row['field_value'] as String? ?? '';
          final decryptedValue = i < decrypted.length ? decrypted[i] : '';
          if (fid != null) {
            if (decryptedValue.isEmpty && fval.trim().isNotEmpty) {
              debugPrint('[FieldValueService/loadUserFieldValues] Warning: v2 decryption failed for field_id=$fid');
            }
            applyResolvedValue(fid, decryptedValue);
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('[FieldValueService/loadUserFieldValues] Error: $e');
      return {};
    }
  }

  /// Loads saved field values for a template, then fills any missing fields
  /// by matching canonical_field_key across all templates.
  ///
  /// Now also serves canonical keys created dynamically via the Web Form
  /// Builder registry (canonical_key_registry table). No logic change was
  /// required because matching is already generic string-normalization over
  /// whatever canonical_field_key contains — see _normalizeCanonicalKey,
  /// _semanticFieldKey, _candidateLookupKeys.
  Future<Map<String, dynamic>> loadUserFieldValuesWithCrossFormFill({
    required String userId,
    required FormTemplate template,
  }) async {
    final direct = await loadUserFieldValues(
      userId: userId,
      template: template,
    );

    try {
      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) {
        return await _applySignatureFallbackIfMissing(
          userId: userId,
          values: direct,
        );
      }

      final missingByCanonical = <String, List<FormFieldModel>>{};
      var protectedCount = 0;
      final directRows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value')
          .eq('user_id', userId)
          .inFilter('field_id', eligible.map((f) => f.fieldId).toList());
      final clearedFieldIds = directRows
          .where((r) => (r['field_value'] as String?) == _clearedSentinel)
          .map((r) => r['field_id'] as String?)
          .whereType<String>()
          .toSet();

      // Build a fieldId->canonical map from DB to supplement in-memory model.
      final fieldIdToCanonical = <String, String>{};
      try {
        final eligibleFieldRows = await _supabase
            .from('form_fields')
            .select('field_id, canonical_field_key')
            .inFilter('field_id', eligible.map((f) => f.fieldId).toList());
        for (final row in eligibleFieldRows) {
          final fid = row['field_id'] as String?;
          final canonical = _normalizeCanonicalKey(row['canonical_field_key'] as String?);
          if (fid != null && canonical != null && canonical.isNotEmpty) {
            fieldIdToCanonical[fid] = canonical;
          }
        }
      } catch (_) {}

      debugPrint('[FieldValueService/FILL] Eligible fields: ${eligible.map((f) => "${f.fieldName}=${f.fieldType}=${f.canonicalFieldKey}").join(" | ")}');
      debugPrint('[FieldValueService/FILL] Cleared field IDs (will skip for non-table): ${clearedFieldIds.length}');
      debugPrint('[FieldValueService/FILL] Direct keys in result: ${direct.keys.join(",")}');

      for (final field in eligible) {
        if (field.fieldType != FormFieldType.memberTable &&
            clearedFieldIds.contains(field.fieldId)) {
          debugPrint('[FieldValueService/FILL] SKIP cleared non-table field=${field.fieldName}');
          continue;
        }
        final current = direct[field.fieldName];
        final hasValue = current != null &&
            (current is List
                ? current.isNotEmpty
                : current.toString().trim().isNotEmpty);
        // Prefer the canonical from DB (which may be set even if in-memory model is stale).
        final canonical = fieldIdToCanonical[field.fieldId] ?? _semanticFieldKey(field);
        debugPrint('[FieldValueService/FILL] field="${field.fieldName}" type=${field.fieldType} dbCanonical=${fieldIdToCanonical[field.fieldId] ?? "(missing)"} semanticCanonical="${_semanticFieldKey(field)}" resolved="$canonical" hasValue=$hasValue currentType=${current.runtimeType} current=$current');
        // Always cross-fill member_table fields so they stay in sync with the source.
        if (hasValue && field.fieldType != FormFieldType.memberTable) {
          protectedCount++;
          continue;
        }
        if (canonical == null || canonical.isEmpty) {
          debugPrint('[FieldValueService/FILL] SKIP no canonical for field=${field.fieldName}');
          continue;
        }
        missingByCanonical
            .putIfAbsent(canonical, () => <FormFieldModel>[])
            .add(field);
      }

      debugPrint('[FieldValueService/FILL] Protected count: $protectedCount');
      debugPrint('[FieldValueService/FILL] MissingByCanonical keys: ${missingByCanonical.keys.join(",")}');
      if (missingByCanonical.isNotEmpty) {
        for (final k in missingByCanonical.keys) {
          debugPrint('[FieldValueService/FILL]   Missing="$k" targets=${missingByCanonical[k]!.map((f) => f.fieldName).join(",")}');
        }
      }

      if (missingByCanonical.isEmpty) {
        return await _applySignatureFallbackIfMissing(
          userId: userId,
          values: direct,
        );
      }

      final valueRows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, iv, encryption_version, updated_at')
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final allFieldIds = valueRows
          .map((row) => row['field_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      debugPrint('[FieldValueService/FILL] ALL user_field_values rows=${valueRows.length} distinctFieldIds=${allFieldIds.length}');
      if (allFieldIds.isEmpty) {
        return await _applySignatureFallbackIfMissing(
          userId: userId,
          values: direct,
        );
      }

      final idToCanonical = <String, String>{};
      try {
        final fieldRows = await _supabase
            .from('form_fields')
            .select(
              'field_id, canonical_field_key, field_name, field_label',
            )
            .inFilter('field_id', allFieldIds);

        debugPrint('[FieldValueService/FILL] form_fields rows fetched: ${fieldRows.length}');
        for (final row in fieldRows) {
          final fid = row['field_id'] as String?;
          final rawCanonical = row['canonical_field_key'] as String?;
          final fieldName = row['field_name'] as String?;
          final fieldLabel = row['field_label'] as String?;
          final canonical =
              _normalizeCanonicalKey(rawCanonical) ??
              _keyFromTextPreferAlias(fieldName) ??
              _keyFromTextPreferAlias(fieldLabel);
          debugPrint('[FieldValueService/FILL]   field_id=$fid rawCanonical="$rawCanonical" fieldName=$fieldName → canonical="$canonical"');
          if (fid == null || canonical == null || canonical.isEmpty) continue;
          idToCanonical[fid] = canonical;
        }
      } catch (e) {
        debugPrint('[FieldValueService/loadUserFieldValuesWithCrossFormFill] Error loading form_fields: $e');
      }

      debugPrint('[FieldValueService/FILL] idToCanonical count: ${idToCanonical.length} keys: ${idToCanonical.values.join(",")}');
      if (idToCanonical.isEmpty) {
        return await _applySignatureFallbackIfMissing(
          userId: userId,
          values: direct,
        );
      }

      final keys = await HybridCryptoService.fetchUserFieldKeys(userId);

      final canonicalBestValue = <String, String>{};

      // Separate encrypted rows from plaintext rows for batch decryption
      final crossFillEncryptedRows = <Map<String, dynamic>>[];
      final crossFillItems = <({String ciphertext, String iv})>[];
      final crossFillCanonicals = <String>[];

      for (final row in valueRows) {
        final fid = row['field_id'] as String?;
        final fval = row['field_value'] as String?;
        if (fid == null ||
            fval == null ||
            fval.trim().isEmpty ||
            fval == _clearedSentinel) {
          if (fval == _clearedSentinel) {
            debugPrint('[FieldValueService/FILL]   skip sentinel row field_id=$fid');
          }
          continue;
        }

        final canonical = idToCanonical[fid];
        if (canonical == null) {
          debugPrint('[FieldValueService/FILL]   skip row field_id=$fid no canonical mapping');
          continue;
        }

        // Skip if we already have a value for this canonical key
        if (canonicalBestValue.containsKey(canonical)) {
          debugPrint('[FieldValueService/FILL]   skip row field_id=$fid canonical=$canonical already have value');
          continue;
        }

        final rawVersion = row['encryption_version'];
        final version = rawVersion is int
            ? rawVersion
            : int.tryParse(rawVersion?.toString() ?? '') ?? 0;

        debugPrint('[FieldValueService/FILL]   candidate row field_id=$fid canonical=$canonical version=$version fval_len=${fval.length}');
        if (version == 2) {
          final iv = row['iv'] as String? ?? '';
          if (iv.isEmpty) continue;
          crossFillEncryptedRows.add(row);
          crossFillItems.add((ciphertext: fval, iv: iv));
          crossFillCanonicals.add(canonical);
        } else if (version == 0) {
          canonicalBestValue[canonical] = fval;
        } else {
          continue;
        }
      }

      // Batch decrypt all encrypted cross-fill values
      if (crossFillItems.isNotEmpty) {
        try {
          final decrypted = await HybridCryptoService.decryptFieldBatch(
            crossFillItems,
            keys,
          );
          for (var i = 0; i < crossFillCanonicals.length; i++) {
            final value = i < decrypted.length ? decrypted[i] : '';
            debugPrint('[FieldValueService/FILL]   decrypted canonical=${crossFillCanonicals[i]} value_len=${value.length} value_prefix=${value.length > 20 ? value.substring(0,20) : value}');
            if (value.isNotEmpty && value != _clearedSentinel) {
              canonicalBestValue[crossFillCanonicals[i]] = value;
            }
          }
        } catch (e) {
          debugPrint('[FieldValueService/loadUserFieldValuesWithCrossFormFill] Error decrypting batch: $e');
        }
      }
      debugPrint('[FieldValueService/FILL] Canonical best values count: ${canonicalBestValue.length} keys: ${canonicalBestValue.keys.join(",")}');

      final unmatchedKeys =
          missingByCanonical.keys
              .where(
                (k) => !_candidateLookupKeys(
                  k,
                ).any(canonicalBestValue.containsKey),
              )
              .toList()
            ..sort();
      if (unmatchedKeys.isNotEmpty) {
        final missingPreview = unmatchedKeys.take(12).join(', ');
        final availablePreview = canonicalBestValue.keys.take(20).join(', ');
        debugPrint('[FieldValueService/FILL] UNMATCHED keys: [$missingPreview] available: [$availablePreview]');
      } else {
        debugPrint('[FieldValueService/FILL] ALL missing keys have matches in canonicalBestValue');
      }

      final merged = <String, dynamic>{...direct};
      var filledCount = 0;
      for (final entry in missingByCanonical.entries) {
        String? bestValue;
        for (final k in _candidateLookupKeys(entry.key)) {
          final v = canonicalBestValue[k];
          if (v != null && v.trim().isNotEmpty) {
            bestValue = v;
            break;
          }
        }
        if (bestValue == null || bestValue.trim().isEmpty) {
          debugPrint('[FieldValueService/FILL] No bestValue for canonical=${entry.key}');
          continue;
        }

        for (final field in entry.value) {
          final current = merged[field.fieldName];
          var isEmpty = false;
          if (current == null) {
            isEmpty = true;
          } else if (current is List) {
            isEmpty = current.isEmpty;
          } else {
            isEmpty = current.toString().trim().isEmpty;
          }
          debugPrint('[FieldValueService/FILL]   Apply field=${field.fieldName} type=${field.fieldType} currentIsEmpty=$isEmpty bestValue_prefix=${bestValue.length > 30 ? bestValue.substring(0,30) : bestValue}');
          
          // Always overwrite member_table fields so they stay in sync with source.
          if (field.fieldType == FormFieldType.memberTable || isEmpty) {
            if (field.fieldType == FormFieldType.memberTable) {
              try {
                final decodedSourceRows = jsonDecode(bestValue) as List;
                debugPrint('[FieldValueService/FILL]   decoded ${decodedSourceRows.length} source rows, dest has ${field.columns.length} columns');
                merged[field.fieldName] = mergeTablePayloads(
                  sourceRows: decodedSourceRows,
                  destinationColumns: field.columns,
                );
                debugPrint('[FieldValueService/FILL]   merged result has ${(merged[field.fieldName] as List).length} rows');
              } catch (e) {
                debugPrint('[FieldValueService/FILL]   FAILED to merge: $e');
                merged[field.fieldName] = <Map<String, dynamic>>[];
              }
            } else {
              merged[field.fieldName] = bestValue;
            }
            filledCount++;
          }
        }
      }
      debugPrint('[FieldValueService/FILL] Cross-filled count: $filledCount');

      final withSignature = await _applySignatureFallbackIfMissing(
        userId: userId,
        values: merged,
      );

      if (filledCount == 0 && missingByCanonical.isNotEmpty) {
        debugPrint('[FieldValueService/FILL] TRYING LEGACY FALLBACK PATH');
        try {
          final legacy = await loadUserFieldValuesWithCanonicalFallback(
            userId: userId,
            template: template,
          );
          if (legacy.length > withSignature.length) return legacy;
        } catch (e) {
          debugPrint('[FieldValueService/loadUserFieldValuesWithCrossFormFill] Error in legacy fallback: $e');
        }
      }

      return withSignature;
    } catch (e) {
      debugPrint('[FieldValueService/loadUserFieldValuesWithCrossFormFill] Error: $e');
      return await _applySignatureFallbackIfMissing(
        userId: userId,
        values: direct,
      );
    }
  }

  Future<Map<String, dynamic>> _applySignatureFallbackIfMissing({
    required String userId,
    required Map<String, dynamic> values,
  }) async {
    final merged = <String, dynamic>{...values};
    final hasSignature =
        merged['__signature'] != null &&
        merged['__signature'].toString().trim().isNotEmpty;
    if (hasSignature) {
      return merged;
    }

    try {
      final signatureRow = await _supabase
          .from('user_field_values')
          .select(
            'field_value, iv, encryption_version, updated_at, form_fields!inner(canonical_field_key)',
          )
          .eq('user_id', userId)
          .eq('form_fields.canonical_field_key', 'signature')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (signatureRow == null) {
        return merged;
      }

      var signatureValue = signatureRow['field_value']?.toString().trim() ?? '';
      final rawVersion = signatureRow['encryption_version'];
      final version = rawVersion is int
          ? rawVersion
          : int.tryParse(rawVersion?.toString() ?? '') ?? 0;

      if (version == 2 && signatureValue.isNotEmpty) {
        final iv = signatureRow['iv']?.toString() ?? '';
        if (iv.isNotEmpty) {
          final keys = await HybridCryptoService.fetchUserFieldKeys(userId);
          signatureValue = await HybridCryptoService.decryptField(
            signatureValue,
            iv,
            keys,
          );
        } else {
          signatureValue = '';
        }
      } else if (version != 0) {
        // Unsupported encryption version — skip rather than return ciphertext
        signatureValue = '';
      }

      if (signatureValue.isNotEmpty && signatureValue != _clearedSentinel) {
        merged['__signature'] = signatureValue;
      }
    } catch (e) {
      debugPrint('[FieldValueService/_applySignatureFallbackIfMissing] Error: $e');
    }

    return merged;
  }

  // Load direct values and fill missing fields from canonical matches.
  Future<Map<String, dynamic>> loadUserFieldValuesWithCanonicalFallback({
    required String userId,
    required FormTemplate template,
  }) async {
    try {
      // Pass 1: direct field_id loading for the selected template.
      final direct = await loadUserFieldValues(
        userId: userId,
        template: template,
      );

      final eligible = template.allFields
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();
      if (eligible.isEmpty) return direct;

      final missingByCanonical = <String, List<FormFieldModel>>{};
      for (final field in eligible) {
        final current = direct[field.fieldName];
        final hasValue = current != null &&
            (current is List
                ? current.isNotEmpty
                : current.toString().trim().isNotEmpty);
        final canonical = _normalizeCanonicalKey(field.canonicalFieldKey);
        if (hasValue || canonical == null || canonical.isEmpty) continue;
        missingByCanonical
            .putIfAbsent(canonical, () => <FormFieldModel>[])
            .add(field);
      }

      if (missingByCanonical.isEmpty) return direct;

      final templates = await FormTemplateService().fetchActiveTemplates();
      final allFields = templates
          .expand((t) => t.allFields)
          .where((f) => !_skipTypes.contains(f.fieldType))
          .where((f) => f.parentFieldId == null)
          .toList();

      final canonicalNeeded = missingByCanonical.keys.toSet();
      final idToCanonical = <String, String>{};
      final candidateFieldIds = <String>[];
      for (final field in allFields) {
        final canonical = _normalizeCanonicalKey(field.canonicalFieldKey);
        if (canonical == null || canonical.isEmpty) continue;
        if (!canonicalNeeded.contains(canonical)) continue;
        idToCanonical[field.fieldId] = canonical;
        candidateFieldIds.add(field.fieldId);
      }

      if (candidateFieldIds.isEmpty) return direct;

      final rows = await _supabase
          .from('user_field_values')
          .select('field_id, field_value, updated_at')
          .eq('user_id', userId)
          .inFilter('field_id', candidateFieldIds)
          .order('updated_at', ascending: false);

      final canonicalResolved = <String>{};
      final merged = <String, dynamic>{...direct};
      for (final row in rows) {
        final fid = row['field_id'] as String?;
        final value = row['field_value'] as String?;
        if (fid == null || value == null || value.trim().isEmpty) {
          continue;
        }

        final canonical = idToCanonical[fid];
        if (canonical == null || canonicalResolved.contains(canonical)) {
          continue;
        }

        final targets = missingByCanonical[canonical];
        if (targets == null || targets.isEmpty) continue;

        for (final target in targets) {
          final current = merged[target.fieldName];
          final isEmpty = current == null
              ? true
              : (current is List ? current.isEmpty : current.toString().trim().isEmpty);
          if (!isEmpty) continue;

          if (target.fieldType == FormFieldType.memberTable) {
            try {
              final decodedSourceRows = jsonDecode(value) as List;
              merged[target.fieldName] = mergeTablePayloads(
                sourceRows: decodedSourceRows,
                destinationColumns: target.columns,
              );
            } catch (_) {
              merged[target.fieldName] = <Map<String, dynamic>>[];
            }
          } else {
            merged[target.fieldName] = value;
          }
        }
        canonicalResolved.add(canonical);
      }

      return merged;
    } catch (e) {
      debugPrint('[FieldValueService/loadUserFieldValuesWithCanonicalFallback] Error: $e');
      return await loadUserFieldValues(userId: userId, template: template);
    }
  }

  // Shared helpers for the save and load flows.

  /// Iterate template fields, skip non-saveable types, build row maps.
  List<Map<String, dynamic>> _buildFieldRows(
    FormTemplate template,
    Map<String, dynamic> formData,
    Map<String, dynamic> Function(FormFieldModel field, String value)
    rowBuilder,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final field in template.allFields) {
      if (_skipTypes.contains(field.fieldType)) {
        continue;
      }
      if (field.parentFieldId != null) {
        continue; // skip child column-definitions
      }

      if (field.fieldType == FormFieldType.signature) {
        final sigVal =
            (formData[field.fieldName] ?? formData['__signature'])
                ?.toString() ??
            '';
        if (sigVal.trim().isEmpty) continue;
        rows.add(rowBuilder(field, sigVal));
        continue;
      }

      if (field.fieldType == FormFieldType.memberTable) {
        final val = formData[field.fieldName];
        if (val == null) continue;
        final jsonStr = jsonEncode(val);
        if (jsonStr == '[]' || jsonStr.isEmpty) continue;
        rows.add(rowBuilder(field, jsonStr));
        continue;
      }

      final val = formData[field.fieldName]?.toString().trim() ?? '';
      if (val.isEmpty) continue;
      rows.add(rowBuilder(field, val));
    }
    return rows;
  }

  static String? _normalizeCanonicalKey(String? raw) {
    if (raw == null) return null;
    final lowered = raw.trim().toLowerCase();
    if (lowered.isEmpty) return null;
    final normalized = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  /// Merges source member_table rows into the destination column schema using
  /// tiered matching (canonical key, semantic alias, exact name), dropping
  /// unmapped columns and empty rows.
  @visibleForTesting
  static List<Map<String, dynamic>> mergeTablePayloads({
    required List<dynamic> sourceRows,
    required List<FormFieldModel> destinationColumns,
    Map<String, String>? sourceColumnCanonicalKeys,
  }) {
    if (destinationColumns.isEmpty) return const [];

    final destByCanonical = <String, String>{};
    for (final col in destinationColumns) {
      final key = _normalizeCanonicalKey(col.canonicalFieldKey);
      if (key != null && key.isNotEmpty) {
        destByCanonical.putIfAbsent(key, () => col.fieldName);
      }
    }

    final destByAlias = <String, String>{};
    for (final col in destinationColumns) {
      final alias = _keyFromTextPreferAlias(col.fieldName);
      if (alias != null && alias.isNotEmpty) {
        destByAlias.putIfAbsent(alias, () => col.fieldName);
      }
    }

    final destFieldNames = destinationColumns.map((c) => c.fieldName).toSet();
    final mergedRows = <Map<String, dynamic>>[];

    for (final rawRow in sourceRows) {
      if (rawRow is! Map) continue;
      final sourceRow = Map<String, dynamic>.from(rawRow);
      final mappedRow = <String, dynamic>{};

      for (final sourceEntry in sourceRow.entries) {
        final sourceKey = sourceEntry.key;
        final value = sourceEntry.value;

        final sourceCanonical =
            _normalizeCanonicalKey(sourceColumnCanonicalKeys?[sourceKey]);
        if (sourceCanonical != null &&
            destByCanonical.containsKey(sourceCanonical)) {
          mappedRow[destByCanonical[sourceCanonical]!] = value;
          continue;
        }

        final sourceAlias = _keyFromTextPreferAlias(sourceKey);
        if (sourceAlias != null && destByAlias.containsKey(sourceAlias)) {
          mappedRow[destByAlias[sourceAlias]!] = value;
          continue;
        }

        if (destFieldNames.contains(sourceKey)) {
          mappedRow[sourceKey] = value;
          continue;
        }
      }

      if (mappedRow.isNotEmpty) {
        mergedRows.add(mappedRow);
      }
    }

    return mergedRows;
  }

  String? _semanticFieldKey(FormFieldModel field) {
    final canonical = _keyFromTextPreferAlias(field.canonicalFieldKey);
    if (canonical != null) return canonical;

    final aliasFromName = _keyFromTextPreferAlias(field.fieldName);
    if (aliasFromName != null) return aliasFromName;

    final aliasFromLabel = _keyFromTextPreferAlias(field.fieldLabel);
    if (aliasFromLabel != null) return aliasFromLabel;

    return _normalizeCanonicalKey(field.fieldName);
  }


  static String? _keyFromTextPreferAlias(String? raw) {
    final alias = _semanticAliasFromText(raw);
    if (alias != null) return alias;
    return _normalizeCanonicalKey(raw);
  }

  static String? _semanticAliasFromText(String? raw) {
    final t = _normalizeCanonicalKey(raw);
    if (t == null) return null;

    // Name variants (English + Filipino labels/keys)
    if (t == 'lastname' ||
        t == 'last_name' ||
        t == 'surname' ||
        t == 'family_name' ||
        t.contains('apelyido') ||
        (t.contains('last') && t.contains('name'))) {
      return 'last_name';
    }

    if (t == 'firstname' ||
        t == 'first_name' ||
        t == 'given_name' ||
        t == 'given_names' ||
        t.contains('pangalan') ||
        (t.contains('first') && t.contains('name'))) {
      return 'first_name';
    }

    if (t == 'middlename' ||
        t == 'middle_name' ||
        t.contains('gitnang') ||
        (t.contains('middle') && t.contains('name'))) {
      return 'middle_name';
    }

    // Birthdate variants
    if (t == 'birthdate' ||
        t == 'date_of_birth' ||
        t.contains('kapanganakan') ||
        (t.contains('birth') && (t.contains('date') || t.contains('day')))) {
      return 'birth_date';
    }

    // Civil/marital status variants
    if (t == 'civil_status' ||
        t == 'marital_status' ||
        t == 'estadong_sibil_civil_status' ||
        t.contains('sibil') ||
        (t.contains('civil') && t.contains('status')) ||
        (t.contains('marital') && t.contains('status'))) {
      return 'civil_status';
    }

    // Sex/gender variants
    if (t == 'sex' ||
        t == 'gender' ||
        t == 'kasarian_sex' ||
        t.contains('kasarian') ||
        t.contains('gender')) {
      return 'gender';
    }

    // Contact variants
    if (t == 'cp_number' ||
        t == 'contact_no' ||
        t == 'contact_number' ||
        t == 'mobile_no' ||
        t == 'cellphone_number' ||
        t.contains('phone') ||
        t.contains('mobile') ||
        t.contains('contact')) {
      return 'phone';
    }

    // Email variants
    if (t == 'email_address' || t.contains('email') || t.contains('e_mail')) {
      return 'email';
    }

    // Place of birth variants
    if (t == 'lugar_ng_kapanganakan_place_of_birth' ||
        t == 'place_of_birth' ||
        t == 'birth_place' ||
        (t.contains('birth') && t.contains('place'))) {
      return 'birthplace';
    }

    // Address component variants used in profile + GIS forms
    if (t == 'house_number_street_name_phase_purok' ||
        t == 'house_no_street' ||
        t == 'address_line' ||
        t.contains('street')) {
      return 'address_line';
    }

    if (t == 'subdivison_' || t == 'subdivision' || t.contains('subdivision')) {
      return 'subdivision';
    }

    if (t.contains('barangay')) return 'barangay';
    if (t.contains('purok') || t.contains('sitio')) return 'purok_sitio';

    return null;
  }

  List<String> _candidateLookupKeys(String key) {
    final normalized = _normalizeCanonicalKey(key);
    if (normalized == null || normalized.isEmpty) return const [];

    final set = <String>{normalized};
    switch (normalized) {
      case 'civil_status':
        set.add('estadong_sibil_civil_status');
        break;
      case 'gender':
        set.add('kasarian_sex');
        break;
      case 'phone':
        set.add('cp_number');
        break;
      case 'email':
        set.add('email_address');
        break;
      case 'birth_date':
        set.add('date_of_birth');
        break;
      case 'birthplace':
        set.add('lugar_ng_kapanganakan_place_of_birth');
        break;
      case 'address_line':
        set.add('house_number_street_name_phase_purok');
        break;
      case 'subdivision':
        set.add('subdivison_');
        break;
    }
    return set.toList(growable: false);
  }
}