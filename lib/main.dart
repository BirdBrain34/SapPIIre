import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/auth/web_auth_service.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/customer_display_screen.dart';
import 'package:sappiire/web/utils/web_navigator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tgbfxepldpdswxehhlkx.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4',
  );

  await HybridCryptoService.fetchAndCacheRsaPublicKey();

  // On web, try to restore a saved staff session before the app mounts.
  // BUT: skip restoration when the display screen is opened in a new tab,
  // otherwise the restored staff session will redirect it away from /display.
  // The URL is /#/display?station=... so the route is in the hash fragment.
  final bool isDisplayRoute =
      kIsWeb && (Uri.base.fragment.contains('/display') || Uri.base.path.contains('/display'));

  StaffSession? restored;
  bool sessionValid = false;
  if (kIsWeb && !isDisplayRoute) {
    final authService = WebAuthService();
    restored = await authService.restoreSession();
    if (restored != null) {
      final validation = await authService.validateSession(restored.cswdId);
      switch (validation) {
        case SessionValidation.valid:
          sessionValid = true;
          break;
        case SessionValidation.deactivated:
          await authService.clearSession();
          sessionValid = false;
          break;
        case SessionValidation.unreachable:
          sessionValid = true;
          break;
      }
    }
  }

  runApp(MyApp(restoredSession: sessionValid ? restored : null));
}

class MyApp extends StatelessWidget {
  final StaffSession? restoredSession;

  const MyApp({super.key, this.restoredSession});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return MaterialApp(
        title: 'SapPIIre',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFF1A237E),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const LoginScreen(),
      );
    }

    return MaterialApp(
      title: 'SapPIIre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1A237E),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');

        if (uri.path == '/display') {
          final stationId = uri.queryParameters['station'] ?? 'default';
          return MaterialPageRoute(
            builder: (_) => CustomerDisplayScreen(stationId: stationId),
          );
        }

        // If we have a restored valid session, route to the last active screen
        // via a wrapper that navigates to the saved route after the first frame.
        if (restoredSession != null) {
          return MaterialPageRoute(
            builder: (_) => _SessionRestoreWidget(
              session: restoredSession!,
            ),
          );
        }

        return MaterialPageRoute(
          builder: (_) => const WorkerLoginScreen(),
        );
      },
    );
  }
}

/// Wrapper that immediately navigates to the last saved route after the first
/// frame, so the user lands on the exact screen they were on before refresh.
class _SessionRestoreWidget extends StatefulWidget {
  final StaffSession session;
  const _SessionRestoreWidget({required this.session});

  @override
  State<_SessionRestoreWidget> createState() => _SessionRestoreWidgetState();
}

class _SessionRestoreWidgetState extends State<_SessionRestoreWidget> {
  @override
  void initState() {
    super.initState();
    // Navigate to the saved route after the first frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WebNavigator.go(
        context,
        widget.session.lastRoute,
        cswdId: widget.session.cswdId,
        role: widget.session.role,
        displayName: widget.session.displayName,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show a brief loading indicator while we navigate to the saved route.
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}