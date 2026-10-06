import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/history/application/recently_played_controller.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

/// An in-memory history server.
class FakeHistoryApi implements HistoryApi {
  List<Track> history = [];
  final recorded = <(String, String?)>[];
  Object? error;
  int cleared = 0;

  @override
  Future<List<Track>> listHistory(String token, {int? limit}) async {
    if (error != null) throw error!;
    return history;
  }

  @override
  Future<void> recordPlay(String token, String trackId,
      {String? playlistId}) async {
    recorded.add((trackId, playlistId));
    if (error != null) throw error!;
  }

  @override
  Future<void> clearHistory(String token) async {
    if (error != null) throw error!;
    cleared++;
    history = [];
  }
}

Track track(String id, {String? via, String? shared, Uri? device}) => Track(
      id: id,
      title: id,
      contentType: 'audio/mpeg',
      sizeBytes: 1,
      viaPlaylist: via,
      addedBy: via == null ? null : 'b***@example.com',
      sharedVia: shared,
      sourceUri: device,
    );

void main() {
  group('listenThreshold', () {
    test('is 30 s, or half of a shorter track', () {
      expect(listenThreshold(null), const Duration(seconds: 30));
      expect(listenThreshold(const Duration(minutes: 4)),
          const Duration(seconds: 30));
      expect(listenThreshold(const Duration(seconds: 40)),
          const Duration(seconds: 20));
    });
  });

  group('player', () {
    late FakeAudioEngine engine;
    late PlayerController player;
    late List<String> listened;

    setUp(() {
      engine = FakeAudioEngine();
      listened = [];
      player = PlayerController(
        api: FakeTracksApi(),
        engine: engine,
        token: () => 'tok',
        onListened: (t) => listened.add(t.id),
      );
    });

    void playFor(Duration total, {Duration from = Duration.zero}) {
      const step = Duration(milliseconds: 250);
      for (var at = from + step; at <= from + total; at += step) {
        engine.positionCtl.add(at);
      }
    }

    test('counts a track once after 30 s of listening', () async {
      await player.play(track('a'));
      playFor(const Duration(seconds: 29));
      expect(listened, isEmpty);
      playFor(const Duration(seconds: 10), from: const Duration(seconds: 29));
      expect(listened, ['a']);
    });

    test('a short track counts after half of it', () async {
      await player.play(track('a'));
      engine.durationCtl.add(const Duration(seconds: 20));
      playFor(const Duration(seconds: 10));
      expect(listened, ['a']);
    });

    test('seeking past the music is not listening', () async {
      await player.play(track('a'));
      await player.seek(const Duration(minutes: 2));
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 1));
      expect(listened, isEmpty);
    });

    test('each new play counts again', () async {
      await player.playFrom([track('a'), track('b')], 0);
      playFor(const Duration(seconds: 31));
      await player.next();
      playFor(const Duration(seconds: 31));
      expect(listened, ['a', 'b']);
    });

    test('a track reached gaplessly or by crossfade counts too', () async {
      await player.playFrom([track('a'), track('b')], 0);
      playFor(const Duration(seconds: 31));
      expect(listened, ['a']);
      // Near the end the next track is preloaded; the engine moves on to it
      // by itself instead of the player loading it.
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 31));
      await pumpEventQueue();
      expect(engine.preloaded, 'b');
      engine.advance();
      await pumpEventQueue();
      expect(player.track?.id, 'b');

      playFor(const Duration(seconds: 31));
      expect(listened, ['a', 'b']);
    });
  });

  group('RecentlyPlayedController', () {
    late FakeHistoryApi api;
    late RecentlyPlayedController recent;
    String? token = 'tok';

    setUp(() {
      api = FakeHistoryApi();
      token = 'tok';
      recent = RecentlyPlayedController(api: api, token: () => token);
    });

    test('loads the server history', () async {
      api.history = [track('a'), track('b', via: 'p1')];
      expect(await recent.load(), isTrue);
      expect(recent.status, RecentlyPlayedStatus.loaded);
      expect(recent.tracks.map((t) => t.id), ['a', 'b']);
    });

    test('a failed load is an error', () async {
      api.error = Exception('offline');
      expect(await recent.load(), isFalse);
      expect(recent.status, RecentlyPlayedStatus.error);
    });

    test('recording moves the track to the top and tells the server', () async {
      api.history = [track('a'), track('b')];
      await recent.load();
      await recent.record(track('b'));
      await recent.record(track('m', via: 'p1'));
      expect(recent.tracks.map((t) => t.id), ['m', 'b', 'a']);
      expect(api.recorded, [('b', null), ('m', 'p1')]);
    });

    test('device-only, shared-link and signed-out plays are not kept',
        () async {
      await recent
          .record(track('device:7', device: Uri.parse('content://media/7')));
      await recent.record(track('s', shared: 'tok3n'));
      token = null;
      await recent.record(track('a'));
      expect(api.recorded, isEmpty);
      expect(recent.tracks, isEmpty);
    });

    test('a synced track is kept by its cloud id', () async {
      await recent.record(track('c1', device: Uri.parse('content://media/1')));
      expect(api.recorded, [('c1', null)]);
    });

    test('a failed recording keeps playback state intact', () async {
      api.error = Exception('offline');
      await recent.record(track('a'));
      expect(recent.tracks.map((t) => t.id), ['a']);
    });

    test('remove, clearAll and clear', () async {
      api.history = [track('a'), track('b')];
      await recent.load();
      recent.remove('a');
      expect(recent.tracks.map((t) => t.id), ['b']);
      expect(await recent.clearAll(), isTrue);
      expect(api.cleared, 1);
      expect(recent.tracks, isEmpty);
      recent.clear();
      expect(recent.status, RecentlyPlayedStatus.loading);
    });

    test('resolveRecent prefers the library copy of own tracks', () {
      final edited = Track(
          id: 'a', title: 'Edited', contentType: 'audio/mpeg', sizeBytes: 1);
      final resolved =
          resolveRecent([track('a'), track('m', via: 'p1')], [edited]);
      expect(resolved.first.title, 'Edited');
      expect(resolved.last.viaPlaylist, 'p1');
    });
  });

  group('ApiClient history', () {
    final baseUri = Uri.parse('https://music.example.com');

    test('lists entries, playing others\' tracks through their playlist',
        () async {
      late http.Request sent;
      final client = ApiClient(baseUri, httpClient: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'entries': [
              {
                'playedAt': '2026-10-06T10:00:00Z',
                'playlistId': 'p1',
                'track': {
                  'id': 'm',
                  'title': 'Member song',
                  'contentType': 'audio/mpeg',
                  'sizeBytes': 3,
                  'addedBy': 'b***@example.com',
                },
              },
              {
                'playedAt': '2026-10-06T09:00:00Z',
                'track': {
                  'id': 'a',
                  'title': 'Mine',
                  'contentType': 'audio/mpeg',
                  'sizeBytes': 1,
                },
              },
            ],
          }),
          200,
        );
      }));

      final tracks = await client.listHistory('t0ken', limit: 20);

      expect(sent.url.toString(),
          'https://music.example.com/api/v1/history?limit=20');
      expect(sent.headers['Authorization'], 'Bearer t0ken');
      expect(tracks.map((t) => t.id), ['m', 'a']);
      expect(tracks.first.viaPlaylist, 'p1');
      expect(tracks.last.viaPlaylist, isNull);
    });

    test('records a play and clears the history', () async {
      final sent = <http.Request>[];
      final client = ApiClient(baseUri, httpClient: MockClient((request) async {
        sent.add(request);
        return http.Response('', 204);
      }));

      await client.recordPlay('t0ken', 'a');
      await client.recordPlay('t0ken', 'm', playlistId: 'p1');
      await client.clearHistory('t0ken');

      expect(sent.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/v1/history',
        'POST /api/v1/history',
        'DELETE /api/v1/history',
      ]);
      expect(jsonDecode(sent[0].body), {'trackId': 'a'});
      expect(jsonDecode(sent[1].body), {'trackId': 'm', 'playlistId': 'p1'});
    });
  });
}
