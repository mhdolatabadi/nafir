import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sot/app/app_configuration.dart';
import 'package:sot/features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfiguration.initializeSupabase();
  runApp(const ProviderScope(child: SotApp()));
}

class SotApp extends StatelessWidget {
  const SotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
