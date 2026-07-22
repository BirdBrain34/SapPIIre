/// Utility for conditional logging that is stripped in release builds.
///
/// MobSF flags raw `debugPrint()` calls as a sensitive-logging risk because
/// debug output may contain PII or internal state.  This wrapper ensures all
/// log calls are eliminated when `kReleaseMode` is true, satisfying the
/// remediation requirement without changing every call site at once.
///
/// Usage (preferred for new code):
/// ```dart
/// LogUtil.debugPrint('[MyClass] Something happened: $e');
/// ```
///
/// For a gradual migration, existing `debugPrint(...)` calls can be replaced
/// file-by-file with `LogUtil.debugPrint(...)`.
import 'package:flutter/foundation.dart';

void _noOp(String? message, {int? wrapWidth}) {}

/// A function reference that either logs or no-ops depending on build mode.
///
/// In debug/profile mode this forwards to [debugPrint]; in release mode it
/// silently discards the message.
void Function(String? message, {int? wrapWidth}) logPrint = kReleaseMode
    ? _noOp
    : debugPrint;

/// Convenience wrapper so callers can write `LogUtil.debugPrint(...)`.
class LogUtil {
  static void debugPrint(
    String? message, {
    int? wrapWidth,
  }) {
    logPrint(message, wrapWidth: wrapWidth);
  }
}