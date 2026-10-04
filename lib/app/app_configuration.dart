import 'package:flutter/foundation.dart';

abstract final class AppConfiguration {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The web build is served by the same host as the API, so it falls back to
  /// its own origin and one image works for any domain.
  static bool get isApiConfigured => apiBaseUrl.isNotEmpty || kIsWeb;

  static Uri? get apiBaseUri {
    if (apiBaseUrl.isEmpty) {
      return kIsWeb ? Uri.parse(Uri.base.origin) : null;
    }
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return uri;
  }

  /// A public page of the Nafir site, such as `/privacy`, which is served
  /// from the same origin as the API.
  static Uri? sitePage(String path) => apiBaseUri?.resolve(path);

  /// The share token of a playlist link the web app was opened with
  /// (`/app/?shared=…`), taken only once.
  static String? takeInitialShareToken() {
    if (!kIsWeb || _shareTokenTaken) return null;
    _shareTokenTaken = true;
    final token = Uri.base.queryParameters['shared'];
    return token == null || token.isEmpty ? null : token;
  }

  static bool _shareTokenTaken = false;

  /// The collaboration link the web app was opened with (`/app/?collab=…`),
  /// to join once signed in. Taken only once.
  static String? takeInitialCollabToken() {
    if (!kIsWeb || _collabTokenTaken) return null;
    final token = peekInitialCollabToken();
    _collabTokenTaken = true;
    return token;
  }

  /// The same, without taking it: a guest is asked to sign in first.
  static String? peekInitialCollabToken() {
    if (!kIsWeb || _collabTokenTaken) return null;
    final token = Uri.base.queryParameters['collab'];
    return token == null || token.isEmpty ? null : token;
  }

  static bool _collabTokenTaken = false;
}
