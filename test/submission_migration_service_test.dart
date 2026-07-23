import 'package:flutter_test/flutter_test.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/models/form_version_models.dart';
import 'package:sappiire/services/forms/submission_migration_service.dart';

FormFieldModel _field({
  required String id,
  required String name,
  required String label,
  FormFieldType type = FormFieldType.text,
  int order = 0,
}) {
  return FormFieldModel(
    fieldId: id,
    templateId: 'tpl_1',
    sectionId: 'sec_1',
    fieldName: name,
    fieldLabel: label,
    fieldType: type,
    fieldOrder: order,
  );
}

FormTemplate _template(List<FormFieldModel> fields, {int version = 2}) {
  return FormTemplate(
    templateId: 'tpl_1',
    formName: 'Intake',
    status: 'published',
    version: version,
    sections: [
      FormSection(
        sectionId: 'sec_1',
        templateId: 'tpl_1',
        sectionName: 'Main',
        fields: fields,
      ),
    ],
  );
}

SnapshotField _snapField({
  required String id,
  required String name,
  required String label,
  String type = 'text',
}) {
  return SnapshotField(
    fieldId: id,
    sectionId: 'sec_1',
    fieldName: name,
    fieldLabel: label,
    fieldType: type,
  );
}

FormTemplateSnapshot _snapshot(List<SnapshotField> fields, {int version = 1}) {
  return FormTemplateSnapshot(
    templateId: 'tpl_1',
    formName: 'Intake',
    version: version,
    fields: fields,
  );
}

void main() {
  final service = SubmissionMigrationService();

  group('migrateWithSnapshot', () {
    test('carries a renamed field\'s value onto the new data key', () {
      final result = service.migrateWithSnapshot(
        template: _template([
          _field(id: 'f1', name: 'household_income', label: 'Household Income'),
        ]),
        data: {'monthly_income': '12000'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.data['household_income'], '12000');
      expect(result.data.containsKey('monthly_income'), isFalse);
      expect(result.renamed.single.oldName, 'monthly_income');
      expect(result.renamed.single.newName, 'household_income');
      expect(result.archived, isEmpty);
    });

    test('archives a removed field with its label from the snapshot', () {
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'first_name', label: 'First Name')]),
        data: {'first_name': 'Ana', 'monthly_income': '12000'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
          _snapField(id: 'f2', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        fromVersion: 1,
        currentVersion: 3,
      );

      expect(result.data['first_name'], 'Ana');
      expect(result.data.containsKey('monthly_income'), isFalse);
      expect(result.archived.single.key, 'monthly_income');
      expect(result.archived.single.label, 'Monthly Income');
      expect(result.archived.single.value, '12000');
      expect(result.archived.single.archivedAtVersion, 3);
      expect(result.removedFieldLabels, ['Monthly Income']);
    });

    test('reports a removed field the record never filled', () {
      // The reason the banner was silent in practice: deleting a field that a
      // given submission left blank archives nothing, but the record is still
      // on an older structure and must say so.
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'first_name', label: 'First Name')]),
        data: {'first_name': 'Ana'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
          _snapField(id: 'f2', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.archived, isEmpty);
      expect(result.removedFieldLabels, ['Monthly Income']);
      expect(result.isStale, isTrue);
      expect(result.hasChanges, isTrue);
      expect(
        result.summary,
        '1 field removed. This record held no data in the removed field.',
      );
    });

    test('reports a field absent from the snapshot as added', () {
      final result = service.migrateWithSnapshot(
        template: _template([
          _field(id: 'f1', name: 'first_name', label: 'First Name'),
          _field(id: 'f2', name: 'barangay', label: 'Barangay'),
        ]),
        data: {'first_name': 'Ana'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.addedFieldLabels, ['Barangay']);
      expect(result.archived, isEmpty);
      expect(result.renamed, isEmpty);
    });

    test('a key matching a field label is displayable, not archived', () {
      // loadFromJson falls back to a label match, so these still render.
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'first_name', label: 'First Name')]),
        data: {'First Name': 'Ana'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.archived, isEmpty);
      expect(result.data['First Name'], 'Ana');
    });

    test('leaves system-owned reserved keys alone', () {
      // Every `__`-prefixed key is written by the app, not by a template
      // field — controller state and record metadata alike. None can be
      // "removed" from a form, so none may reach the archive panel.
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'first_name', label: 'First Name')]),
        data: {
          'first_name': 'Ana',
          '__signature': 'base64…',
          '__session_id': 'be0e581d-9425-4b3f-8800-690a234aafff',
          '__applicant_name': {'first': 'Ana', 'middle': 'B', 'last': 'Cruz'},
          '__family_composition': [
            {'name': 'Ben'},
          ],
        },
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.archived, isEmpty);
      expect(result.data['__signature'], 'base64…');
      expect(result.data['__session_id'], isNotNull);
      expect(result.data['__applicant_name'], isA<Map<dynamic, dynamic>>());
      expect(result.data['__family_composition'], isA<List<dynamic>>());
    });

    test('a rename never overwrites a value already under the new key', () {
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'income', label: 'Income')]),
        data: {'monthly_income': '12000', 'income': '15000'},
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.data['income'], '15000');
      expect(result.data.containsKey('monthly_income'), isFalse);
    });

    test('lifts a previously archived value back once its field returns', () {
      final result = service.migrateWithSnapshot(
        template: _template([
          _field(id: 'f1', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        data: {
          '__archived__': {
            'monthly_income': {
              'label': 'Monthly Income',
              'value': '12000',
              'archived_at_version': 2,
            },
          },
        },
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'monthly_income', label: 'Monthly Income'),
        ]),
        fromVersion: 1,
        currentVersion: 3,
      );

      expect(result.data['monthly_income'], '12000');
      expect(result.data.containsKey('__archived__'), isFalse);
      expect(result.archived, isEmpty);
    });

    test('keeps an archived value archived while its field is still gone', () {
      final result = service.migrateWithSnapshot(
        template: _template([_field(id: 'f1', name: 'first_name', label: 'First Name')]),
        data: {
          'first_name': 'Ana',
          '__archived__': {
            'old_notes': {'label': 'Old Notes', 'value': 'n/a'},
          },
        },
        snapshot: _snapshot([
          _snapField(id: 'f1', name: 'first_name', label: 'First Name'),
        ]),
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.archived.single.key, 'old_notes');
      expect(result.archived.single.label, 'Old Notes');
      expect(result.data.containsKey('__archived__'), isFalse);
    });
  });

  group('migrateWithoutSnapshot', () {
    test('recovers removed data but reports no renames or additions', () {
      final result = service.migrateWithoutSnapshot(
        template: _template([
          _field(id: 'f1', name: 'first_name', label: 'First Name'),
          _field(id: 'f2', name: 'barangay', label: 'Barangay'),
        ]),
        data: {'first_name': 'Ana', 'monthly_income': '12000'},
        fromVersion: 1,
        currentVersion: 2,
      );

      expect(result.archived.single.key, 'monthly_income');
      expect(result.archived.single.label, 'monthly_income');
      expect(result.renamed, isEmpty);
      expect(result.addedFieldLabels, isEmpty);
      expect(result.snapshotMissing, isTrue);
    });
  });

  group('SubmissionMigration', () {
    test('upToDate reports no staleness and no changes', () {
      final result = SubmissionMigration.upToDate(
        version: 4,
        data: {'first_name': 'Ana'},
      );

      expect(result.isStale, isFalse);
      expect(result.hasChanges, isFalse);
    });

    test('summary counts each kind of change', () {
      final result = SubmissionMigration(
        submissionVersion: 1,
        currentVersion: 2,
        data: const {},
        archived: const [
          ArchivedFieldValue(key: 'a', label: 'A', value: '1'),
        ],
        removedFieldLabels: const ['A'],
        addedFieldLabels: const ['B', 'C'],
      );

      expect(
        result.summary,
        '1 field removed, 2 fields added. 1 held saved data on this record, '
        'preserved below.',
      );
      expect(result.isStale, isTrue);
      expect(result.hasChanges, isTrue);
    });
  });

  group('ArchivedFieldValue.displayValue', () {
    test('renders scalars, lists, rows, and blanks', () {
      expect(
        const ArchivedFieldValue(key: 'k', label: 'L', value: null).displayValue,
        '—',
      );
      expect(
        const ArchivedFieldValue(key: 'k', label: 'L', value: '  ').displayValue,
        '—',
      );
      expect(
        const ArchivedFieldValue(key: 'k', label: 'L', value: ['x', 'y'])
            .displayValue,
        'x, y',
      );
      expect(
        const ArchivedFieldValue(
          key: 'k',
          label: 'L',
          value: [
            {'a': 1},
            {'a': 2},
          ],
        ).displayValue,
        '2 row(s)',
      );
    });
  });
}
