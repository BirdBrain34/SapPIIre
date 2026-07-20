import 'package:flutter/material.dart';

/// Visual descriptor for a form template's lifecycle status.
///
/// Single source of truth for status styling. Consumed by the form-builder
/// action bar's status pill (and anywhere else that needs to render status).
typedef FormStatusDescriptor = ({
  Color color,
  String label,
  String description,
  IconData icon,
});

FormStatusDescriptor statusDescriptor(String formStatus) {
  return switch (formStatus) {
    'published' => (
      color: Colors.blue,
      label: 'PUBLISHED',
      description: 'Visible to admin staff in Manage Forms',
      icon: Icons.visibility,
    ),
    'pushed_to_mobile' => (
      color: Colors.green,
      label: 'LIVE ON MOBILE',
      description: 'Users can fill this form on the mobile app',
      icon: Icons.phone_android,
    ),
    'archived' => (
      color: Colors.grey,
      label: 'ARCHIVED',
      description: 'Hidden from admins & mobile. Data preserved.',
      icon: Icons.archive_outlined,
    ),
    'pending_approval' => (
      color: Colors.deepPurple,
      label: 'PENDING APPROVAL',
      description: 'Awaiting superadmin approval before publishing',
      icon: Icons.hourglass_empty,
    ),
    _ => (
      color: Colors.orange,
      label: 'DRAFT',
      description: 'Only you can see this template',
      icon: Icons.edit_note,
    ),
  };
}
