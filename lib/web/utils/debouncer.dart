import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses a burst of calls into a single trailing invocation.
///
/// Modelled on the recompute debounce in `form_state_controller.dart`, but
/// general purpose. Search boxes need this because every keystroke would
/// otherwise trigger a server-side bulk decrypt.
///
/// Always call [dispose] from the owning `State.dispose`, or a pending timer
/// can fire after the widget is gone.
class Debouncer {
  Debouncer(this.delay);

  /// 320ms — long enough to swallow normal typing, short enough to still feel
  /// responsive between words.
  Debouncer.search() : delay = const Duration(milliseconds: 320);

  final Duration delay;
  Timer? _timer;

  bool get isPending => _timer?.isActive ?? false;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancels any pending call and runs [action] immediately. Use for explicit
  /// submits (Enter key), where waiting out the delay would feel broken.
  void flush(VoidCallback action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
