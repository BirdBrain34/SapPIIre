import 'package:flutter_test/flutter_test.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/models/form_template_models.dart';

FormFieldModel _field({
  required String id,
  required String name,
  required String label,
  required FormFieldType type,
  int order = 0,
  Map<String, dynamic>? rules,
}) {
  return FormFieldModel(
    fieldId: id,
    templateId: 'tpl_1',
    sectionId: 'sec_1',
    fieldName: name,
    fieldLabel: label,
    fieldType: type,
    fieldOrder: order,
    validationRules: rules,
  );
}

FormTemplate _templateWithChain({required bool putFBeforeD}) {
  final fields = <FormFieldModel>[
    _field(id: 'a', name: 'A', label: 'A', type: FormFieldType.number, order: 1),
    _field(id: 'b', name: 'B', label: 'B', type: FormFieldType.number, order: 2),
    _field(id: 'c', name: 'C', label: 'C', type: FormFieldType.number, order: 3),
    _field(id: 'e', name: 'E', label: 'E', type: FormFieldType.number, order: 4),
    _field(
      id: 'd',
      name: 'D',
      label: 'D',
      type: FormFieldType.computed,
      order: putFBeforeD ? 6 : 5,
      rules: {'formula': 'A + B + C'},
    ),
    _field(
      id: 'f',
      name: 'F',
      label: 'F',
      type: FormFieldType.computed,
      order: putFBeforeD ? 5 : 6,
      rules: {'formula': 'D / E'},
    ),
  ]..sort((x, y) => x.fieldOrder.compareTo(y.fieldOrder));

  return FormTemplate(
    templateId: 'tpl_1',
    formName: 'Formula Chain Test',
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

FormTemplate _templateWithLabelOverlap() {
  final fields = <FormFieldModel>[
    _field(
      id: 'a2',
      name: 'amount_a',
      label: 'Amount A',
      type: FormFieldType.number,
      order: 1,
    ),
    _field(
      id: 'b2',
      name: 'amount_b',
      label: 'Amount B',
      type: FormFieldType.number,
      order: 2,
    ),
    _field(
      id: 'c2',
      name: 'cost_c',
      label: 'Cost C',
      type: FormFieldType.number,
      order: 3,
    ),
    _field(
      id: 'e2',
      name: 'divider_e',
      label: 'Divider E',
      type: FormFieldType.number,
      order: 4,
    ),
    _field(
      id: 'd2',
      name: 'derived_d',
      label: 'D',
      type: FormFieldType.computed,
      order: 6,
      rules: {'formula': 'Amount A + Amount B + Cost C'},
    ),
    _field(
      id: 'f2',
      name: 'final_f',
      label: 'Final Result',
      type: FormFieldType.computed,
      order: 5,
      rules: {'formula': 'D / Divider E'},
    ),
    _field(
      id: 'g2',
      name: 'derived_d_total',
      label: 'D Total',
      type: FormFieldType.number,
      order: 7,
    ),
  ]..sort((x, y) => x.fieldOrder.compareTo(y.fieldOrder));

  return FormTemplate(
    templateId: 'tpl_2',
    formName: 'Formula Label Overlap Test',
    sections: [
      FormSection(
        sectionId: 'sec_2',
        templateId: 'tpl_2',
        sectionName: 'Main',
        fields: fields,
      ),
    ],
  );
}

FormTemplate _templateWithLiveScenario() {
  final fields = <FormFieldModel>[
    _field(
      id: 'bw_kita',
      name: 'buwang_kita',
      label: 'Buwang Kita',
      type: FormFieldType.number,
      order: 1,
    ),
    _field(
      id: 'kab_tulong',
      name: 'kabuuang_tulong',
      label: 'Kabuuang Tulong',
      type: FormFieldType.number,
      order: 2,
    ),
    _field(
      id: 'kab_kita',
      name: 'kabuuang_kita',
      label: 'Kabuuang kita',
      type: FormFieldType.number,
      order: 3,
    ),
    _field(
      id: 'hh_size',
      name: 'household_size',
      label: 'Household size',
      type: FormFieldType.number,
      order: 4,
    ),
    _field(
      id: 'gross_income',
      name: 'total_gross_family_income',
      label: 'Total Gross Family Income',
      type: FormFieldType.computed,
      order: 5,
      rules: {'formula': 'Buwang Kita + Kabuuang Tulong + Kabuuang kita'},
    ),
    _field(
      id: 'monthly_pc_income',
      name: 'monthly_per_capita_income',
      label: 'Monthly Per Capital Income',
      type: FormFieldType.computed,
      order: 6,
      rules: {'formula': 'Total Gross Family Income / Household size'},
    ),
  ]..sort((x, y) => x.fieldOrder.compareTo(y.fieldOrder));

  return FormTemplate(
    templateId: 'tpl_3',
    formName: 'Live Scenario Test',
    sections: [
      FormSection(
        sectionId: 'sec_3',
        templateId: 'tpl_3',
        sectionName: 'Main',
        fields: fields,
      ),
    ],
  );
}

void main() {
  test('computed chain resolves when F appears before D in schema order', () async {
    final controller = FormStateController(
      template: _templateWithChain(putFBeforeD: true),
    );

    controller.setValue('A', '1');
    controller.setValue('B', '2');
    controller.setValue('C', '3');
    controller.setValue('E', '2');

    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.getValue('D'), '6.00');
    expect(controller.getValue('F'), '3.00');
  });

  test('computed chain also resolves when D appears before F', () async {
    final controller = FormStateController(
      template: _templateWithChain(putFBeforeD: false),
    );

    controller.setValue('A', '4');
    controller.setValue('B', '5');
    controller.setValue('C', '1');
    controller.setValue('E', '2');

    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.getValue('D'), '10.00');
    expect(controller.getValue('F'), '5.00');
  });

  test('label overlap does not corrupt computed dependencies', () async {
    final controller = FormStateController(template: _templateWithLabelOverlap());

    controller.setValue('amount_a', '1');
    controller.setValue('amount_b', '2');
    controller.setValue('cost_c', '3');
    controller.setValue('divider_e', '2');
    controller.setValue('derived_d_total', '999');

    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.getValue('derived_d'), '6.00');
    expect(controller.getValue('final_f'), '3.00');
  });

  test('live scenario resolves Monthly Per Capital Income from computed gross income', () async {
    final controller = FormStateController(
      template: _templateWithLiveScenario(),
    );

    controller.setValue('buwang_kita', '100');
    controller.setValue('kabuuang_tulong', '100');
    controller.setValue('kabuuang_kita', '100');
    controller.setValue('household_size', '2');

    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.getValue('total_gross_family_income'), '300.00');
    expect(controller.getValue('monthly_per_capita_income'), '150.00');
  });
}
