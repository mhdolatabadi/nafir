import 'package:flutter/material.dart';
import 'package:sot/app/app_configuration.dart';
import 'package:sot/features/auth/presentation/sign_in_screen.dart';
import 'package:sot/features/library/presentation/library_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfiguration.isSupabaseConfigured) {
      return const _ConfigurationRequiredScreen();
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        return session == null ? const SignInScreen() : const LibraryScreen();
      },
    );
  }
}

class _ConfigurationRequiredScreen extends StatelessWidget {
  const _ConfigurationRequiredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'برای اجرای SOT، SUPABASE_URL و SUPABASE_ANON_KEY را با --dart-define تنظیم کن.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
