part of 'form_builder_screen.dart';

Widget buildFormBuilderScreen(_FormBuilderScreenState state) {
  return WebShell(
    activePath: 'FormBuilder',
    pageTitle: 'Form Builder',
    pageSubtitle: state._controller.activeTemplateId != null ? '${state._controller.formName}${state._controller.hasUnsavedChanges ? '  -  unsaved changes' : ''}' : 'Create and manage form templates',
    role: state.widget.role,
    cswd_id: state.widget.cswd_id,
    displayName: state.widget.displayName,
    onLogout: state._handleLogout,
    headerActions: buildHeaderActions(state),
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
                  width: 680,
                  child: Column(
                    children: [
                      FormBuilderTitleCard(controller: state._controller, onChanged: () => state._controller.markChanged()),
                      const SizedBox(height: 12),
                      ...buildAllSections(state),
                      const SizedBox(height: 16),
                      buildAddSectionButton(state),
                      const SizedBox(height: 16),
                      FormBuilderStatusCard(
                        formStatus: state._controller.formStatus,
                        onArchive: () {
                          state._archiveTemplateAndSnack();
                        },
                        onUnpublish: () {
                          state._unpublishTemplateAndSnack();
                        },
                        onRestore: () {
                          state._restoreTemplateAndSnack();
                        },
                      ),
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

Widget buildCanvasToolbar(_FormBuilderScreenState state) {
  final targetSectionIndex = state._controller.activeSectionIdx ?? (state._controller.sections.isNotEmpty ? state._controller.sections.length - 1 : null);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    decoration: const BoxDecoration(
      color: AppColors.cardBg,
      border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
    ),
    child: Row(
      children: [
        ElevatedButton.icon(
          onPressed: targetSectionIndex != null
              ? () {
                  state._controller.addField(targetSectionIndex);
                }
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white),
          label: const Text('Add Question', style: TextStyle(color: Colors.white, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: targetSectionIndex != null
              ? () {
                  showSystemBlockPicker(state, targetSectionIndex);
                }
              : null,
          icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
          label: const Text('Add Intake Module', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.highlight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: AppColors.highlight),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const Spacer(),
        if (state._controller.activeSectionIdx != null) Text('Active: ${state._controller.sections[state._controller.activeSectionIdx!].name}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
  return OutlinedButton.icon(
    onPressed: () {
      state._controller.addSection();
    },
    icon: const Icon(Icons.playlist_add, size: 20),
    label: const Text('Add Section'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.highlight,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      side: BorderSide(color: AppColors.highlight.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

Widget buildEmptyState(_FormBuilderScreenState state) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note, size: 80, color: AppColors.highlight.withValues(alpha: 0.3)),
        const SizedBox(height: 24),
        const Text(
          'Select a template or create a new one',
          style: TextStyle(fontSize: 18, color: AppColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            state._controller.createNewTemplate();
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New Form', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );
}

List<Widget> buildHeaderActions(_FormBuilderScreenState state) {
  if (state._controller.activeTemplateId == null) return [];
  return [
    if (state._controller.formStatus == 'draft') ...[
      headerBtn(
        state,
        'Save Draft',
        Icons.save_outlined,
        onPressed: state._controller.isSaving
            ? null
            : () {
                state._saveTemplateAndSnack();
              },
      ),
      const SizedBox(width: 8),
      headerBtn(
        state,
        'Publish',
        Icons.publish,
        color: AppColors.highlight,
        onPressed: () {
          state._publishTemplateAndSnack();
        },
      ),
    ],
    if (state._controller.formStatus == 'published') ...[
      headerBtn(
        state,
        'Save',
        Icons.save_outlined,
        onPressed: state._controller.isSaving
            ? null
            : () {
                state._saveTemplateAndSnack();
              },
      ),
      const SizedBox(width: 8),
      headerBtn(
        state,
        'Push to Mobile',
        Icons.phone_android,
        color: Colors.green,
        onPressed: () {
          state._pushToMobileAndSnack();
        },
      ),
    ],
    if (state._controller.formStatus == 'pushed_to_mobile') ...[
      headerBtn(
        state,
        'Save',
        Icons.save_outlined,
        onPressed: state._controller.isSaving
            ? null
            : () {
                state._saveTemplateAndSnack();
              },
      ),
    ],
    if (state._controller.formStatus == 'archived') ...[
      headerBtn(
        state,
        'Restore',
        Icons.restore,
        color: Colors.teal,
        onPressed: () {
          state._restoreTemplateAndSnack();
        },
      ),
    ],
  ];
}

Widget headerBtn(_FormBuilderScreenState state, String label, IconData icon, {VoidCallback? onPressed, Color? color}) {
  return ElevatedButton.icon(
    onPressed: onPressed,
    icon: state._controller.isSaving && icon == Icons.save_outlined ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(icon, color: Colors.white, size: 18),
    label: Text(
      label,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: color ?? AppColors.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              return ListTile(
                leading: Icon(block.icon, color: exists ? AppColors.textMuted : AppColors.highlight),
                title: Text(block.label, style: TextStyle(fontSize: 14, color: exists ? AppColors.textMuted : AppColors.textDark)),
                subtitle: entry.key == FormFieldType.signature ? Text(exists ? 'Already added' : block.desc, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)) : null,
                enabled: !exists || entry.key == FormFieldType.computed,
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
