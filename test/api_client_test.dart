import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nafir/core/api/api_client.dart';

void main() {
  final baseUri = Uri.parse('https://music.example.com');

  test('login posts credentials and parses the session', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({
          'token': 't0ken',
          'expiresAt': '2030-01-01T00:00:00Z',
          'user': {'id': 'u1', 'email': 'a@example.com'},
        }),
        200,
      );
    }));

    final session = await client.login('a@example.com', 'secret123');

    expect(sent.url.toString(), 'https://music.example.com/api/v1/auth/login');
    expect(jsonDecode(sent.body),
        {'email': 'a@example.com', 'password': 'secret123'});
    expect(session.token, 't0ken');
    expect(session.user.email, 'a@example.com');
  });

  test('me sends the bearer token', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
          jsonEncode({'id': 'u1', 'email': 'a@example.com'}), 200);
    }));

    final user = await client.me('t0ken');

    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(user.id, 'u1');
  });

  test('errors carry the status and API error code', () async {
    final client = ApiClient(baseUri, httpClient: MockClient((_) async {
      return http.Response(jsonEncode({'error': 'email_taken'}), 409);
    }));

    await expectLater(
      client.register('a@example.com', 'secret123'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.code, 'code', 'email_taken')),
    );
  });

  test('a 401 is reported as unauthorized', () async {
    final client = ApiClient(baseUri, httpClient: MockClient((_) async {
      return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
    }));

    await expectLater(
      client.me('expired'),
      throwsA(isA<ApiException>()
          .having((e) => e.isUnauthorized, 'isUnauthorized', true)),
    );
  });
}
