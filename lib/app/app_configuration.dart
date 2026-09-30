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

  /// The share token of a playlist link the web app was opened with
  /// (`/?shared=…`), taken only once.
  static String? takeInitialShareToken() {
    if (!kIsWeb || _shareTokenTaken) return null;
    _shareTokenTaken = true;
    final token = Uri.base.queryParameters['shared'];
    return token == null || token.isEmpty ? null : token;
  }

  static bool _shareTokenTaken = false;
}
