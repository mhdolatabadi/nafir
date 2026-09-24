import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/app_loading_screen.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/presentation/sign_in_screen.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/presentation/library_screen.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';

/// Restores the saved session once, then shows sign-in or the library.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.library,
    required this.uploads,
    required this.picker,
  });

  final AuthController controller;
  final LibraryController library;
  final UploadController uploads;
  final AudioPicker picker;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.restore();
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
          AuthStatus.signedOut => SignInScreen(controller: controller),
          AuthStatus.signedIn => LibraryScreen(
              email: controller.user!.email,
              onLogout: () {
                // Never show one account's tracks to the next one.
                widget.library.clear();
                widget.uploads.dismiss();
                controller.logout();
              },
              library: widget.library,
              uploads: widget.uploads,
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
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
