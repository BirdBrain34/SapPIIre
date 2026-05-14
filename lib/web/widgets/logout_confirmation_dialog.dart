import 'package:flutter/material.dart';

/// Reusable logout confirmation dialog widget.
///
/// Shows a confirmation dialog before logging out with customizable
/// titles, messages, and button labels.
class LogoutConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const LogoutConfirmationDialog({
    super.key,
    this.title = "Confirm Logout",
    this.message = "Are you sure you want to log out?",
    this.cancelLabel = "Cancel",
    this.confirmLabel = "Log Out",
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel?.call();
          },
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(confirmLabel, style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  /// Static helper method to show the dialog.
  ///
  /// Example usage:
  /// ```dart
  /// LogoutConfirmationDialog.show(
  ///   context: context,
  ///   onConfirm: () => _handleLogout(),
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    String title = "Confirm Logout",
    String message = "Are you sure you want to log out?",
    String cancelLabel = "Cancel",
    String confirmLabel = "Log Out",
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
  }) {
    return showDialog(
      context: context,
      builder: (context) => LogoutConfirmationDialog(
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        onConfirm: onConfirm,
        onCancel: onCancel,
      ),
    );
  }
}
