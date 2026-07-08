import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';

class FormBuilderSectionHeader extends StatelessWidget {
  const FormBuilderSectionHeader({
    super.key,
    required this.section,
    required this.sectionIndex,
    required this.isActive,
    required this.controller,
    required this.onTap,
  });

  final BuilderSection section;
  final int sectionIndex;
  final bool isActive;
  final FormBuilderScreenController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, top: 4),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.highlight : AppColors.cardBorder,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isActive)
              Container(
                width: 3,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.highlight,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isActive ? 13 : 16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActive)
                      TextField(
                        focusNode: controller.focusNode('sec_${section.id}'),
                        controller: controller.ctrl(
                          'sec_${section.id}',
                          section.name,
                        ),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Section Title',
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.highlight,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          section.name = value;
                        },
                      )
                    else
                      Text(
                        section.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                      ),
                    if (isActive)
                      TextField(
                        focusNode: controller.focusNode(
                          'sec_desc_${section.id}',
                        ),
                        controller: controller.ctrl(
                          'sec_desc_${section.id}',
                          section.description ?? '',
                        ),
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Section description (optional)',
                          hintStyle: TextStyle(fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          section.description = value.isEmpty ? null : value;
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (isActive) ...[
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: sectionIndex > 0
                    ? () => controller.moveSection(sectionIndex, -1)
                    : null,
                tooltip: 'Move up',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: sectionIndex < controller.sections.length - 1
                    ? () => controller.moveSection(sectionIndex, 1)
                    : null,
                tooltip: 'Move down',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.red,
                ),
                onPressed: () => controller.removeSection(sectionIndex),
                tooltip: 'Delete section',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
