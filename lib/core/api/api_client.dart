import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nafir/features/auth/data/auth_models.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable error from the API body, for example `email_taken`.
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

abstract interface class AuthApi {
  Future<AuthSession> register(String email, String password);
  Future<AuthSession> login(String email, String password);
  Future<AuthUser> me(String token);
}

abstract interface class TracksApi {
  Future<UploadTicket> createUpload(
      String token, String fileName, int sizeBytes);
  Future<Track> completeUpload(String token, String trackId);
  Future<void> deleteTrack(String token, String trackId);
}

class ApiClient implements AuthApi, TracksApi {
  ApiClient(this.baseUri, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  final Uri baseUri;
  final http.Client _httpClient;

  Future<void> checkHealth() async {
    final body = await _send('GET', '/api/v1/health');
    if (body['status'] != 'ok') {
      throw const ApiException('Server returned an invalid health response.');
    }
  }

  @override
  Future<AuthSession> register(String email, String password) async {
    final body = await _send('POST', '/api/v1/auth/register',
        body: {'email': email, 'password': password});
    return AuthSession.fromJson(body);
  }

  @override
  Future<AuthSession> login(String email, String password) async {
    final body = await _send('POST', '/api/v1/auth/login',
        body: {'email': email, 'password': password});
    return AuthSession.fromJson(body);
  }

  @override
  Future<AuthUser> me(String token) async {
    final body = await _send('GET', '/api/v1/me', token: token);
    return AuthUser.fromJson(body);
  }

  @override
  Future<UploadTicket> createUpload(
      String token, String fileName, int sizeBytes) async {
    final body = await _send('POST', '/api/v1/tracks/uploads',
        token: token, body: {'fileName': fileName, 'sizeBytes': sizeBytes});
    return UploadTicket.fromJson(body);
  }

  @override
  Future<Track> completeUpload(String token, String trackId) async {
    final body =
        await _send('POST', '/api/v1/tracks/$trackId/complete', token: token);
    return Track.fromJson(body);
  }

  @override
  Future<void> deleteTrack(String token, String trackId) async {
    await _send('DELETE', '/api/v1/tracks/$trackId',
        token: token, expectBody: false);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
    bool expectBody = true,
  }) async {
    final request = http.Request(method, baseUri.resolve(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final response = await http.Response.fromStream(
      await _httpClient.send(request).timeout(_timeout),
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded?['error'];
      throw ApiException(
        'Server returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        code: code is String ? code : null,
      );
    }
    if (!expectBody) return const {};
    if (decoded == null) {
      throw const ApiException('Server returned an invalid response.');
    }
    return decoded;
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
