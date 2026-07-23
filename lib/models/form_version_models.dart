/// Models for form template versioning and submission migration.
///
/// A [FormTemplateSnapshot] is the frozen structure of a template at one
/// version, stored in `form_template_versions.snapshot`. Comparing a snapshot
/// against the live [FormTemplate] produces a [SubmissionMigration], which
/// tells the viewer what changed and which saved values no longer have a home.
library;

/// One field as it existed at a given template version.
class SnapshotField {
  final String fieldId;
  final String? sectionId;
  final String fieldName;
  final String fieldLabel;
  final String fieldType;
  final int fieldOrder;
  final String? parentFieldId;
  final bool isRequired;

  const SnapshotField({
    required this.fieldId,
    this.sectionId,
    required this.fieldName,
    required this.fieldLabel,
    required this.fieldType,
    this.fieldOrder = 0,
    this.parentFieldId,
    this.isRequired = false,
  });

  factory SnapshotField.fromMap(Map<String, dynamic> m) => SnapshotField(
    fieldId: m['field_id']?.toString() ?? '',
    sectionId: m['section_id']?.toString(),
    fieldName: m['field_name']?.toString() ?? '',
    fieldLabel: m['field_label']?.toString() ?? '',
    fieldType: m['field_type']?.toString() ?? 'text',
    fieldOrder: (m['field_order'] as num?)?.toInt() ?? 0,
    parentFieldId: m['parent_field_id']?.toString(),
    isRequired: m['is_required'] == true,
  );

  Map<String, dynamic> toMap() => {
    'field_id': fieldId,
    'section_id': sectionId,
    'field_name': fieldName,
    'field_label': fieldLabel,
    'field_type': fieldType,
    'field_order': fieldOrder,
    'parent_field_id': parentFieldId,
    'is_required': isRequired,
  };
}

/// One section as it existed at a given template version.
class SnapshotSection {
  final String sectionId;
  final String sectionName;
  final int sectionOrder;

  const SnapshotSection({
    required this.sectionId,
    required this.sectionName,
    this.sectionOrder = 0,
  });

  factory SnapshotSection.fromMap(Map<String, dynamic> m) => SnapshotSection(
    sectionId: m['section_id']?.toString() ?? '',
    sectionName: m['section_name']?.toString() ?? '',
    sectionOrder: (m['section_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'section_id': sectionId,
    'section_name': sectionName,
    'section_order': sectionOrder,
  };
}

/// The full structure of a template at one version.
class FormTemplateSnapshot {
  final String templateId;
  final String formName;
  final int version;
  final DateTime? capturedAt;
  final List<SnapshotSection> sections;
  final List<SnapshotField> fields;

  const FormTemplateSnapshot({
    required this.templateId,
    required this.formName,
    required this.version,
    this.capturedAt,
    this.sections = const [],
    this.fields = const [],
  });

  factory FormTemplateSnapshot.fromMap(Map<String, dynamic> m) =>
      FormTemplateSnapshot(
        templateId: m['template_id']?.toString() ?? '',
        formName: m['form_name']?.toString() ?? '',
        version: (m['version'] as num?)?.toInt() ?? 1,
        capturedAt: DateTime.tryParse(m['captured_at']?.toString() ?? ''),
        sections: (m['sections'] as List<dynamic>? ?? [])
            .map((s) => SnapshotSection.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
        fields: (m['fields'] as List<dynamic>? ?? [])
            .map((f) => SnapshotField.fromMap(Map<String, dynamic>.from(f as Map)))
            .toList(),
      );

  /// Field lookup by the stable `field_id`, which survives renames.
  Map<String, SnapshotField> get fieldsById => {
    for (final f in fields) f.fieldId: f,
  };

  /// Field lookup by the data key used in submission payloads.
  Map<String, SnapshotField> get fieldsByName => {
    for (final f in fields) f.fieldName: f,
  };
}

/// A field whose `field_id` survived an edit but whose data key changed.
class RenamedField {
  final String fieldId;
  final String oldName;
  final String newName;
  final String label;

  const RenamedField({
    required this.fieldId,
    required this.oldName,
    required this.newName,
    required this.label,
  });
}

/// A saved value with no field in the current template to display it.
class ArchivedFieldValue {
  final String key;
  final String label;
  final dynamic value;
  final int? archivedAtVersion;

  const ArchivedFieldValue({
    required this.key,
    required this.label,
    required this.value,
    this.archivedAtVersion,
  });

  factory ArchivedFieldValue.fromMap(String key, Map<String, dynamic> m) =>
      ArchivedFieldValue(
        key: key,
        label: m['label']?.toString() ?? key,
        value: m['value'],
        archivedAtVersion: (m['archived_at_version'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
    'label': label,
    'value': value,
    if (archivedAtVersion != null) 'archived_at_version': archivedAtVersion,
  };

  /// Human-readable rendering of [value] for the read-only archive panel.
  String get displayValue {
    final v = value;
    if (v == null) return '—';
    if (v is List) {
      if (v.isEmpty) return '—';
      if (v.first is Map) return '${v.length} row(s)';
      return v.join(', ');
    }
    if (v is Map) return '${v.length} entry(ies)';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }
}

/// Result of comparing a submission's version against the live template.
class SubmissionMigration {
  /// Version the submission was filled against (NULL in the DB reads as 1).
  final int submissionVersion;

  /// Version of the template as it stands now.
  final int currentVersion;

  /// Payload with renames applied and archived values lifted out — this is
  /// what gets handed to [FormStateController.loadFromJson].
  final Map<String, dynamic> data;

  /// Saved values whose field no longer exists in the current template.
  ///
  /// A subset of [removedFieldLabels] — only the removed fields this
  /// particular record happened to hold a value for.
  final List<ArchivedFieldValue> archived;

  /// Fields deleted from the template since [submissionVersion], whether or
  /// not this record had data in them.
  final List<String> removedFieldLabels;

  /// Fields added since [submissionVersion]; empty in this record's data.
  final List<String> addedFieldLabels;

  /// Fields whose data key changed; their values were carried over.
  final List<RenamedField> renamed;

  /// True when no snapshot existed for [submissionVersion], so renames could
  /// not be distinguished from a removal plus an addition.
  final bool snapshotMissing;

  const SubmissionMigration({
    required this.submissionVersion,
    required this.currentVersion,
    required this.data,
    this.archived = const [],
    this.removedFieldLabels = const [],
    this.addedFieldLabels = const [],
    this.renamed = const [],
    this.snapshotMissing = false,
  });

  /// Unchanged passthrough for records already on the current version.
  factory SubmissionMigration.upToDate({
    required int version,
    required Map<String, dynamic> data,
  }) => SubmissionMigration(
    submissionVersion: version,
    currentVersion: version,
    data: data,
  );

  bool get isStale => currentVersion > submissionVersion;

  /// True when there is something worth telling the staff member about.
  bool get hasChanges =>
      archived.isNotEmpty ||
      removedFieldLabels.isNotEmpty ||
      addedFieldLabels.isNotEmpty ||
      renamed.isNotEmpty;

  /// One-line summary for the banner.
  String get summary {
    final parts = <String>[];
    // Structural removals are the headline; fall back to the archived count
    // when there is no snapshot to compare structures against.
    final removedCount = removedFieldLabels.isNotEmpty
        ? removedFieldLabels.length
        : archived.length;
    if (removedCount > 0) {
      parts.add('$removedCount field${removedCount == 1 ? '' : 's'} removed');
    }
    if (addedFieldLabels.isNotEmpty) {
      parts.add(
        '${addedFieldLabels.length} field'
        '${addedFieldLabels.length == 1 ? '' : 's'} added',
      );
    }
    if (renamed.isNotEmpty) {
      parts.add(
        '${renamed.length} field${renamed.length == 1 ? '' : 's'} renamed',
      );
    }
    if (parts.isEmpty) return 'No field changes affect this record.';

    final summary = parts.join(', ');
    if (archived.isNotEmpty) {
      return '$summary. ${archived.length} held saved data on this record, '
          'preserved below.';
    }
    if (removedFieldLabels.isNotEmpty) {
      return '$summary. This record held no data in the removed '
          'field${removedFieldLabels.length == 1 ? '' : 's'}.';
    }
    return summary;
  }
}
