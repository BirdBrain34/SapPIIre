import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/mobile/screens/auth/login_screen.dart';
import 'package:sappiire/services/crypto/hybrid_crypto_service.dart';
import 'package:sappiire/web/screen/web_login_screen.dart';
import 'package:sappiire/web/screen/customer_display_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tgbfxepldpdswxehhlkx.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4',
  );

  await HybridCryptoService.fetchAndCacheRsaPublicKey();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Mobile: no URL routing needed, just show login screen.
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

    // Web: use onGenerateRoute so /display?station=X opens the customer monitor.
    return MaterialApp(
      title: 'SapPIIre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1A237E),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');

        // /display?station=desk_1
        if (uri.path == '/display') {
          final stationId = uri.queryParameters['station'] ?? 'default';
          return MaterialPageRoute(
            builder: (_) => CustomerDisplayScreen(stationId: stationId),
          );
        }

        // Everything else → login screen (default behaviour)
        return MaterialPageRoute(
          builder: (_) => const WorkerLoginScreen(),
        );
      },
    );
  }
}
