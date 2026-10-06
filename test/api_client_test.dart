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

  test('downloadLink asks for the track download with the token', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({
          'url': 'https://music.example.com/nafir-music/k?sig=1',
          'expiresAt': '2030-01-01T00:00:00Z',
          'fileName': 'My_Song.mp3',
        }),
        200,
      );
    }));

    final link = await client.downloadLink('t0ken', 't1');

    expect(sent.method, 'GET');
    expect(sent.url.toString(),
        'https://music.example.com/api/v1/tracks/t1/download');
    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(link.url.toString(), 'https://music.example.com/nafir-music/k?sig=1');
    expect(link.fileName, 'My_Song.mp3');
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

  test('listTracks parses the library', () async {
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      expect(request.url.path, '/api/v1/tracks');
      expect(request.headers['Authorization'], 'Bearer t0ken');
      return http.Response(
        jsonEncode({
          'tracks': [
            {
              'id': 't1',
              'title': 'آهنگ',
              'artist': null,
              'album': null,
              'albumArtist': 'همخوان',
              'composer': 'Composer',
              'genre': 'Rock',
              'year': 2026,
              'trackNumber': 7,
              'discNumber': 1,
              'comment': 'Demo',
              'durationMs': null,
              'fileName': 'song.mp3',
              'contentType': 'audio/mpeg',
              'sizeBytes': 10,
              'createdAt': '2026-09-24T00:00:00Z',
            },
          ],
          'storage': {'usedBytes': 10, 'limitBytes': 5368709120},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final library = await client.listTracks('t0ken');

    expect(library.tracks.single.title, 'آهنگ');
    expect(library.tracks.single.artist, isNull);
    expect(library.tracks.single.albumArtist, 'همخوان');
    expect(library.tracks.single.composer, 'Composer');
    expect(library.tracks.single.genre, 'Rock');
    expect(library.tracks.single.year, 2026);
    expect(library.tracks.single.trackNumber, 7);
    expect(library.tracks.single.discNumber, 1);
    expect(library.tracks.single.comment, 'Demo');
    expect(library.tracks.single.fileName, 'song.mp3');
    expect(library.usedBytes, 10);
    expect(library.limitBytes, 5368709120);
  });

  test('bot link code is requested with the token and parsed', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({
          'code': '12345678',
          'expiresAt': '2026-09-29T12:10:00Z',
          'bots': [
            {
              'provider': 'bale',
              'name': 'بله',
              'username': 'NafirBot',
              'linkUrl': 'https://ble.ir/NafirBot?start=12345678',
            },
          ],
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));

    final code = await client.createBotLinkCode('t0ken');

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/bots/link-code');
    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(code.code, '12345678');
    expect(code.expiresAt, DateTime.utc(2026, 9, 29, 12, 10));
    expect(code.bots.single.name, 'بله');
    expect(code.bots.single.linkUrl, 'https://ble.ir/NafirBot?start=12345678');
  });

  test('bot list parses bots without links', () async {
    final client = ApiClient(baseUri, httpClient: MockClient((_) async {
      return http.Response(
        jsonEncode({
          'bots': [
            {'provider': 'bale', 'name': 'bale'},
          ],
        }),
        200,
      );
    }));

    final bots = await client.listBots('t0ken');

    expect(bots.single.provider, 'bale');
    expect(bots.single.username, isNull);
    expect(bots.single.linkUrl, isNull);
  });

  test('sending a track to a bot posts the track ID', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response('', 202);
    }));

    await client.sendTrackToBot('t0ken', 'bale', 'track-1');

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/bots/bale/send');
    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(jsonDecode(sent.body), {'trackId': 'track-1'});
  });

  test('track list carries each source and the imports in progress', () async {
    final client = ApiClient(baseUri, httpClient: MockClient((_) async {
      return http.Response(
        jsonEncode({
          'tracks': [
            {
              'id': 't1',
              'title': 'Song',
              'contentType': 'audio/mpeg',
              'sizeBytes': 1,
              'source': 'telegram',
            },
          ],
          'storage': {'usedBytes': 1, 'limitBytes': 10},
          'importsInProgress': 3,
        }),
        200,
      );
    }));

    final library = await client.listTracks('t0ken');

    expect(library.tracks.single.importedFrom, 'تلگرام');
    expect(library.importsInProgress, 3);
  });

  test('updateTrackMetadata patches editable fields', () async {
    late http.Request sent;
    final client = ApiClient(baseUri, httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
        jsonEncode({
          'id': 't1',
          'title': 'New title',
          'artist': null,
          'album': 'Album',
          'albumArtist': 'Album Artist',
          'composer': 'Composer',
          'genre': 'Jazz',
          'year': 2026,
          'trackNumber': 2,
          'discNumber': 1,
          'comment': 'Note',
          'fileName': 'new-title.mp3',
          'contentType': 'audio/mpeg',
          'sizeBytes': 1,
          'version': 4,
        }),
        200,
      );
    }));

    final track = await client.updateTrackMetadata(
      't0ken',
      't1',
      version: 3,
      fileName: 'new-title.mp3',
      title: 'New title',
      artist: null,
      album: 'Album',
      albumArtist: 'Album Artist',
      composer: 'Composer',
      genre: 'Jazz',
      year: 2026,
      trackNumber: 2,
      discNumber: 1,
      comment: 'Note',
    );

    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/tracks/t1');
    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(jsonDecode(sent.body), {
      'version': 3,
      'fileName': 'new-title.mp3',
      'title': 'New title',
      'artist': null,
      'album': 'Album',
      'albumArtist': 'Album Artist',
      'composer': 'Composer',
      'genre': 'Jazz',
      'year': 2026,
      'trackNumber': 2,
      'discNumber': 1,
      'comment': 'Note',
    });
    expect(track.title, 'New title');
    expect(track.version, 4);
    expect(track.artist, isNull);
    expect(track.album, 'Album');
    expect(track.albumArtist, 'Album Artist');
    expect(track.composer, 'Composer');
    expect(track.genre, 'Jazz');
    expect(track.year, 2026);
    expect(track.trackNumber, 2);
    expect(track.discNumber, 1);
    expect(track.comment, 'Note');
    expect(track.fileName, 'new-title.mp3');
  });
}
