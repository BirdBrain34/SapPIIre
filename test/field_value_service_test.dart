import 'package:flutter_test/flutter_test.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/field_value_service.dart';

void main() {
  group('mergeTablePayloads', () {
    /// Build a destination column FormFieldModel with just the essential fields.
    FormFieldModel col(String fieldName, {String? canonicalFieldKey}) {
      return FormFieldModel(
        fieldId: 'col_$fieldName',
        templateId: 't1',
        fieldName: fieldName,
        fieldLabel: fieldName,
        fieldType: FormFieldType.text,
        canonicalFieldKey: canonicalFieldKey,
      );
    }

    test('matches by exact column label (Tier 3)', () {
      final destColumns = [
        col('Name'),
        col('Age'),
        col('Address'),
      ];

      final sourceRows = [
        {'Name': 'Juan', 'Age': '30', 'ExtraCol': 'should_be_dropped'},
        {'Name': 'Maria', 'Age': '25', 'ExtraCol': 'dropped'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(2));
      expect(result[0], containsPair('Name', 'Juan'));
      expect(result[0], containsPair('Age', '30'));
      expect(result[0], isNot(contains('ExtraCol')));
      expect(result[1], containsPair('Name', 'Maria'));
      expect(result[1], containsPair('Age', '25'));
    });

    test('matches by semantic alias (Tier 2)', () {
      // Source uses "Pangalan" (Filipino for "Name"), dest has "First Name".
      // _keyFromTextPreferAlias("Pangalan") returns "first_name",
      // and _keyFromTextPreferAlias("First Name") also returns "first_name".
      final destColumns = [
        col('First Name'),
        col('Age'),
      ];

      final sourceRows = [
        {'Pangalan': 'Juan', 'Age': '30'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(1));
      // "Pangalan" alias-maps to "first_name", and "First Name" also
      // resolves to "first_name", so the value lands in "First Name".
      expect(result[0], containsPair('First Name', 'Juan'));
      expect(result[0], containsPair('Age', '30'));
    });

    test('drops source-only extra columns silently', () {
      final destColumns = [
        col('Name'),
        col('Age'),
      ];

      final sourceRows = [
        {'Name': 'Juan', 'Age': '30', 'Unwanted': 'nope'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(1));
      expect(result[0], containsPair('Name', 'Juan'));
      expect(result[0], containsPair('Age', '30'));
      expect(result[0], isNot(contains('Unwanted')));
    });

    test('omits no-match column from row silently (not an error)', () {
      // Source has "Edad" which does NOT match any alias or exact label in dest.
      final destColumns = [
        col('First Name'),
        col('Age'), // "Edad" doesn't alias to "Age" in the current table.
      ];

      final sourceRows = [
        {'First Name': 'Juan', 'Edad': '30'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(1));
      expect(result[0], containsPair('First Name', 'Juan'));
      // "Edad" has no match in dest — silently omitted.
      expect(result[0], isNot(contains('Age')));
    });

    test('drops a row where zero columns match entirely', () {
      final destColumns = [
        col('Name'),
      ];

      final sourceRows = [
        {'Completely': 'Unrelated'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(0));
    });

    test('empty destination columns returns empty list', () {
      final sourceRows = [
        {'Name': 'Juan'},
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: [],
      );

      expect(result, hasLength(0));
    });

    test('handles non-Map entries in sourceRows gracefully', () {
      final destColumns = [
        col('Name'),
      ];

      final sourceRows = [
        {'Name': 'Juan'},
        'not a map',
        42,
        null,
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(1));
      expect(result[0], containsPair('Name', 'Juan'));
    });

    test('multi-row with mixed match outcomes', () {
      // Row 0: both columns match → populated
      // Row 1: no columns match → dropped entirely
      // Row 2: one column matches → partial row kept
      final destColumns = [
        col('Name'),
        col('Birthdate'),
      ];

      final sourceRows = [
        {'Name': 'Juan', 'Birthdate': '2000-01-01'},
        {'Gibberish': 'Nothing'},
        {'Name': 'Maria'}, // only Name matches
      ];

      final result = FieldValueService.mergeTablePayloads(
        sourceRows: sourceRows,
        destinationColumns: destColumns,
      );

      expect(result, hasLength(2));
      expect(result[0], containsPair('Name', 'Juan'));
      expect(result[0], containsPair('Birthdate', '2000-01-01'));
      // Middle row dropped entirely
      expect(result[1], containsPair('Name', 'Maria'));
      expect(result[1], isNot(contains('Birthdate')));
    });
  });
}