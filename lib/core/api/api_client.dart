import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUri, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final Uri baseUri;
  final http.Client _httpClient;

  Future<void> checkHealth() async {
    final response = await _httpClient
        .get(baseUri.resolve('/api/v1/health'))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw ApiException('Server returned HTTP ${response.statusCode}.');
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['status'] != 'ok') {
      throw const ApiException('Server returned an invalid health response.');
    }
  }
}
