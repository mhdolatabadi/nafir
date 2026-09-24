import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/data/auth_models.dart';
import 'package:nafir/features/auth/data/token_store.dart';

enum AuthStatus { restoring, restoreFailed, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  AuthController({required AuthApi api, required TokenStore tokenStore})
      : _api = api,
        _tokenStore = tokenStore;

  final AuthApi _api;
  final TokenStore _tokenStore;

  AuthStatus _status = AuthStatus.restoring;
  AuthUser? _user;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  /// Restores a saved session. A rejected token is discarded; a network
  /// failure keeps it so the user can retry without signing in again.
  Future<void> restore() async {
    _set(AuthStatus.restoring);
    final token = await _tokenStore.read();
    if (token == null) return _set(AuthStatus.signedOut);
    try {
      _set(AuthStatus.signedIn, await _api.me(token));
    } on ApiException catch (error) {
      if (!error.isUnauthorized) return _set(AuthStatus.restoreFailed);
      await _tokenStore.clear();
      _set(AuthStatus.signedOut);
    } catch (_) {
      _set(AuthStatus.restoreFailed);
    }
  }

  Future<void> login(String email, String password) =>
      _start(_api.login(email.trim(), password));

  Future<void> register(String email, String password) =>
      _start(_api.register(email.trim(), password));

  Future<void> logout() async {
    await _tokenStore.clear();
    _set(AuthStatus.signedOut);
  }

  Future<void> _start(Future<AuthSession> request) async {
    final session = await request;
    await _tokenStore.write(session.token);
    _set(AuthStatus.signedIn, session.user);
  }

  void _set(AuthStatus status, [AuthUser? user]) {
    _status = status;
    _user = user;
    notifyListeners();
  }
}
