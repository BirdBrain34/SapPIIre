import 'package:flutter/material.dart';

/// Shows a standard yes/no confirmation dialog and resolves to `true` only when
/// the user taps the confirm action. Dismissing the dialog resolves to `false`.
///
/// When [confirmColor] is null the confirm action renders as a plain
/// [TextButton] (for low-risk confirmations); otherwise it renders as a filled
/// [ElevatedButton] in that color with a white label (for destructive or
/// state-changing actions).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color? confirmColor,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        if (confirmColor == null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          )
        else
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(
              confirmLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    ),
  );
  return confirmed == true;
}
