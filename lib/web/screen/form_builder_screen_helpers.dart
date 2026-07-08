part of 'form_builder_screen.dart';

Widget buildFormBuilderScreen(_FormBuilderScreenState state) {
  return WebShell(
    activePath: 'FormBuilder',
    pageTitle: 'Form Builder',
    pageSubtitle: state._controller.activeTemplateId != null ? state._controller.formName : 'Create and manage form templates',
    role: state.widget.role,
    cswd_id: state.widget.cswd_id,
    displayName: state.widget.displayName,
    onLogout: state._handleLogout,
    headerActions: const [],
    onNavigate: (path) => WebNavigator.go(state.context, path, cswdId: state.widget.cswd_id, role: state.widget.role, displayName: state.widget.displayName),
    child: AnimatedBuilder(
      animation: state._controller,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormBuilderTemplateListPanel(
              controller: state._controller,
              onCreateNew: () {
                state._controller.createNewTemplate();
              },
              onSelectTemplate: (templateId) {
                state._handleTemplateSelect(templateId);
              },
            ),
            Expanded(
              child: state._controller.activeTemplateId == null
                  ? buildEmptyState(state)
                  : state._controller.isLoadingTemplate
                  ? const Center(child: CircularProgressIndicator(color: AppColors.highlight))
                  : buildBuilderCanvas(state),
            ),
          ],
        );
      },
    ),
  );
}

Widget buildBuilderCanvas(_FormBuilderScreenState state) {
  return PageStorage(
    bucket: state._pageStorageBucket,
    child: Container(
      color: AppColors.pageBg,
      child: Column(
        children: [
          buildCanvasToolbar(state),
          Expanded(
            child: SingleChildScrollView(
              key: const PageStorageKey<String>('form_builder_canvas_scroll'),
              controller: state._scrollCtrl,
              primary: false,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 720,
                  child: Column(
                    children: [
                      FormBuilderTitleCard(controller: state._controller, onChanged: () => state._controller.markChanged()),
                      const SizedBox(height: 12),
                      ...buildAllSections(state),
                      const SizedBox(height: 16),
                      buildAddSectionButton(state),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Canvas action bar
//
// One bar holds everything the user acts on: build actions on the left
// (Add Question / Add Intake Module), and status + save/lifecycle actions on
// the right. Save is the primary, right-pinned button. Secondary lifecycle
// actions (Revert / Archive) live behind a "More" (⋮) menu to keep it tidy.
// This replaces the old top-bar header actions AND the old bottom status card.
// ---------------------------------------------------------------------------
Widget buildCanvasToolbar(_FormBuilderScreenState state) {
  final ctrl = state._controller;
  final targetSectionIndex = ctrl.activeSectionIdx ?? (ctrl.sections.isNotEmpty ? ctrl.sections.length - 1 : null);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: const BoxDecoration(
      color: AppColors.cardBg,
      border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
    ),
    child: Row(
      children: [
        // ---- Build cluster (left) ----
        buildPrimaryAction(
          'Add Question',
          Icons.add_circle_outline,
          onPressed: targetSectionIndex != null ? () => ctrl.addField(targetSectionIndex) : null,
        ),
        const SizedBox(width: 12),
        buildOutlinedAction(
          'Add Intake Module',
          Icons.dashboard_customize_outlined,
          onPressed: targetSectionIndex != null ? () => showSystemBlockPicker(state, targetSectionIndex) : null,
        ),
        if (ctrl.activeSectionIdx != null) ...[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              'into  ${ctrl.sections[ctrl.activeSectionIdx!].name}',
              maxLines: 1,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(width: 16),
        // ---- Status + save cluster (right) ----
        // Right-pinned when it fits; scrolls horizontally (keeping the Save
        // end visible via reverse) when the bar gets cramped on narrow screens.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                buildStatusPill(ctrl.formStatus),
                if (ctrl.hasUnsavedChanges) ...[
                  const SizedBox(width: 8),
                  buildUnsavedChip(),
                ],
                const SizedBox(width: 16),
                ...buildLifecycleActions(state),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Status-driven Save + lifecycle actions for the right side of the action bar.
/// Consolidates what used to be split between the WebShell header and the
/// bottom status card. Keeps the exact status branching + state-method wiring.
List<Widget> buildLifecycleActions(_FormBuilderScreenState state) {
  final ctrl = state._controller;
  final saving = ctrl.isSaving;

  switch (ctrl.formStatus) {
    case 'draft':
      return [
        buildOutlinedAction('Publish', Icons.publish, onPressed: () => state._publishTemplateAndSnack()),
        const SizedBox(width: 8),
        buildPrimaryAction('Save Draft', Icons.save_outlined, busy: saving, onPressed: saving ? null : () => state._saveTemplateAndSnack()),
      ];
    case 'published':
      return [
        buildOutlinedAction('Push to Mobile', Icons.phone_android, color: Colors.green, onPressed: () => state._pushToMobileAndSnack()),
        const SizedBox(width: 8),
        buildPrimaryAction('Save', Icons.save_outlined, busy: saving, onPressed: saving ? null : () => state._saveTemplateAndSnack()),
        buildMoreMenu(state),
      ];
    case 'pushed_to_mobile':
      return [
        buildPrimaryAction('Save', Icons.save_outlined, busy: saving, onPressed: saving ? null : () => state._saveTemplateAndSnack()),
        buildMoreMenu(state),
      ];
    case 'archived':
      return [
        buildPrimaryAction('Restore', Icons.restore, color: Colors.teal, onPressed: () => state._restoreTemplateAndSnack()),
      ];
    default:
      return const [];
  }
}

/// Filled primary button (Save / Add Question / Restore …).
/// [busy] swaps the icon for a spinner (used by Save while [isSaving]).
Widget buildPrimaryAction(String label, IconData icon, {required VoidCallback? onPressed, Color color = AppColors.highlight, bool busy = false}) {
  return ElevatedButton.icon(
    onPressed: onPressed,
    icon: busy
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Icon(icon, size: 18, color: Colors.white),
    label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Secondary outlined button (Add Intake Module / Publish / Push to Mobile).
Widget buildOutlinedAction(String label, IconData icon, {required VoidCallback? onPressed, Color color = AppColors.highlight}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Status pill (DRAFT / PUBLISHED / LIVE ON MOBILE / ARCHIVED).
Widget buildStatusPill(String status) {
  final descriptor = statusDescriptor(status);
  return Tooltip(
    message: descriptor.description,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: descriptor.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: descriptor.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: descriptor.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            descriptor.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: descriptor.color),
          ),
        ],
      ),
    ),
  );
}

/// Amber "Unsaved changes" chip, shown only when [hasUnsavedChanges].
Widget buildUnsavedChip() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.warningAmber.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.warningAmber, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        const Text('Unsaved changes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ],
    ),
  );
}

/// "More" (⋮) menu for the secondary lifecycle actions (Revert / Archive).
Widget buildMoreMenu(_FormBuilderScreenState state) {
  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'revert':
            state._unpublishTemplateAndSnack();
            break;
          case 'archive':
            state._archiveTemplateAndSnack();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'revert',
          child: Row(children: [Icon(Icons.undo, size: 18, color: AppColors.textMuted), SizedBox(width: 12), Text('Revert to Draft')]),
        ),
        PopupMenuItem<String>(
          value: 'archive',
          child: Row(children: [Icon(Icons.archive_outlined, size: 18, color: Colors.orange), SizedBox(width: 12), Text('Archive')]),
        ),
      ],
    ),
  );
}

List<Widget> buildAllSections(_FormBuilderScreenState state) {
  final items = <Widget>[];
  for (var sectionIndex = 0; sectionIndex < state._controller.sections.length; sectionIndex++) {
    final section = state._controller.sections[sectionIndex];
    final isActive = state._controller.activeSectionIdx == sectionIndex;
    items.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            FormBuilderSectionHeader(
              section: section,
              sectionIndex: sectionIndex,
              isActive: isActive,
              controller: state._controller,
              onTap: () {
                state._controller.selectSection(sectionIndex);
              },
            ),
            ...List.generate(section.fields.length, (fieldIndex) {
              final isFieldActive = state._controller.activeSectionIdx == sectionIndex && state._controller.activeFieldIdx == fieldIndex;
              return FormBuilderFieldCard(
                field: section.fields[fieldIndex],
                sectionIndex: sectionIndex,
                fieldIndex: fieldIndex,
                isActive: isFieldActive,
                controller: state._controller,
                onTap: () {
                  state._controller.selectField(sectionIndex, fieldIndex);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
  return items;
}

Widget buildAddSectionButton(_FormBuilderScreenState state) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () {
        state._controller.addSection();
      },
      icon: const Icon(Icons.playlist_add, size: 20),
      label: const Text('Add Section', style: TextStyle(fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.highlight,
        backgroundColor: AppColors.cardBg,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: AppColors.highlight.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

Widget buildEmptyState(_FormBuilderScreenState state) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.highlight.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.edit_note, size: 56, color: AppColors.highlight.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 24),
        const Text(
          'Select a template or create a new one',
          style: TextStyle(fontSize: 18, color: AppColors.textDark, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pick a form from the list, or start from scratch.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () {
            state._controller.createNewTemplate();
          },
          icon: const Icon(Icons.add, color: Colors.white, size: 18),
          label: const Text('New Form', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ),
  );
}

void showSystemBlockPicker(_FormBuilderScreenState state, int sectionIndex) {
  showModalBottomSheet(
    context: state.context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Intake Module',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text('These are fixed system blocks with specialized rendering.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            ...systemBlocks.entries.map((entry) {
              final block = entry.value;
              final exists = state._controller.sections.expand((section) => section.fields).any((field) => field.type == entry.key);
              // Only Signature is single-use; Computed Field can be added multiple times
              final isSingleUse = entry.key == FormFieldType.signature;
              final isDisabled = isSingleUse && exists;
              return ListTile(
                leading: Icon(block.icon, color: isDisabled ? AppColors.textMuted : AppColors.highlight),
                title: Text(block.label, style: TextStyle(fontSize: 14, color: isDisabled ? AppColors.textMuted : AppColors.textDark)),
                subtitle: isSingleUse ? Text(exists ? 'Already added' : block.desc, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)) : null,
                enabled: !isDisabled,
                onTap: () {
                  Navigator.pop(ctx);
                  state._controller.addSystemField(sectionIndex, entry.key);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void showSumColumnPicker(_FormBuilderScreenState state, BuilderField field) {
  final tableFields = state._controller.sections.expand((section) => section.fields).where((candidate) => candidate.type == FormFieldType.memberTable).toList();
  if (tableFields.isEmpty) {
    ScaffoldMessenger.of(state.context).showSnackBar(const SnackBar(content: Text('No table fields found in the form.'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
    return;
  }

  showModalBottomSheet(
    context: state.context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Table Field',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text('Choose the table you want to sum.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            ...tableFields.map((tableField) {
              final tableKey = tableField.fieldName;
              final tableLabel = tableField.label.isNotEmpty ? tableField.label : tableField.fieldName;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.table_chart, size: 18, color: AppColors.primaryBlue),
                title: Text(tableLabel),
                onTap: () {
                  Navigator.pop(ctx);
                  showColumnPicker(state, field, tableKey, tableField.columns);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void showColumnPicker(_FormBuilderScreenState state, BuilderField field, String tableKey, List<BuilderColumn> columns) {
  if (columns.isEmpty) {
    ScaffoldMessenger.of(state.context).showSnackBar(const SnackBar(content: Text('No columns found for this table.'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
    return;
  }

  showModalBottomSheet(
    context: state.context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Column',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text('Choose which column to sum.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final column in columns)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.pin, size: 18, color: AppColors.primaryBlue),
                        title: Text('${column.label} (${(column.dbMapKey?.isNotEmpty == true ? column.dbMapKey : column.fieldName)})'),
                        subtitle: Text(column.dbMapKey?.isNotEmpty == true ? column.dbMapKey! : column.fieldName, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                        onTap: () {
                          Navigator.pop(ctx);
                          final columnKey = column.dbMapKey?.isNotEmpty == true ? column.dbMapKey! : column.fieldName;
                          final formula = 'SUM_COLUMN($tableKey, "$columnKey")';
                          state._controller.appendFormulaToken(field, formula);
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
