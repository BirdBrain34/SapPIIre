import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/web/controllers/form_builder_controller.dart';

String _slugify(String label) => label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

const _typeLabels = <FormFieldType, String>{
  FormFieldType.radio: 'Multiple Choice',
  FormFieldType.checkbox: 'Checkboxes',
  FormFieldType.dropdown: 'Dropdown',
  FormFieldType.text: 'Short Answer',
  FormFieldType.paragraph: 'Paragraph',
  FormFieldType.linearScale: 'Linear Scale',
  FormFieldType.date: 'Date',
  FormFieldType.time: 'Time',
  FormFieldType.number: 'Number',
  FormFieldType.boolean: 'Yes / No',
  FormFieldType.signature: 'Signature',
  FormFieldType.memberTable: 'Member Table',
};

const _typeIcons = <FormFieldType, IconData>{
  FormFieldType.radio: Icons.radio_button_checked,
  FormFieldType.checkbox: Icons.check_box_outlined,
  FormFieldType.dropdown: Icons.arrow_drop_down_circle_outlined,
  FormFieldType.text: Icons.short_text,
  FormFieldType.paragraph: Icons.notes,
  FormFieldType.linearScale: Icons.linear_scale,
  FormFieldType.date: Icons.calendar_today,
  FormFieldType.time: Icons.access_time,
  FormFieldType.number: Icons.pin,
  FormFieldType.boolean: Icons.toggle_on_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.memberTable: Icons.table_chart_outlined,
};

const _systemTypeLabels = <FormFieldType, String>{
  FormFieldType.computed: 'Computed',
  FormFieldType.conditional: 'Conditional',
  FormFieldType.membershipGroup: 'Membership Group',
  FormFieldType.familyTable: 'Family Table',
  FormFieldType.supportingFamilyTable: 'Supporting Family Table',
  FormFieldType.signature: 'Signature',
  FormFieldType.unknown: 'Unknown',
};

const _systemTypeIcons = <FormFieldType, IconData>{
  FormFieldType.computed: Icons.calculate_outlined,
  FormFieldType.conditional: Icons.device_hub_outlined,
  FormFieldType.membershipGroup: Icons.group_outlined,
  FormFieldType.familyTable: Icons.table_chart_outlined,
  FormFieldType.supportingFamilyTable: Icons.table_chart_outlined,
  FormFieldType.signature: Icons.draw_outlined,
  FormFieldType.unknown: Icons.help_outline,
};

const _referenceTokens = <ReferenceToken>[
  ReferenceToken('Form Code', '{FORMCODE}', 'GIS', 'Form Info'),
  ReferenceToken('Year (2026)', '{YYYY}', '2026', 'Date'),
  ReferenceToken('Year Short (26)', '{YY}', '26', 'Date'),
  ReferenceToken('Month Number (03)', '{MM}', '03', 'Date'),
  ReferenceToken('Month Short (MAR)', '{MON}', 'MAR', 'Date'),
  ReferenceToken('Day (26)', '{DD}', '26', 'Date'),
  ReferenceToken('Day of Year (085)', '{DDD}', '085', 'Date'),
  ReferenceToken('Quarter (1)', '{Q}', '1', 'Date'),
  ReferenceToken('Week Number (13)', '{WW}', '13', 'Date'),
  ReferenceToken('ISO Week (13)', '{IW}', '13', 'Date'),
  ReferenceToken('Hour (14)', '{HH24}', '14', 'Time'),
  ReferenceToken('Minute (30)', '{MI}', '30', 'Time'),
  ReferenceToken('Second (00)', '{SS}', '00', 'Time'),
  ReferenceToken('Counter 8-digit (00000001)', '{########}', '00000001', 'Counter'),
  ReferenceToken('Counter 6-digit (000001)', '{######}', '000001', 'Counter'),
  ReferenceToken('Counter 4-digit (0001)', '{####}', '0001', 'Counter'),
  ReferenceToken('Counter 3-digit (001)', '{###}', '001', 'Counter'),
  ReferenceToken('Counter 2-digit (01)', '{##}', '01', 'Counter'),
  ReferenceToken('Counter (1)', '{#}', '1', 'Counter'),
];

const _referenceTokenGroups = <String>['Form Info', 'Date', 'Time', 'Counter'];

class FormBuilderTemplateListPanel extends StatelessWidget {
  const FormBuilderTemplateListPanel({
    super.key,
    required this.templates,
    required this.selectedTemplateId,
    required this.isLoading,
    required this.filter,
    required this.onSelectTemplate,
    required this.onCreateNew,
    required this.onFilterChanged,
  });

  final List<Map<String, dynamic>> templates;
  final String? selectedTemplateId;
  final bool isLoading;
  final TemplateListFilter filter;
  final ValueChanged<String> onSelectTemplate;
  final VoidCallback onCreateNew;
  final ValueChanged<TemplateListFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final visibleTemplates = templates.where((t) {
      final status = (t['status'] as String?) ?? 'draft';
      final isArchived = status == 'archived';
      final isActive = (t['is_active'] as bool?) == true;
      return switch (filter) {
        TemplateListFilter.archived => isArchived,
        TemplateListFilter.draft => status == 'draft',
        TemplateListFilter.published => status == 'published',
        TemplateListFilter.active => isActive && !isArchived,
        TemplateListFilter.all => true,
      };
    }).toList();

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: AppColors.textDark, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My Templates',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark),
                  ),
                ),
                IconButton(
                  onPressed: onCreateNew,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.highlight,
                  tooltip: 'New Form',
                  iconSize: 22,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(label: const Text('All'), selected: filter == TemplateListFilter.all, onSelected: (_) => onFilterChanged(TemplateListFilter.all)),
                ChoiceChip(label: const Text('Active'), selected: filter == TemplateListFilter.active, onSelected: (_) => onFilterChanged(TemplateListFilter.active)),
                ChoiceChip(label: const Text('Draft'), selected: filter == TemplateListFilter.draft, onSelected: (_) => onFilterChanged(TemplateListFilter.draft)),
                ChoiceChip(label: const Text('Published'), selected: filter == TemplateListFilter.published, onSelected: (_) => onFilterChanged(TemplateListFilter.published)),
                ChoiceChip(label: const Text('Archived'), selected: filter == TemplateListFilter.archived, onSelected: (_) => onFilterChanged(TemplateListFilter.archived)),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.highlight))
                : visibleTemplates.isEmpty
                    ? _buildNoTemplates(filter: filter, onCreateNew: onCreateNew)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: visibleTemplates.length,
                        itemBuilder: (_, i) => _buildTemplateListItem(visibleTemplates[i], selectedTemplateId: selectedTemplateId, onSelectTemplate: onSelectTemplate),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTemplates({required TemplateListFilter filter, required VoidCallback onCreateNew}) {
    final emptyLabel = switch (filter) {
      TemplateListFilter.archived => 'No archived templates',
      TemplateListFilter.active => 'No active templates',
      TemplateListFilter.draft => 'No draft templates',
      TemplateListFilter.published => 'No published templates',
      TemplateListFilter.all => 'No templates yet',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_add_outlined, size: 48, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(emptyLabel, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onCreateNew, icon: const Icon(Icons.add, size: 18), label: const Text('Create New')),
        ],
      ),
    );
  }

  Widget _buildTemplateListItem(Map<String, dynamic> t, {required String? selectedTemplateId, required ValueChanged<String> onSelectTemplate}) {
    final id = t['template_id'] as String;
    final name = t['form_name'] as String? ?? 'Untitled';
    final status = t['status'] as String? ?? 'draft';
    final isActive = selectedTemplateId == id;
    final (Color statusClr, String statusLbl) = switch (status) {
      'published' => (Colors.blue, 'Published'),
      'pushed_to_mobile' => (Colors.green, 'Live'),
      'archived' => (Colors.grey, 'Archived'),
      _ => (Colors.orange, 'Draft'),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? AppColors.highlight.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive ? Border.all(color: AppColors.highlight.withOpacity(0.3)) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.description_outlined, color: isActive ? AppColors.highlight : AppColors.textMuted, size: 20),
        title: Text(name, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: statusClr, shape: BoxShape.circle)), const SizedBox(width: 4), Text(statusLbl, style: TextStyle(fontSize: 11, color: statusClr))]),
        onTap: () => onSelectTemplate(id),
      ),
    );
  }
}

class FormBuilderCanvasToolbar extends StatelessWidget {
  const FormBuilderCanvasToolbar({super.key, required this.activeSectionName, required this.onAddQuestion, required this.onAddIntakeModule});

  final String? activeSectionName;
  final VoidCallback onAddQuestion;
  final VoidCallback onAddIntakeModule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(color: AppColors.cardBg, border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: onAddQuestion,
            icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white),
            label: const Text('Add Question', style: TextStyle(color: Colors.white, fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.highlight, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onAddIntakeModule,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
            label: const Text('Add Intake Module', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.highlight, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), side: const BorderSide(color: AppColors.highlight), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const Spacer(),
          if (activeSectionName != null) Text('Active: $activeSectionName', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class FormBuilderTitleCard extends StatelessWidget {
  const FormBuilderTitleCard({super.key, required this.controller});

  final FormBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final referenceParts = controller.referenceFormatParts();
    return Container(
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller.ctrlLookup('formName', controller.formName),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: AppColors.textDark),
              decoration: const InputDecoration(hintText: 'Untitled Form', hintStyle: TextStyle(color: AppColors.textMuted), border: InputBorder.none, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.highlight, width: 2))),
              onChanged: controller.setFormName,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.ctrlLookup('formDesc', controller.formDesc),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
              decoration: const InputDecoration(hintText: 'Form description', hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14), border: InputBorder.none, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.transparent)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.highlight, width: 1))),
              onChanged: controller.setFormDesc,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.ctrlLookup('formCode', controller.formCode),
                    scrollPadding: EdgeInsets.zero,
                    decoration: InputDecoration(labelText: 'Form Code', hintText: 'GIS', isDense: true, filled: true, fillColor: AppColors.pageBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                    onChanged: controller.setFormCode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller.ctrlLookup('referencePrefix', controller.referencePrefix),
                    scrollPadding: EdgeInsets.zero,
                    decoration: InputDecoration(labelText: 'Reference Prefix', hintText: 'GIS', isDense: true, filled: true, fillColor: AppColors.pageBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                    onChanged: controller.setReferencePrefix,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 170,
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Needs Ref', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    value: controller.requiresReference,
                    onChanged: controller.setRequiresReference,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.pageBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reference Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: referenceParts.isEmpty
                        ? const [Text('No format tokens yet. Add tokens below.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))]
                        : List.generate(referenceParts.length, (i) {
                            final part = referenceParts[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(part == ' ' ? 'space' : part, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textDark, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  InkWell(borderRadius: BorderRadius.circular(10), onTap: () => controller.removeReferencePartAt(i), child: const Padding(padding: EdgeInsets.all(1), child: Icon(Icons.close, size: 14, color: AppColors.textMuted))),
                                ],
                              ),
                            );
                          }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._referenceTokenGroups.map((group) {
              final groupTokens = _referenceTokens.where((t) => t.group == group).toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: groupTokens
                          .map((t) => OutlinedButton(
                                onPressed: () => controller.appendReferenceToken(t.token),
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryBlue, side: const BorderSide(color: AppColors.cardBorder), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                                child: Text(t.label, style: const TextStyle(fontSize: 11)),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            const Align(alignment: Alignment.centerLeft, child: Text('Separators', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sep in const ['-', '/', '_', '.', ' '])
                  OutlinedButton(
                    onPressed: () => controller.appendReferenceSeparator(sep),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.textMuted, side: const BorderSide(color: AppColors.cardBorder), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                    child: Text(sep == ' ' ? 'space' : sep, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFF), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.requiresReference ? controller.referencePreview() : 'Reference disabled for this form',
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: controller.requiresReference ? AppColors.primaryBlue : AppColors.textMuted, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.cardBorder),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: controller.popupEnabled ? AppColors.primaryBlue.withOpacity(0.1) : AppColors.pageBg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.info_outline_rounded, size: 18, color: controller.popupEnabled ? AppColors.primaryBlue : AppColors.textMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Form Introduction Popup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: controller.popupEnabled ? AppColors.textDark : AppColors.textMuted)),
                      Text(controller.popupEnabled ? 'Shown on mobile before the user scans the QR' : 'Disabled - mobile goes straight to QR scan', style: TextStyle(fontSize: 11, color: controller.popupEnabled ? AppColors.primaryBlue.withOpacity(0.75) : AppColors.textMuted)),
                    ],
                  ),
                ),
                Switch(value: controller.popupEnabled, activeColor: AppColors.primaryBlue, onChanged: controller.setPopupEnabled),
              ],
            ),
            if (controller.popupEnabled) ...[
              const SizedBox(height: 14),
              TextField(
                controller: controller.ctrlLookup('popupSubtitle', controller.popupSubtitle),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(labelText: 'Subtitle', hintText: 'e.g. Before you proceed...', hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted), filled: true, fillColor: AppColors.pageBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryBlue)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                onChanged: controller.setPopupSubtitle,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller.ctrlLookup('popupDesc', controller.popupDescription),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                maxLines: 5,
                decoration: InputDecoration(labelText: 'Description', hintText: 'Explain what this form is for, what data is being collected, and how it will be used...', hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted), filled: true, fillColor: AppColors.pageBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryBlue)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), alignLabelWithHint: true),
                onChanged: controller.setPopupDescription,
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.04), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primaryBlue.withOpacity(0.15))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.phone_android, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          children: [
                            const TextSpan(text: 'Preview  ', style: TextStyle(fontWeight: FontWeight.w600)),
                            TextSpan(text: controller.formName.trim().isEmpty ? 'Untitled Form' : controller.formName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                            if (controller.popupSubtitle.trim().isNotEmpty) TextSpan(text: '  ·  ${controller.popupSubtitle.trim()}'),
                            if (controller.popupDescription.trim().isNotEmpty) TextSpan(text: '\n${controller.popupDescription.trim().length > 100 ? '${controller.popupDescription.trim().substring(0, 100)}...' : controller.popupDescription.trim()}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FormBuilderSectionHeader extends StatelessWidget {
  const FormBuilderSectionHeader({super.key, required this.section, required this.sectionIndex, required this.isActive, required this.sectionCount, required this.onTap, required this.onMoveUp, required this.onMoveDown, required this.onDelete, required this.onChanged, required this.ctrl});

  final BuilderSection section;
  final int sectionIndex;
  final bool isActive;
  final int sectionCount;
  final VoidCallback onTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final TextEditingController Function(String key, String initial) ctrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? AppColors.highlight : AppColors.cardBorder)),
        child: Row(
          children: [
            if (isActive)
              Container(width: 3, height: 64, decoration: const BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.horizontal(left: Radius.circular(8)))),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isActive ? 13 : 16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActive)
                      TextField(
                        controller: ctrl('sec_${section.id}', section.name),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textDark),
                        decoration: const InputDecoration(hintText: 'Section Title', border: InputBorder.none, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.highlight, width: 2))),
                        onChanged: (v) { section.name = v; onChanged(); },
                      )
                    else
                      Text(section.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textDark)),
                    if (isActive)
                      TextField(
                        controller: ctrl('sec_desc_${section.id}', section.description ?? ''),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                        decoration: const InputDecoration(hintText: 'Section description (optional)', hintStyle: TextStyle(fontSize: 13), border: InputBorder.none),
                        onChanged: (v) { section.description = v.isEmpty ? null : v; onChanged(); },
                      ),
                  ],
                ),
              ),
            ),
            if (isActive) ...[
              IconButton(icon: const Icon(Icons.arrow_upward, size: 18), onPressed: sectionIndex > 0 ? onMoveUp : null, tooltip: 'Move up'),
              IconButton(icon: const Icon(Icons.arrow_downward, size: 18), onPressed: sectionIndex < sectionCount - 1 ? onMoveDown : null, tooltip: 'Move down'),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: onDelete, tooltip: 'Delete section'),
            ],
          ],
        ),
      ),
    );
  }
}

class FormBuilderFieldCard extends StatefulWidget {
  const FormBuilderFieldCard({super.key, required this.field, required this.sectionIndex, required this.fieldIndex, required this.isActive, required this.allSections, required this.availableCanonicalKeys, required this.isLoadingCanonicalKeys, required this.onTap, required this.onDuplicate, required this.onDelete, required this.onMoveUp, required this.onMoveDown, required this.ctrlLookup, required this.onFieldChanged});

  final BuilderField field;
  final int sectionIndex;
  final int fieldIndex;
  final bool isActive;
  final List<BuilderSection> allSections;
  final List<({String key, String label})> availableCanonicalKeys;
  final bool isLoadingCanonicalKeys;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final TextEditingController Function(String key, String initial) ctrlLookup;
  final VoidCallback onFieldChanged;

  @override
  State<FormBuilderFieldCard> createState() => _FormBuilderFieldCardState();
}

class _FormBuilderFieldCardState extends State<FormBuilderFieldCard> {
  List<String> _formulaTokens(BuilderField field) => field.formula.trim().isEmpty ? [] : field.formula.trim().split(RegExp(r'\s+'));

  void _appendFormulaToken(BuilderField field, String token) {
    final tokens = _formulaTokens(field);
    tokens.add(token);
    setState(() => field.formula = tokens.join(' '));
    widget.onFieldChanged();
  }

  void _removeFormulaToken(BuilderField field, int index) {
    final tokens = _formulaTokens(field);
    if (index < 0 || index >= tokens.length) return;
    tokens.removeAt(index);
    setState(() => field.formula = tokens.join(' '));
    widget.onFieldChanged();
  }

  Widget _textPreview(String hint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
        child: Align(alignment: Alignment.centerLeft, child: Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
      );

  Widget _iconPreview(String hint, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
        child: Row(children: [Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)), const Spacer(), Icon(icon, size: 18, color: AppColors.textMuted)]),
      );

  Widget _optionRow(IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Icon(icon, size: 20, color: AppColors.textMuted), const SizedBox(width: 10), Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textDark))]),
      );

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.isActive ? AppColors.highlight : AppColors.cardBorder)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isActive) Container(width: 3, decoration: const BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.horizontal(left: Radius.circular(8)))),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(widget.isActive ? 18 : 24, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isActive) _buildFieldHeaderActive(field) else _buildFieldHeaderInactive(field),
                      const SizedBox(height: 12),
                      _buildFieldContent(field, widget.isActive),
                      if (widget.isActive) ...[const SizedBox(height: 8), const Divider(color: AppColors.cardBorder), _buildFieldToolbar(field)],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldHeaderActive(BuilderField field) {
    final isSignatureField = field.type == FormFieldType.signature;
    final canLinkCanonicalKey = field.type == FormFieldType.signature || field.type == FormFieldType.text || field.type == FormFieldType.number || field.type == FormFieldType.date || field.type == FormFieldType.dropdown || field.type == FormFieldType.radio || field.type == FormFieldType.boolean;
    final selectedCanonicalKey = isSignatureField ? 'signature' : field.canonicalFieldKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: widget.ctrlLookup('fld_${field.id}', field.label),
                scrollPadding: EdgeInsets.zero,
                style: const TextStyle(fontSize: 15, color: AppColors.textDark),
                decoration: InputDecoration(hintText: 'Question', filled: true, fillColor: AppColors.pageBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.highlight)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                onChanged: (v) { field.label = v; widget.onFieldChanged(); },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
                child: field.type.isSystemType || field.type == FormFieldType.computed
                    ? Row(children: [Icon(_systemTypeIcons[field.type] ?? Icons.help_outline, size: 18, color: AppColors.textMuted), const SizedBox(width: 8), Flexible(child: Text('System: ${_systemTypeLabels[field.type] ?? field.type.toDbString()}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted), overflow: TextOverflow.ellipsis))])
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<FormFieldType>(
                          value: field.type,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down),
                          style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                          items: _typeLabels.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Row(children: [Icon(_typeIcons[e.key], size: 18, color: AppColors.textMuted), const SizedBox(width: 8), Flexible(child: Text(e.value, overflow: TextOverflow.ellipsis))])))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              field.type = v;
                              if (v == FormFieldType.signature) field.canonicalFieldKey = 'signature';
                              if (v != FormFieldType.number) field.ageFromFieldId = null;
                              if (field.hasOptions && field.options.isEmpty) field.options.add(BuilderOption(label: 'Option 1'));
                            });
                            widget.onFieldChanged();
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (canLinkCanonicalKey) ...[
          const SizedBox(height: 10),
          const Text('Autofill Key (cross-form)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedCanonicalKey,
                isExpanded: true,
                hint: const Text('Link to known field (optional)', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                items: [
                  if (!isSignatureField) const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                  if (isSignatureField)
                    const DropdownMenuItem<String?>(value: 'signature', child: Text('Signature')),
                  ...widget.availableCanonicalKeys.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.key == entry.label ? entry.key : '${entry.label} (${entry.key})', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => field.canonicalFieldKey = isSignatureField ? 'signature' : value);
                  widget.onFieldChanged();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFieldHeaderInactive(BuilderField field) {
    return Row(
      children: [
        Icon((field.type.isSystemType ? _systemTypeIcons[field.type] : _typeIcons[field.type]) ?? Icons.help_outline, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(child: Text(field.label, style: const TextStyle(fontSize: 14, color: AppColors.textDark), overflow: TextOverflow.ellipsis)),
              if (field.canonicalFieldKey != null) ...[
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.highlight.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.highlight.withOpacity(0.4))), child: Text('⟷ ${field.canonicalFieldKey}', style: const TextStyle(fontSize: 10, color: AppColors.highlight))),
              ],
            ],
          ),
        ),
        if (field.isRequired) const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFieldToolbar(BuilderField field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVisibilityConditionRow(field),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 0,
          runSpacing: 4,
          children: [
            IconButton(icon: const Icon(Icons.content_copy, size: 18), tooltip: 'Duplicate', onPressed: widget.onDuplicate),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), tooltip: 'Delete', onPressed: widget.onDelete),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.cardBorder),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.arrow_upward, size: 18), tooltip: 'Move up', onPressed: widget.onMoveUp),
            IconButton(icon: const Icon(Icons.arrow_downward, size: 18), tooltip: 'Move down', onPressed: widget.onMoveDown),
            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.cardBorder),
            const SizedBox(width: 4),
            const Text('Required', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            Switch(value: field.isRequired, activeColor: AppColors.highlight, onChanged: (v) { setState(() => field.isRequired = v); widget.onFieldChanged(); }),
          ],
        ),
      ],
    );
  }

  Widget _buildVisibilityConditionRow(BuilderField field) {
    final triggerCandidates = widget.allSections
        .expand((s) => s.fields)
        .where((f) => f.id != field.id && (f.type == FormFieldType.boolean || f.type == FormFieldType.radio || f.type == FormFieldType.dropdown || f.type == FormFieldType.checkbox || f.type == FormFieldType.membershipGroup))
        .toList();
    final hasCondition = field.condition.triggerFieldId.isNotEmpty;
    BuilderField? triggerField;
    for (final f in triggerCandidates) {
      if (f.id == field.condition.triggerFieldId) {
        triggerField = f;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: hasCondition ? Colors.orange.withOpacity(0.06) : AppColors.pageBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: hasCondition ? Colors.orange.withOpacity(0.4) : AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.device_hub_outlined, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              const Text('Show only if...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const Spacer(),
              Switch(
                value: hasCondition,
                activeColor: Colors.orange,
                onChanged: triggerCandidates.isEmpty
                    ? null
                    : (v) => setState(() {
                          if (!v) {
                            field.condition.triggerFieldId = '';
                            field.condition.triggerValue = '';
                          } else {
                            field.condition.triggerFieldId = triggerCandidates.first.id;
                            field.condition.triggerValue = '';
                            field.condition.action = 'show';
                          }
                          widget.onFieldChanged();
                        }),
              ),
            ],
          ),
          if (hasCondition) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: field.condition.triggerFieldId.isEmpty ? null : field.condition.triggerFieldId,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 12, color: AppColors.textDark),
                        hint: const Text('Pick a field', style: TextStyle(fontSize: 12)),
                        items: triggerCandidates
                            .map((f) => DropdownMenuItem<String>(value: f.id, child: Text(f.label.isNotEmpty ? f.label : f.fieldName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (v) => setState(() {
                          field.condition.triggerFieldId = v ?? '';
                          field.condition.triggerValue = '';
                          field.condition.action = 'show';
                          widget.onFieldChanged();
                        }),
                      ),
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('=', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMuted))),
                Expanded(
                  flex: 2,
                  child: triggerField != null && (triggerField.hasOptions || triggerField.type == FormFieldType.boolean || triggerField.type == FormFieldType.membershipGroup)
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: field.condition.triggerValue.isEmpty ? null : field.condition.triggerValue,
                              isExpanded: true,
                              style: const TextStyle(fontSize: 12, color: AppColors.textDark),
                              hint: const Text('Pick a value', style: TextStyle(fontSize: 12)),
                              items: triggerField.type == FormFieldType.boolean
                                  ? const [DropdownMenuItem(value: 'yes', child: Text('Yes')), DropdownMenuItem(value: 'no', child: Text('No'))]
                                  : triggerField.type == FormFieldType.membershipGroup
                                      ? const [DropdownMenuItem(value: 'solo_parent', child: Text('Solo Parent')), DropdownMenuItem(value: 'pwd', child: Text('PWD')), DropdownMenuItem(value: 'four_ps_member', child: Text('4Ps Member')), DropdownMenuItem(value: 'phic_member', child: Text('PHIC Member'))]
                                      : triggerField.options.map((o) => DropdownMenuItem<String>(value: _slugify(o.label), child: Text(o.label, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (v) => setState(() {
                                field.condition.triggerValue = v ?? '';
                                field.condition.action = 'show';
                                widget.onFieldChanged();
                              }),
                            ),
                          ),
                        )
                      : TextField(
                          controller: widget.ctrlLookup('cond_val_${field.id}', field.condition.triggerValue),
                          scrollPadding: EdgeInsets.zero,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(hintText: 'Type value...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.orange)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                          onChanged: (v) {
                            field.condition.triggerValue = v;
                            field.condition.action = 'show';
                            widget.onFieldChanged();
                          },
                        ),
                ),
              ],
            ),
            if (field.condition.triggerValue.isNotEmpty)
              Text('This field shows when "${triggerField?.label ?? "?"}" = "${field.condition.triggerValue}"', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
            if (!hasCondition && triggerCandidates.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 4), child: Text('Add a Yes/No, radio, dropdown, checkbox, or Membership Group field first to use this.', style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldContent(BuilderField field, bool isActive) {
    switch (field.type) {
      case FormFieldType.text:
        return _textPreview('Short answer text');
      case FormFieldType.paragraph:
        return _textPreview('Long answer text');
      case FormFieldType.number:
        return _textPreview('Number');
      case FormFieldType.radio:
      case FormFieldType.checkbox:
      case FormFieldType.dropdown:
        return _optionsEditor(field, isActive);
      case FormFieldType.date:
        return _iconPreview('Month, Day, Year', Icons.calendar_today);
      case FormFieldType.time:
        return _iconPreview('Time', Icons.access_time);
      case FormFieldType.linearScale:
        return _linearScaleEditor(field, isActive);
      case FormFieldType.memberTable:
        return _textPreview('Member table');
      case FormFieldType.familyTable:
        return _textPreview('Family table');
      case FormFieldType.computed:
        return _formulaEditor(field, isActive);
      case FormFieldType.conditional:
        return _conditionEditor(field, isActive);
      case FormFieldType.boolean:
        return Column(children: [_optionRow(Icons.radio_button_unchecked, 'Yes'), _optionRow(Icons.radio_button_unchecked, 'No')]);
      default:
        return const SizedBox();
    }
  }

  Widget _optionsEditor(BuilderField field, bool isActive) {
    final isRadio = field.type == FormFieldType.radio;
    final isCheckbox = field.type == FormFieldType.checkbox;
    final optIcon = isRadio ? Icons.radio_button_unchecked : isCheckbox ? Icons.check_box_outline_blank : Icons.arrow_right;
    return Column(
      children: [
        ...List.generate(field.options.length, (oi) {
          final opt = field.options[oi];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(optIcon, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                if (isActive)
                  Expanded(
                    child: TextField(
                      controller: widget.ctrlLookup('opt_${opt.id}', opt.label),
                      scrollPadding: EdgeInsets.zero,
                      style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                      decoration: const InputDecoration(hintText: 'Option', border: InputBorder.none, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.highlight)), contentPadding: EdgeInsets.symmetric(vertical: 8)),
                      onChanged: (v) {
                        opt.label = v;
                        widget.onFieldChanged();
                      },
                    ),
                  )
                else
                  Expanded(child: Text(opt.label, style: const TextStyle(fontSize: 13, color: AppColors.textDark))),
                if (isActive && field.options.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () {
                      setState(() => field.options.removeAt(oi));
                      widget.onFieldChanged();
                    },
                  ),
              ],
            ),
          );
        }),
        if (isActive)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(optIcon, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    setState(() {
                      field.options.add(BuilderOption(label: 'Option ${field.options.length + 1}', order: field.options.length));
                    });
                    widget.onFieldChanged();
                  },
                  child: const Text('Add option'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _linearScaleEditor(BuilderField field, bool isActive) {
    if (!isActive) {
      return Row(children: [Text('${field.scaleMin}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)), Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 16), color: AppColors.cardBorder)), Text('${field.scaleMax}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted))]);
    }
    return Row(
      children: [
        const Text('From:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMin,
          items: [0, 1].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => field.scaleMin = v);
            widget.onFieldChanged();
          },
        ),
        const SizedBox(width: 24),
        const Text('To:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: field.scaleMax,
          items: List.generate(9, (i) => i + 2).map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => field.scaleMax = v);
            widget.onFieldChanged();
          },
        ),
      ],
    );
  }

  Widget _formulaEditor(BuilderField field, bool isActive) {
    final tokens = _formulaTokens(field);
    if (!isActive) return _textPreview(tokens.isEmpty ? 'No formula set' : tokens.join(' '));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Formula', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        const Text('Tap field names and operators below to build the formula.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.buttonOutlineBlue.withOpacity(0.4))),
          child: tokens.isEmpty
              ? const Text('Empty - add fields and operators below', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic))
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tokens.asMap().entries.map((e) {
                    final i = e.key;
                    final tok = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.buttonOutlineBlue)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(tok, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.primaryBlue)), const SizedBox(width: 4), GestureDetector(onTap: () => _removeFormulaToken(field, i), child: const Icon(Icons.close, size: 13, color: AppColors.primaryBlue))]),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['+', '-', '*', '/', '(', ')']
              .map((op) => ElevatedButton(
                    onPressed: () => _appendFormulaToken(field, op),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8EEFF), foregroundColor: AppColors.primaryBlue, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), minimumSize: const Size(36, 32)),
                    child: Text(op, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _conditionEditor(BuilderField field, bool isActive) => _textPreview(isActive ? 'Condition editor' : 'No condition');
}

class FormBuilderStatusCard extends StatelessWidget {
  const FormBuilderStatusCard({super.key, required this.formStatus, required this.onUnpublish, required this.onArchive, required this.onRestore});

  final String formStatus;
  final VoidCallback onUnpublish;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final (Color clr, String label, String desc, IconData icon) = switch (formStatus) {
      'published' => (Colors.blue, 'PUBLISHED', 'Visible to admin staff in Manage Forms', Icons.visibility),
      'pushed_to_mobile' => (Colors.green, 'LIVE ON MOBILE', 'Users can fill this form on the mobile app', Icons.phone_android),
      'archived' => (Colors.grey, 'ARCHIVED', 'Hidden from admins & mobile. Data preserved.', Icons.archive_outlined),
      _ => (Colors.orange, 'DRAFT', 'Only you can see this template', Icons.edit_note),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: clr.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: clr.withOpacity(0.3))),
      child: Row(
        children: [
          Icon(icon, color: clr, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Status: $label', style: TextStyle(fontWeight: FontWeight.bold, color: clr, fontSize: 13)), Text(desc, style: TextStyle(color: clr.withOpacity(0.8), fontSize: 12))])),
          const SizedBox(width: 12),
          if (formStatus != 'archived') ...[
            if (formStatus != 'draft') TextButton(onPressed: onUnpublish, child: const Text('Revert to Draft')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: onArchive, icon: const Icon(Icons.archive_outlined, size: 16), label: const Text('Archive'), style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange))),
          ],
          if (formStatus == 'archived') ...[
            ElevatedButton.icon(onPressed: onRestore, icon: const Icon(Icons.restore, size: 18), label: const Text('Restore to Draft'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white)),
          ],
        ],
      ),
    );
  }
}

class FormBuilderAddSectionButton extends StatelessWidget {
  const FormBuilderAddSectionButton({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.playlist_add, size: 20), label: const Text('Add Section'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.highlight, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), side: BorderSide(color: AppColors.highlight.withOpacity(0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
}

class FormBuilderHeaderButton extends StatelessWidget {
  const FormBuilderHeaderButton(this.label, this.icon, {super.key, this.onPressed, this.color});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(backgroundColor: color ?? AppColors.primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
