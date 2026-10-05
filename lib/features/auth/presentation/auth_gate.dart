import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/widgets/app_loading_screen.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/presentation/sign_in_prompt.dart';
import 'package:nafir/features/auth/presentation/sign_in_screen.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/library_sync_controller.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/presentation/library_screen.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/presentation/popular_playlists_screen.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/link_import/application/link_import_controller.dart';
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
    required this.sync,
    required this.cache,
    this.botLinks,
    this.linkImports,
    required this.picker,
    required this.player,
  });

  final AuthController controller;
  final PlayerController player;
  final LibraryController library;
  final PlaylistsController? playlists;
  final LocalAudioController localAudio;
  final UploadController uploads;
  final LibrarySyncController sync;
  final CacheController cache;
  final BotLinkController? botLinks;
  final LinkImportController? linkImports;
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
  /// sign-in or playlist page it was opened from. Signing out, or deleting
  /// the account from Settings, lands on the guest home with nothing of the
  /// account left behind.
  void _onAuthChanged() {
    final status = widget.controller.status;
    if (status == AuthStatus.signedIn && _status != AuthStatus.signedIn) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    if (status == AuthStatus.signedOut && _status == AuthStatus.signedIn) {
      _forgetAccount();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _status = status;
  }

  /// Never show one account's tracks to the next one.
  void _forgetAccount() {
    widget.player.stop();
    widget.library.clear();
    widget.playlists?.clear();
    widget.botLinks?.clear();
    widget.linkImports?.clear();
    widget.uploads.dismiss();
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
      // A collaboration link is joined once signed in; say so.
      if (AppConfiguration.peekInitialCollabToken() != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          askToSignIn(context,
              action: 'پیوستن به فهرست پخش مشترک', onSignIn: _openSignIn);
        });
      }
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
                widget.sync.clear();
                widget.linkImports?.clear();
                widget.uploads.dismiss();
                controller.logout();
              },
              onDeleteAccount: controller.deleteAccount,
              library: widget.library,
              playlists: widget.playlists,
              localAudio: widget.localAudio,
              player: widget.player,
              uploads: widget.uploads,
              sync: widget.sync,
              cache: widget.cache,
              botLinks: widget.botLinks,
              linkImports: widget.linkImports,
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
