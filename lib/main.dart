import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sot/app/app_configuration.dart';
import 'package:sot/app/backend_gate.dart';
import 'package:sot/core/api/api_client.dart';

void main() {
  runApp(const ProviderScope(child: SotApp()));
}

class SotApp extends StatelessWidget {
  const SotApp({super.key, this.healthCheck});

  final Future<void> Function()? healthCheck;

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
      home: BackendGate(
        healthCheck: healthCheck ??
            (AppConfiguration.apiBaseUri == null
                ? null
                : ApiClient(AppConfiguration.apiBaseUri!).checkHealth),
      ),
    );
  }
}
