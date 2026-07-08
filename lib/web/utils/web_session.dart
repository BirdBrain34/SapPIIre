import 'package:flutter/material.dart';

import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';

/// Shared logout for the web staff portal. Centralizes sign-out so every
/// sidebar behaves identically: clear crypto cache + Supabase sign-out
/// (via [WebAuthService.signOut]), clear the persisted session, then wipe
/// the nav stack back to login.
///
/// Screens with extra teardown (e.g. closing an active session) should run
/// that first, then delegate the actual sign-out + redirect here.
class WebSession {
  static Future<void> logout(BuildContext context) async {
    final auth = WebAuthService();
    await auth.clearSession();
    await auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        ContentFadeRoute(page: const WorkerLoginScreen()),
        (route) => false,
      );
    }
  }
}
