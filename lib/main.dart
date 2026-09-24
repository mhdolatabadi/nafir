import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/app/backend_gate.dart';
import 'package:nafir/core/api/api_client.dart';

void main() {
  runApp(const ProviderScope(child: NafirApp()));
}

class NafirApp extends StatelessWidget {
  const NafirApp({super.key, this.healthCheck});

  final Future<void> Function()? healthCheck;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nafir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: BackendGate(
        healthCheck: healthCheck ??
            (AppConfiguration.apiBaseUri == null
                ? null
                : ApiClient(AppConfiguration.apiBaseUri!).checkHealth),
      ),
    );
  }
}
