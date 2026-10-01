import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/widgets/app_loading_screen.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/presentation/sign_in_screen.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/presentation/library_screen.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/presentation/popular_playlists_screen.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';

/// Restores the saved session once, then shows the library, or for a guest
/// the popular playlists, which they can play without an account.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.library,
    this.playlists,
    required this.localAudio,
    required this.uploads,
    required this.cache,
    this.botLinks,
    required this.picker,
    required this.player,
  });

  final AuthController controller;
  final PlayerController player;
  final LibraryController library;
  final PlaylistsController? playlists;
  final LocalAudioController localAudio;
  final UploadController uploads;
  final CacheController cache;
  final BotLinkController? botLinks;
  final AudioPicker picker;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthStatus? _status;

  /// The shared link the app was opened with, for a guest; taken once.
  String? _guestShareToken;
  bool _guestShown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuthChanged);
    widget.controller.restore();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Signing in from a guest screen lands in the library, not back on the
  /// sign-in or playlist page it was opened from.
  void _onAuthChanged() {
    final status = widget.controller.status;
    if (status == AuthStatus.signedIn && _status != AuthStatus.signedIn) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _status = status;
  }

  void _openSignIn() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SignInScreen(controller: widget.controller),
    ));
  }

  Widget _guestHome(PlaylistsController playlists) {
    if (!_guestShown) {
      _guestShown = true;
      _guestShareToken = AppConfiguration.takeInitialShareToken();
    }
    return PopularPlaylistsScreen(
      controller: playlists,
      player: widget.player,
      onSignIn: _openSignIn,
      openShareToken: _guestShareToken,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return switch (controller.status) {
          AuthStatus.restoring => const AppLoadingScreen(),
          AuthStatus.restoreFailed => _RestoreFailedScreen(
              onRetry: controller.restore,
            ),
          AuthStatus.signedOut => widget.playlists == null
              ? SignInScreen(controller: controller)
              : _guestHome(widget.playlists!),
          AuthStatus.signedIn => LibraryScreen(
              email: controller.user!.email,
              onLogout: () {
                // Never show one account's tracks to the next one.
                widget.player.stop();
                widget.library.clear();
                widget.playlists?.clear();
                widget.botLinks?.clear();
                widget.uploads.dismiss();
                controller.logout();
              },
              library: widget.library,
              playlists: widget.playlists,
              localAudio: widget.localAudio,
              player: widget.player,
              uploads: widget.uploads,
              cache: widget.cache,
              botLinks: widget.botLinks,
              picker: widget.picker,
            ),
        };
      },
    );
  }
}

class _RestoreFailedScreen extends StatelessWidget {
  const _RestoreFailedScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('بازیابی ورود قبلی ممکن نشد'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(NafirIcons.arrowsClockwise),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
