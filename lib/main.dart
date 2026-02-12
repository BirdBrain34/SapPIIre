import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart'; // 1. Add this import
import 'package:sappiire/mobile/screens/auth/login_screen.dart'; 
import 'package:sappiire/web/screen/web_login_screen.dart'; 

// 2. Change main to Future<void> and make it async
Future<void> main() async {
  // 3. Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 4. Initialize Supabase with your project credentials
  await Supabase.initialize(
    url: 'https://tgbfxepldpdswxehhlkx.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SapPIIre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1A237E),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // If running on web, show WorkerLoginScreen. Otherwise, show mobile LoginScreen.
      home: kIsWeb ? const WorkerLoginScreen() : const LoginScreen(), 
    );
  }
}