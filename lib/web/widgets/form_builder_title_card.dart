import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';

class FormBuilderTitleCard extends StatelessWidget {
  const FormBuilderTitleCard({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final FormBuilderScreenController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final parts = controller.referenceFormatParts();

    return Container(
      decoration: AppColors.cardDecoration(radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              focusNode: controller.focusNode('formName'),
              controller: controller.ctrl('formName', controller.formName),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: AppColors.textDark,
              ),
              decoration: const InputDecoration(
                hintText: 'Untitled Form',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.highlight, width: 2),
                ),
              ),
              onChanged: (value) {
                controller.formName = value;
              },
            ),
            const SizedBox(height: 8),
            TextField(
              focusNode: controller.focusNode('formDesc'),
              controller: controller.ctrl('formDesc', controller.formDesc),
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
              decoration: const InputDecoration(
                hintText: 'Form description',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.highlight, width: 1),
                ),
              ),
              onChanged: (value) {
                controller.formDesc = value;
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    focusNode: controller.focusNode('formCode'),
                    controller: controller.ctrl(
                      'formCode',
                      controller.formCode,
                    ),
                    scrollPadding: EdgeInsets.zero,
                    decoration: const InputDecoration(
                      labelText: 'Form Code',
                      hintText: 'GIS',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      controller.formCode = controller.sanitizeCode(value);
                      if (controller.referencePrefix.trim().isEmpty) {
                        controller.referencePrefix = controller.formCode;
                        controller
                            .ctrl('referencePrefix', controller.referencePrefix)
                            .text = controller.referencePrefix;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    focusNode: controller.focusNode('referencePrefix'),
                    controller: controller.ctrl(
                      'referencePrefix',
                      controller.referencePrefix,
                    ),
                    scrollPadding: EdgeInsets.zero,
                    decoration: const InputDecoration(
                      labelText: 'Reference Prefix',
                      hintText: 'GIS',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      controller.referencePrefix = controller.sanitizeCode(value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 170,
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Needs Ref',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    value: controller.requiresReference,
                    onChanged: (value) {
                      controller.requiresReference = value;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            // ---- Collapsible: reference number format ----
            _collapsibleSection(
              context,
              title: 'Reference number format',
              icon: Icons.tag,
              initiallyExpanded: controller.requiresReference,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current format',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: parts.isEmpty
                            ? const [
                                Text(
                                  'No format tokens yet. Add tokens below.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ]
                            : List.generate(parts.length, (index) {
                                final part = parts[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.cardBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        part == ' ' ? 'space' : part,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: AppColors.textDark,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () =>
                                            controller.removeReferencePartAt(index),
                                        child: const Padding(
                                          padding: EdgeInsets.all(1),
                                          child: Icon(
                                            Icons.close,
                                            size: 14,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...referenceTokenGroups.map((group) {
                  final groupTokens = referenceTokens
                      .where((token) => token.group == group)
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: groupTokens
                              .map(
                                (token) => OutlinedButton(
                                  onPressed: () =>
                                      controller.appendReferenceToken(token.token),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryBlue,
                                    side: const BorderSide(
                                      color: AppColors.cardBorder,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Text(
                                    token.label,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Separators',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final separator in const ['-', '/', '_', '.', ' '])
                      OutlinedButton(
                        onPressed: () =>
                            controller.appendReferenceSeparator(separator),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          separator == ' ' ? 'space' : separator,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.requiresReference
                              ? controller.referencePreview()
                              : 'Reference disabled for this form',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: controller.requiresReference
                                ? AppColors.primaryBlue
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ---- Collapsible: mobile intro popup ----
            _collapsibleSection(
              context,
              title: 'Mobile intro popup',
              icon: Icons.info_outline_rounded,
              initiallyExpanded: controller.popupEnabled,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: controller.popupEnabled
                            ? AppColors.primaryBlue.withValues(alpha: 0.1)
                            : AppColors.pageBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: controller.popupEnabled
                            ? AppColors.primaryBlue
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Form Introduction Popup',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: controller.popupEnabled
                                  ? AppColors.textDark
                                  : AppColors.textMuted,
                            ),
                          ),
                          Text(
                            controller.popupEnabled
                                ? 'Shown on mobile before the user scans the QR'
                                : 'Disabled - mobile goes straight to QR scan',
                            style: TextStyle(
                              fontSize: 11,
                              color: controller.popupEnabled
                                  ? AppColors.primaryBlue.withValues(alpha: 0.75)
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: controller.popupEnabled,
                      activeThumbColor: AppColors.primaryBlue,
                      onChanged: (value) {
                        controller.popupEnabled = value;
                        controller.markChanged();
                      },
                    ),
                  ],
                ),
                if (controller.popupEnabled) ...[
                  const SizedBox(height: 14),
                  TextField(
                    focusNode: controller.focusNode('popupSubtitle'),
                    controller: controller.ctrl(
                      'popupSubtitle',
                      controller.popupSubtitle,
                    ),
                    scrollPadding: EdgeInsets.zero,
                    style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                    decoration: InputDecoration(
                      labelText: 'Subtitle',
                      hintText: 'e.g. Before you proceed...',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primaryBlue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      controller.popupSubtitle = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    focusNode: controller.focusNode('popupDesc'),
                    controller: controller.ctrl(
                      'popupDesc',
                      controller.popupDescription,
                    ),
                    scrollPadding: EdgeInsets.zero,
                    style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText:
                          'Explain what this form is for, what data is being collected, and how it will be used...',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primaryBlue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      alignLabelWithHint: true,
                    ),
                    onChanged: (value) {
                      controller.popupDescription = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.phone_android,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Preview  ',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: controller.formName.trim().isEmpty
                                      ? 'Untitled Form'
                                      : controller.formName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                if (controller.popupSubtitle.trim().isNotEmpty)
                                  TextSpan(
                                    text: '  ·  ${controller.popupSubtitle.trim()}',
                                  ),
                                if (controller.popupDescription.trim().isNotEmpty)
                                  TextSpan(
                                    text:
                                        '\n${controller.popupDescription.trim().length > 100 ? '${controller.popupDescription.trim().substring(0, 100)}...' : controller.popupDescription.trim()}',
                                  ),
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
          ],
        ),
      ),
    );
  }

  /// A bordered, collapsible section used to tuck away the advanced
  /// reference-format and mobile-popup config so the title card reads as
  /// just Name / Description / Code by default. Pure chrome — the children
  /// keep their existing controllers and callbacks.
  Widget _collapsibleSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool initiallyExpanded,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // Unique key so ExpansionTile's PageStorage-persisted expand state
          // does NOT collide with the canvas scroll offset stored in the same
          // PageStorage bucket (that collision made it read an int as bool?).
          key: PageStorageKey<String>('fb_collapsible_$title'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          shape: const Border(),
          leading: Icon(icon, size: 18, color: AppColors.textMuted),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}
