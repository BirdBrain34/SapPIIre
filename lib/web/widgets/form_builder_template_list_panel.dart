import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';

class FormBuilderTemplateListPanel extends StatelessWidget {
  const FormBuilderTemplateListPanel({
    super.key,
    required this.controller,
    required this.onCreateNew,
    required this.onSelectTemplate,
  });

  final FormBuilderScreenController controller;
  final VoidCallback onCreateNew;
  final void Function(String templateId) onSelectTemplate;

  @override
  Widget build(BuildContext context) {
    final visibleTemplates = controller.templates.where((template) {
      final status = (template['status'] as String?) ?? 'draft';
      final isArchived = status == 'archived';
      final rawIsActive = template['is_active'];
      final isActive = rawIsActive is bool
          ? rawIsActive
          : (rawIsActive is int ? rawIsActive == 1 : false);

      return switch (controller.templateListFilter) {
        TemplateListFilter.archived => isArchived,
        TemplateListFilter.draft => status == 'draft',
        TemplateListFilter.published => status == 'published',
        TemplateListFilter.pendingApproval => status == 'pending_approval',
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
                const Icon(
                  Icons.description_outlined,
                  color: AppColors.textDark,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My Templates',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
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
            child: ChipTheme(
              data: ChipThemeData(
                backgroundColor: AppColors.pageBg,
                selectedColor: AppColors.highlight.withValues(alpha: 0.15),
                showCheckmark: false,
                labelStyle: const TextStyle(fontSize: 12, color: AppColors.textDark),
                secondaryLabelStyle: const TextStyle(fontSize: 12, color: AppColors.highlight),
                side: const BorderSide(color: AppColors.cardBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected:
                      controller.templateListFilter == TemplateListFilter.all,
                  onSelected: (_) {
                    controller.templateListFilter = TemplateListFilter.all;
                    controller.markChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Active'),
                  selected:
                      controller.templateListFilter ==
                      TemplateListFilter.active,
                  onSelected: (_) {
                    controller.templateListFilter = TemplateListFilter.active;
                    controller.markChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Draft'),
                  selected:
                      controller.templateListFilter == TemplateListFilter.draft,
                  onSelected: (_) {
                    controller.templateListFilter = TemplateListFilter.draft;
                    controller.markChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Published'),
                  selected:
                      controller.templateListFilter ==
                      TemplateListFilter.published,
                  onSelected: (_) {
                    controller.templateListFilter =
                        TemplateListFilter.published;
                    controller.markChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Pending'),
                  selected:
                      controller.templateListFilter ==
                      TemplateListFilter.pendingApproval,
                  onSelected: (_) {
                    controller.templateListFilter =
                        TemplateListFilter.pendingApproval;
                    controller.markChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Archived'),
                  selected:
                      controller.templateListFilter ==
                      TemplateListFilter.archived,
                  onSelected: (_) {
                    controller.templateListFilter = TemplateListFilter.archived;
                    controller.markChanged();
                  },
                ),
                ],
              ),
            ),
          ),
          Expanded(
            child: controller.isLoadingList
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.highlight,
                    ),
                  )
                : visibleTemplates.isEmpty
                ? _buildNoTemplates(controller.templateListFilter)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: visibleTemplates.length,
                    itemBuilder: (_, index) =>
                        _buildTemplateListItem(visibleTemplates[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTemplates(TemplateListFilter filter) {
    final emptyLabel = switch (filter) {
      TemplateListFilter.archived => 'No archived templates',
      TemplateListFilter.active => 'No active templates',
      TemplateListFilter.draft => 'No draft templates',
      TemplateListFilter.published => 'No published templates',
      TemplateListFilter.pendingApproval => 'No pending approval templates',
      TemplateListFilter.all => 'No templates yet',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 48,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(emptyLabel, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCreateNew,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateListItem(Map<String, dynamic> template) {
    final id = template['template_id'] as String;
    final name = template['form_name'] as String? ?? 'Untitled';
    final status = template['status'] as String? ?? 'draft';
    final isActive = controller.activeTemplateId == id;

    final (Color statusColor, String statusLabel) = switch (status) {
      'published' => (Colors.blue, 'Published'),
      'pushed_to_mobile' => (Colors.green, 'Live'),
      'archived' => (Colors.grey, 'Archived'),
      'pending_approval' => (Colors.deepPurple, 'Pending'),
      _ => (Colors.orange, 'Draft'),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.highlight.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.highlight.withValues(alpha: 0.35)
              : AppColors.cardBorder,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          Icons.description_outlined,
          color: isActive ? AppColors.highlight : AppColors.textMuted,
          size: 20,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: AppColors.textDark,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              statusLabel,
              style: TextStyle(fontSize: 11, color: statusColor),
            ),
          ],
        ),
        onTap: () {
          if (id == controller.activeTemplateId) return;
          onSelectTemplate(id);
        },
      ),
    );
  }
}
