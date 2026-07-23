/// Banner shown above a submission that was filled against an older version
/// of its form template.
///
/// Tells the staff member what changed between the version the record was
/// captured on and the version the form is on now, and expands a read-only
/// panel holding any saved value whose field has since been removed. Nothing
/// here writes — the archived values are read straight out of the decrypted
/// payload each time the record is opened.
library;

import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/models/form_version_models.dart';

class SubmissionVersionBanner extends StatefulWidget {
  final SubmissionMigration migration;

  const SubmissionVersionBanner({super.key, required this.migration});

  @override
  State<SubmissionVersionBanner> createState() =>
      _SubmissionVersionBannerState();
}

class _SubmissionVersionBannerState extends State<SubmissionVersionBanner> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final migration = widget.migration;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.history,
                size: 18,
                color: AppColors.warningAmber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This record was filled using version '
                      '${migration.submissionVersion} of this form. '
                      'The form is now on version ${migration.currentVersion}.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      migration.summary,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (migration.snapshotMissing) ...[
                      const SizedBox(height: 3),
                      const Text(
                        'No structure snapshot exists for that version, so '
                        'renamed fields cannot be told apart from removed ones.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (migration.archived.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showArchived = !_showArchived),
                  icon: Icon(
                    _showArchived ? Icons.visibility_off : Icons.restore,
                    size: 16,
                  ),
                  label: Text(
                    _showArchived ? 'Hide archived data' : 'Restore archived data',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.midBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (migration.renamed.isNotEmpty) ...[
            const SizedBox(height: 8),
            _RenameNotice(renamed: migration.renamed),
          ],
          // With archived values there is a panel naming each field; without
          // them the labels would go unmentioned otherwise.
          if (migration.archived.isEmpty &&
              migration.removedFieldLabels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Removed from the form: '
              '${migration.removedFieldLabels.join(", ")}.',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (_showArchived) ...[
            const SizedBox(height: 10),
            _ArchivedPanel(archived: migration.archived),
          ],
        ],
      ),
    );
  }
}

/// Renamed fields kept their values, so this is a note, not a warning.
class _RenameNotice extends StatelessWidget {
  final List<RenamedField> renamed;

  const _RenameNotice({required this.renamed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: renamed
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Carried over: "${r.oldName}" is now "${r.newName}" '
                '(${r.label}).',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Read-only rendering of values whose field no longer exists.
class _ArchivedPanel extends StatelessWidget {
  final List<ArchivedFieldValue> archived;

  const _ArchivedPanel({required this.archived});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ARCHIVED DATA',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Captured on this record, but the field it belongs to was removed '
            'from the form. Shown read-only; the saved data is untouched.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          ...archived.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      if (a.archivedAtVersion != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.pageBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'removed in v${a.archivedAtVersion}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      a.displayValue,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
