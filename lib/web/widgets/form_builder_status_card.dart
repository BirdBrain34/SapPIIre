import 'package:flutter/material.dart';


class FormBuilderStatusCard extends StatelessWidget {
  const FormBuilderStatusCard({
    super.key,
    required this.formStatus,
    required this.onArchive,
    required this.onUnpublish,
    required this.onRestore,
  });

  final String formStatus;
  final VoidCallback onArchive;
  final VoidCallback onUnpublish;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final (
      Color color,
      String label,
      String description,
      IconData icon,
    ) = switch (formStatus) {
      'published' => (
        Colors.blue,
        'PUBLISHED',
        'Visible to admin staff in Manage Forms',
        Icons.visibility,
      ),
      'pushed_to_mobile' => (
        Colors.green,
        'LIVE ON MOBILE',
        'Users can fill this form on the mobile app',
        Icons.phone_android,
      ),
      'archived' => (
        Colors.grey,
        'ARCHIVED',
        'Hidden from admins & mobile. Data preserved.',
        Icons.archive_outlined,
      ),
      _ => (
        Colors.orange,
        'DRAFT',
        'Only you can see this template',
        Icons.edit_note,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: $label',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (formStatus != 'archived') ...[
            if (formStatus != 'draft')
              TextButton(
                onPressed: onUnpublish,
                child: const Text('Revert to Draft'),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onArchive,
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Archive'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
            ),
          ],
          if (formStatus == 'archived') ...[
            ElevatedButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore to Draft'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
