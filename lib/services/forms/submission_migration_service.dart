/// Reconciles a saved submission against the current form template.
///
/// A submission's payload is keyed by `field_name`. When a superadmin edits a
/// live template, those keys can stop matching: a field is removed, or renamed
/// so its key changes. `FormStateController.loadFromJson` drops anything it
/// cannot match, so without this pass the values simply vanish from the view.
///
/// The work is lazy — nothing is scanned or rewritten in bulk. [migrate] runs
/// once, on the record a staff member actually opened, and returns a
/// [SubmissionMigration] describing what moved. It performs no writes.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/form_template_models.dart';
import '../../models/form_version_models.dart';

class SubmissionMigrationService {
  static final SubmissionMigrationService _instance =
      SubmissionMigrationService._internal();
  factory SubmissionMigrationService() => _instance;
  SubmissionMigrationService._internal();

  // Resolved on use, not at construction, so the pure diff below can be
  // exercised in tests without an initialized Supabase client.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Reserved payload key holding values whose field is gone from the template.
  static const String archivedKey = '__archived__';

  /// Payload keys owned by the system rather than by a template field. These
  /// never participate in the diff.
  ///
  /// The `__` prefix is the convention for everything the app writes into the
  /// payload itself — controller state (`__membership`, `__family_composition`)
  /// and record metadata (`__session_id`, `__applicant_name`). None of them
  /// were ever template fields, so none can be "removed" from one. The same
  /// convention is applied in `ApplicantsScreen`'s raw-JSON fallback view and
  /// in the Edge Function's `canonical_hash.ts`.
  static bool _isReserved(String key) =>
      key.startsWith('__') || key == 'signature';

  // Snapshots are immutable once written, so caching them is always safe.
  final Map<String, FormTemplateSnapshot?> _snapshotCache = {};

  /// Compare [data] against [template] and report what changed since the
  /// version the record was filled against.
  ///
  /// [submissionVersion] is `client_submissions.template_version`; NULL there
  /// means the record predates versioning and is read as version 1.
  Future<SubmissionMigration> migrate({
    required FormTemplate template,
    required Map<String, dynamic> data,
    int? submissionVersion,
  }) async {
    final fromVersion = submissionVersion ?? 1;
    final currentVersion = template.version;

    if (fromVersion >= currentVersion) {
      return SubmissionMigration.upToDate(
        version: currentVersion,
        data: _withoutArchivedKey(data),
      );
    }

    final snapshot = await _fetchSnapshot(template.templateId, fromVersion);

    return snapshot == null
        ? migrateWithoutSnapshot(
            template: template,
            data: data,
            fromVersion: fromVersion,
            currentVersion: currentVersion,
          )
        : migrateWithSnapshot(
            template: template,
            data: data,
            snapshot: snapshot,
            fromVersion: fromVersion,
            currentVersion: currentVersion,
          );
  }

  // ── Diff with a snapshot: renames are resolvable ────────────────────
  //
  // `field_id` survives a rename, so a field present in both structures under
  // different names is a rename, not a removal plus an addition.
  @visibleForTesting
  SubmissionMigration migrateWithSnapshot({
    required FormTemplate template,
    required Map<String, dynamic> data,
    required FormTemplateSnapshot snapshot,
    required int fromVersion,
    required int currentVersion,
  }) {
    final currentById = {for (final f in template.allFields) f.fieldId: f};
    final oldById = snapshot.fieldsById;
    final oldByName = snapshot.fieldsByName;

    final migrated = _withoutArchivedKey(data);
    final renamed = <RenamedField>[];

    for (final entry in oldById.entries) {
      final current = currentById[entry.key];
      if (current == null) continue;
      final oldName = entry.value.fieldName;
      final newName = current.fieldName;
      if (oldName == newName || oldName.isEmpty || newName.isEmpty) continue;
      if (!migrated.containsKey(oldName)) continue;

      // Never overwrite a value already sitting under the new key.
      if (!migrated.containsKey(newName)) {
        migrated[newName] = migrated[oldName];
      }
      migrated.remove(oldName);
      renamed.add(
        RenamedField(
          fieldId: entry.key,
          oldName: oldName,
          newName: newName,
          label: current.fieldLabel,
        ),
      );
    }

    final archived = _collectArchived(
      template: template,
      data: data,
      migrated: migrated,
      labelFor: (key) => oldByName[key]?.fieldLabel ?? key,
      archivedAtVersion: currentVersion,
    );
    for (final a in archived) {
      migrated.remove(a.key);
    }

    // A field id absent from the snapshot did not exist at that version, so
    // this record could not have carried a value for it.
    final addedFieldLabels = template.allFields
        .where((f) => !oldById.containsKey(f.fieldId))
        .map((f) => f.fieldLabel)
        .toList();

    // Deleted from the template outright. Reported from the structures, not
    // from the payload, so a record that left the field blank still shows that
    // the form it was captured on no longer matches the current one. Child
    // table columns are excluded to match `allFields`, which is top-level only.
    final removedFieldLabels = snapshot.fields
        .where((f) => f.parentFieldId == null && !currentById.containsKey(f.fieldId))
        .map((f) => f.fieldLabel)
        .toList();

    return SubmissionMigration(
      submissionVersion: fromVersion,
      currentVersion: currentVersion,
      data: migrated,
      archived: archived,
      removedFieldLabels: removedFieldLabels,
      addedFieldLabels: addedFieldLabels,
      renamed: renamed,
    );
  }

  // ── Diff without a snapshot: presence comparison only ───────────────
  //
  // Reached when a template was bumped before versioning shipped, or when the
  // snapshot write failed. Removed data is still recovered; a rename is
  // indistinguishable from a removal, and additions are not reported at all
  // because an untouched optional field looks identical to a new one.
  @visibleForTesting
  SubmissionMigration migrateWithoutSnapshot({
    required FormTemplate template,
    required Map<String, dynamic> data,
    required int fromVersion,
    required int currentVersion,
  }) {
    final migrated = _withoutArchivedKey(data);

    final archived = _collectArchived(
      template: template,
      data: data,
      migrated: migrated,
      labelFor: (key) => key,
      archivedAtVersion: currentVersion,
    );
    for (final a in archived) {
      migrated.remove(a.key);
    }

    return SubmissionMigration(
      submissionVersion: fromVersion,
      currentVersion: currentVersion,
      data: migrated,
      archived: archived,
      snapshotMissing: true,
    );
  }

  /// Payload keys with no field in the current template to render them, plus
  /// anything a previous pass already parked under [archivedKey].
  List<ArchivedFieldValue> _collectArchived({
    required FormTemplate template,
    required Map<String, dynamic> data,
    required Map<String, dynamic> migrated,
    required String Function(String key) labelFor,
    required int archivedAtVersion,
  }) {
    // loadFromJson matches on field_name first and falls back to field_label,
    // so a key that matches either one is still displayable.
    final displayable = <String>{
      for (final f in template.allFields) ...[f.fieldName, f.fieldLabel],
    }..removeWhere((k) => k.isEmpty);

    final archived = <ArchivedFieldValue>[];

    for (final entry in migrated.entries) {
      if (_isReserved(entry.key)) continue;
      if (displayable.contains(entry.key)) continue;
      archived.add(
        ArchivedFieldValue(
          key: entry.key,
          label: labelFor(entry.key),
          value: entry.value,
          archivedAtVersion: archivedAtVersion,
        ),
      );
    }

    // Values archived by an earlier migration stay archived unless the field
    // they belong to has since come back into the template.
    final existing = data[archivedKey];
    if (existing is Map) {
      existing.forEach((key, value) {
        final k = key.toString();
        if (displayable.contains(k)) {
          migrated[k] = value is Map ? value['value'] : value;
          return;
        }
        if (archived.any((a) => a.key == k)) return;
        archived.add(
          value is Map
              ? ArchivedFieldValue.fromMap(k, Map<String, dynamic>.from(value))
              : ArchivedFieldValue(key: k, label: k, value: value),
        );
      });
    }

    return archived;
  }

  Map<String, dynamic> _withoutArchivedKey(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    copy.remove(archivedKey);
    return copy;
  }

  /// Fetch the frozen structure of [templateId] at [version], or null when the
  /// version was never snapshotted.
  Future<FormTemplateSnapshot?> _fetchSnapshot(
    String templateId,
    int version,
  ) async {
    final cacheKey = '$templateId#$version';
    if (_snapshotCache.containsKey(cacheKey)) return _snapshotCache[cacheKey];

    try {
      final row = await _supabase
          .from('form_template_versions')
          .select('snapshot')
          .eq('template_id', templateId)
          .eq('version', version)
          .maybeSingle();

      final raw = row?['snapshot'];
      final snapshot = raw is Map
          ? FormTemplateSnapshot.fromMap(Map<String, dynamic>.from(raw))
          : null;
      _snapshotCache[cacheKey] = snapshot;
      return snapshot;
    } catch (e) {
      debugPrint('[SubmissionMigrationService/_fetchSnapshot] Error: $e');
      _snapshotCache[cacheKey] = null;
      return null;
    }
  }

  void clearCache() => _snapshotCache.clear();
}
