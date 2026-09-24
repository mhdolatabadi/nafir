import 'package:flutter/material.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/presentation/sign_in_screen.dart';
import 'package:nafir/features/library/presentation/library_screen.dart';

/// Restores the saved session once, then shows sign-in or the library.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller});

  final AuthController controller;

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
          AuthStatus.restoring => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          AuthStatus.restoreFailed => _RestoreFailedScreen(
              onRetry: controller.restore,
            ),
          AuthStatus.signedOut => SignInScreen(controller: controller),
          AuthStatus.signedIn => LibraryScreen(
              email: controller.user!.email,
              onLogout: controller.logout,
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
