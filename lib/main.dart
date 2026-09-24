import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/app/backend_gate.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/auth/presentation/auth_gate.dart';

void main() {
  runApp(const ProviderScope(child: NafirApp()));
}

class NafirApp extends StatefulWidget {
  const NafirApp({super.key, this.healthCheck, this.authApi, this.tokenStore});

  /// Test overrides; by default both talk to [AppConfiguration.apiBaseUri].
  final Future<void> Function()? healthCheck;
  final AuthApi? authApi;
  final TokenStore? tokenStore;

  @override
  State<NafirApp> createState() => _NafirAppState();
}

class _NafirAppState extends State<NafirApp> {
  late final ApiClient? _apiClient = AppConfiguration.apiBaseUri == null
      ? null
      : ApiClient(AppConfiguration.apiBaseUri!);
  late final AuthApi? _authApi = widget.authApi ?? _apiClient;
  late final AuthController? _auth = _authApi == null
      ? null
      : AuthController(
          api: _authApi,
          tokenStore: widget.tokenStore ?? SecureTokenStore(),
        );

  @override
  void dispose() {
    _auth?.dispose();
    super.dispose();
  }

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
        healthCheck: widget.healthCheck ?? _apiClient?.checkHealth,
        child: _auth == null
            ? const SizedBox.shrink()
            : AuthGate(controller: _auth),
      ),
    );
  }
}
