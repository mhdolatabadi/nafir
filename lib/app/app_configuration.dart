abstract final class AppConfiguration {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;

  static Uri? get apiBaseUri {
    if (!isApiConfigured) return null;
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return uri;
  }
}
