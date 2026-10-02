import 'package:flutter/material.dart';
import 'package:nafir/features/link_import/application/link_import_controller.dart';
import 'package:nafir/features/link_import/data/link_import.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/app/backend_gate.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/auth/presentation/auth_gate.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/library_sync_controller.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/local_audio_upload.dart';
import 'package:nafir/features/player/application/media_session.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/audio_cache.dart';
import 'package:nafir/features/player/data/audio_engine.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/data/storage_uploader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mediaSession = await startMediaSession();
  runApp(ProviderScope(child: NafirApp(mediaSession: mediaSession)));
}

class NafirApp extends StatefulWidget {
  const NafirApp({
    super.key,
    this.healthCheck,
    this.authApi,
    this.tokenStore,
    this.tracksApi,
    this.playlistsApi,
    this.botsApi,
    this.linkImportsApi,
    this.uploader,
    this.picker,
    this.audioEngine,
    this.audioCache,
    this.localAudioLibrary,
    this.localAudioUpload,
    this.mediaSession,
  });

  /// Test overrides; by default these talk to [AppConfiguration.apiBaseUri]
  /// and the real device.
  final Future<void> Function()? healthCheck;
  final AuthApi? authApi;
  final TokenStore? tokenStore;
  final TracksApi? tracksApi;
  final PlaylistsApi? playlistsApi;
  final BotsApi? botsApi;
  final LinkImportsApi? linkImportsApi;
  final StorageUploader? uploader;
  final AudioPicker? picker;
  final AudioEngine? audioEngine;
  final AudioCache? audioCache;
  final LocalAudioLibrary? localAudioLibrary;
  final LocalAudioUploadSource? localAudioUpload;

  /// System media controls; null in tests and where they are unavailable.
  final NafirAudioHandler? mediaSession;

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
  late final PlaylistsApi? _playlistsApi = widget.playlistsApi ??
      _apiClient ??
      (_tracksApi is PlaylistsApi ? _tracksApi as PlaylistsApi : null);
  late final PlaylistsController? _playlists = _playlistsApi == null
      ? null
      : PlaylistsController(api: _playlistsApi, token: () => _auth?.token);

  late final BotsApi? _botsApi = widget.botsApi ?? _apiClient;
  late final BotLinkController? _botLinks = _botsApi == null
      ? null
      : BotLinkController(api: _botsApi, token: () => _auth?.token);

  late final LinkImportsApi? _linkImportsApi =
      widget.linkImportsApi ?? _apiClient;
  late final LinkImportController? _linkImports = _linkImportsApi == null
      ? null
      : LinkImportController(api: _linkImportsApi, token: () => _auth?.token);

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

  // One cache shared by playback and the Settings screen.
  late final AudioCache _audioCache = widget.audioCache ?? createAudioCache();

  late final PlayerController? _player = _tracksApi == null
      ? null
      : PlayerController(
          api: _tracksApi,
          engine: widget.audioEngine ?? JustAudioEngine(cache: _audioCache),
          token: () => _auth?.token,
        );

  late final LocalAudioController _localAudio = LocalAudioController(
    widget.localAudioLibrary ?? createLocalAudioLibrary(),
  );

  late final LibrarySyncController? _sync = _uploads == null
      ? null
      : LibrarySyncController(
          uploads: _uploads,
          uploadSource:
              widget.localAudioUpload ?? createLocalAudioUploadSource(),
          onUploaded: () async {
            await _library?.load();
          },
        );

  late final CacheController _cache = CacheController(
    cache: _audioCache,
    playing: () => _player?.track?.id,
  );

  @override
  void initState() {
    super.initState();
    final player = _player;
    if (player != null) widget.mediaSession?.attach(player);
  }

  @override
  void dispose() {
    _player?.dispose();
    _auth?.dispose();
    _sync?.dispose();
    _uploads?.dispose();
    _library?.dispose();
    _playlists?.dispose();
    _botLinks?.dispose();
    _linkImports?.dispose();
    _localAudio.dispose();
    _cache.dispose();
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
      theme: NafirTheme.dark(),
      home: BackendGate(
        healthCheck: widget.healthCheck ?? _apiClient?.checkHealth,
        child: _auth == null ||
                _uploads == null ||
                _sync == null ||
                _library == null ||
                _player == null
            ? const SizedBox.shrink()
            : AuthGate(
                controller: _auth,
                player: _player,
                library: _library,
                playlists: _playlists,
                localAudio: _localAudio,
                uploads: _uploads,
                sync: _sync,
                cache: _cache,
                botLinks: _botLinks,
                linkImports: _linkImports,
                picker: widget.picker ?? FilePickerAudioPicker(),
              ),
      ),
    );
  }
}
