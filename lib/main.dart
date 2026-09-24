import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/app/backend_gate.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/auth/presentation/auth_gate.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/data/storage_uploader.dart';

void main() {
  runApp(const ProviderScope(child: NafirApp()));
}

class NafirApp extends StatefulWidget {
  const NafirApp({
    super.key,
    this.healthCheck,
    this.authApi,
    this.tokenStore,
    this.tracksApi,
    this.uploader,
    this.picker,
  });

  /// Test overrides; by default these talk to [AppConfiguration.apiBaseUri]
  /// and the real device.
  final Future<void> Function()? healthCheck;
  final AuthApi? authApi;
  final TokenStore? tokenStore;
  final TracksApi? tracksApi;
  final StorageUploader? uploader;
  final AudioPicker? picker;

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

  late final TracksApi? _tracksApi = widget.tracksApi ?? _apiClient;
  late final UploadController? _uploads = _tracksApi == null
      ? null
      : UploadController(
          api: _tracksApi,
          uploader: widget.uploader ?? DioStorageUploader(),
          token: () => _auth?.token,
        );

  late final LibraryController? _library = _tracksApi == null
      ? null
      : LibraryController(api: _tracksApi, token: () => _auth?.token);

  @override
  void dispose() {
    _auth?.dispose();
    _uploads?.dispose();
    _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nafir',
      debugShowCheckedModeBanner: false,
      // The UI is Persian only: right-to-left layout and Persian Material
      // strings (tooltips, dialogs), whatever the device language is.
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        fontFamily: 'Vazirmatn',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: BackendGate(
        healthCheck: widget.healthCheck ?? _apiClient?.checkHealth,
        child: _auth == null || _uploads == null || _library == null
            ? const SizedBox.shrink()
            : AuthGate(
                controller: _auth,
                library: _library,
                uploads: _uploads,
                picker: widget.picker ?? FilePickerAudioPicker(),
              ),
      ),
    );
  }
}
