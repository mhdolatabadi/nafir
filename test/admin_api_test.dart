import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nafir/core/api/api_client.dart';

void main() {
  final uri = Uri.parse('https://music.example.com');

  test('admin directory encodes search and parses verification', () async {
    final client = ApiClient(uri, httpClient: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.url.path, '/api/v1/admin/accounts');
      expect(request.url.queryParameters,
          {'q': 'a+b@example.com', 'offset': '50'});
      return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': 'u1',
                'email': 'a+b@example.com',
                'createdAt': '2026-01-01T00:00:00Z',
                'verified': true,
                'isAdmin': false,
              }
            ],
            'hasMore': true,
          }),
          200);
    }));
    final page = await client.listAccounts('token',
        query: 'a+b@example.com', offset: 50);
    expect(page.accounts.single.user.verified, isTrue);
    expect(page.accounts.single.user.isAdmin, isFalse);
    expect(page.hasMore, isTrue);
  });

  test('verification patch uses server result and propagates denied access',
      () async {
    final client = ApiClient(uri, httpClient: MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(jsonDecode(request.body), {'verified': false});
      return http.Response('{"error":"admin_required"}', 403);
    }));
    await expectLater(
      client.setAccountVerification('token', 'u1', false),
      throwsA(isA<ApiException>()
          .having((error) => error.statusCode, 'statusCode', 403)),
    );
  });
}
