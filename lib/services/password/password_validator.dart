import 'package:flutter/material.dart';

/// Result of a password complexity validation.
class PasswordValidationResult {
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecialChar;

  const PasswordValidationResult({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecialChar,
  });

  /// Number of requirements met (0-5).
  int get score =>
      (hasMinLength ? 1 : 0) +
      (hasUppercase ? 1 : 0) +
      (hasLowercase ? 1 : 0) +
      (hasNumber ? 1 : 0) +
      (hasSpecialChar ? 1 : 0);

  /// Human-readable strength label.
  String get label {
    if (score <= 1) return 'Weak';
    if (score == 2) return 'Fair';
    if (score <= 4) return 'Strong';
    return 'Very Strong';
  }

  /// Color representing the strength level.
  Color get color {
    if (score <= 1) return Colors.red;
    if (score == 2) return Colors.orange;
    if (score <= 4) return Colors.amber;
    return Colors.green;
  }

  /// Whether all requirements are met.
  bool get isValid =>
      hasMinLength &&
      hasUppercase &&
      hasLowercase &&
      hasNumber &&
      hasSpecialChar;
}

/// Validates a password string against complexity rules.
PasswordValidationResult validatePassword(String password) {
  return PasswordValidationResult(
    hasMinLength: password.length >= 8,
    hasUppercase: password.contains(RegExp(r'[A-Z]')),
    hasLowercase: password.contains(RegExp(r'[a-z]')),
    hasNumber: password.contains(RegExp(r'[0-9]')),
    hasSpecialChar: password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;`~]')),
  );
}

/// A reusable password strength bar widget.
class PasswordStrengthBar extends StatelessWidget {
  final PasswordValidationResult result;

  const PasswordStrengthBar({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final fraction = result.score / 5.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: Colors.white12,
            color: result.color,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          result.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: result.color,
          ),
        ),
      ],
    );
  }
}

/// A single requirement row with check/uncheck icon.
class PasswordRequirementRow extends StatelessWidget {
  final String label;
  final bool met;
  final Color? metColor;
  final Color? unmetColor;

  const PasswordRequirementRow({
    super.key,
    required this.label,
    required this.met,
    this.metColor,
    this.unmetColor,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = metColor ?? Colors.green;
    final offColor = unmetColor ?? Colors.white38;

    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: met ? onColor : offColor,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: met ? onColor : offColor,
          ),
        ),
      ],
    );
  }
}