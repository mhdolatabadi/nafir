import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/data/playlist.dart';
import 'package:nafir/features/playlists/presentation/shared_playlist_screen.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

const token = 'AAAAAAAAAAAAAAAAAAAAAA';

/// One playlist `p1`, owned by the signed-in user, optionally shared.
class FakePlaylistsApi implements PlaylistsApi {
  String? shareToken;
  bool shareFails = false;
  final shared = <String, SharedPlaylist>{};

  Playlist get playlist => Playlist(
        id: 'p1',
        name: 'mix',
        trackCount: 0,
        tracks: const [],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        shareToken: shareToken,
      );

  @override
  Future<String> sharePlaylist(String t, String playlistId) async {
    if (shareFails) throw const ApiException('500', statusCode: 500);
    return shareToken ??= token;
  }

  @override
  Future<void> unsharePlaylist(String t, String playlistId) async {
    shareToken = null;
  }

  @override
  Future<SharedPlaylist> getSharedPlaylist(String t, String shareToken) async {
    final playlist = shared[shareToken];
    if (playlist == null) {
      throw const ApiException('404', statusCode: 404, code: 'not_found');
    }
    return playlist;
  }

  int? saveStatus;
  final saved = <String>[];

  @override
  Future<Playlist> saveSharedPlaylist(String t, String shareToken) async {
    if (saveStatus != null) {
      throw ApiException('$saveStatus', statusCode: saveStatus);
    }
    saved.add(shareToken);
    return playlist;
  }

  @override
  Future<Playlist> getPlaylist(String t, String id) async => playlist;
  @override
  Future<List<Playlist>> listPlaylists(String t) async => [playlist];
  @override
  Future<Playlist> createPlaylist(String t, String name) async => playlist;
  @override
  Future<Playlist> renamePlaylist(String t, String id, String name) async =>
      playlist;
  @override
  Future<Playlist> replacePlaylistTracks(
          String t, String id, List<String> trackIds) async =>
      playlist;
  @override
  Future<void> deletePlaylist(String t, String id) async {}
}

SharedPlaylist sharedMix() => SharedPlaylist.fromJson(token, {
      'name': 'Friend mix',
      'owner': 'f***@example.com',
      'isOwner': false,
      'tracks': [
        {
          'id': 's1',
          'title': 'Their song',
          'artist': 'Someone',
          'contentType': 'audio/mpeg',
          'sizeBytes': 1,
        },
      ],
    });

void main() {
  group('share links', () {
    test('a link carries the token and can be read back', () {
      final link =
          sharedPlaylistLink(Uri.parse('https://nafir.example.com'), token);
      expect(link.toString(), 'https://nafir.example.com/?shared=$token');
      expect(shareTokenFrom(link.toString()), token);
      expect(shareTokenFrom('  $token '), token);
    });

    test('anything else is not a share link', () {
      for (final input in [
        '',
        'hello',
        'https://nafir.example.com/?shared=short',
        'https://example.com/',
      ]) {
        expect(shareTokenFrom(input), isNull, reason: input);
      }
    });
  });

  test('tracks of a shared playlist play through its link', () async {
    final tracks = FakeTracksApi();
    final player = PlayerController(
        api: tracks, engine: FakeAudioEngine(), token: () => 'tok');
    final playlist = sharedMix();

    expect(playlist.tracks.single.sharedVia, token);
    await player.playFrom(playlist.tracks, 0);

    expect(tracks.calls, contains('shared:$token:s1'));
    expect(tracks.calls.where((c) => c.startsWith('stream:')), isEmpty);
  });

  group('playlists controller', () {
    test('shares, unshares and reports unavailable links', () async {
      final api = FakePlaylistsApi();
      final controller = PlaylistsController(api: api, token: () => 'tok');

      expect(await controller.share('p1'), token);
      expect(await controller.unshare('p1'), isTrue);
      expect(api.shareToken, isNull);
      expect(() => controller.openShared(token),
          throwsA(isA<SharedPlaylistUnavailable>()));

      api.shareFails = true;
      expect(await controller.share('p1'), isNull);
    });
  });

  group('shared playlist screen', () {
    Future<(FakeTracksApi, FakePlaylistsApi)> pump(
        WidgetTester tester, String shareToken) async {
      final tracks = FakeTracksApi();
      final playlists = FakePlaylistsApi()..shared[token] = sharedMix();
      await tester.pumpWidget(MaterialApp(
        home: SharedPlaylistScreen(
          shareToken: shareToken,
          controller: PlaylistsController(api: playlists, token: () => 'tok'),
          player: PlayerController(
              api: tracks, engine: FakeAudioEngine(), token: () => 'tok'),
        ),
      ));
      await tester.pumpAndSettle();
      return (tracks, playlists);
    }

    testWidgets('shows who shared it and plays a track', (tester) async {
      final (tracks, _) = await pump(tester, token);

      expect(find.text('Friend mix'), findsOneWidget);
      expect(
          find.text('اشتراک‌گذاری‌شده توسط f***@example.com'), findsOneWidget);
      await tester.tap(find.text('Their song'));
      await tester.pumpAndSettle();
      expect(tracks.calls, contains('shared:$token:s1'));
    });

    testWidgets('a recipient saves the playlist to their account',
        (tester) async {
      final (_, playlists) = await pump(tester, token);

      await tester.tap(find.text('افزودن به حساب من'));
      await tester.pumpAndSettle();
      expect(playlists.saved, [token]);
      expect(
          find.text(
              'به Playlistها و کتابخانه‌ات اضافه شد. این نسخه مال خودت است.'),
          findsOneWidget);
    });

    testWidgets('no room in the account is explained', (tester) async {
      final (_, playlists) = await pump(tester, token);
      playlists.saveStatus = 413;

      await tester.tap(find.text('افزودن به حساب من'));
      await tester.pumpAndSettle();
      expect(find.textContaining('فضای کافی'), findsOneWidget);
    });

    testWidgets('a revoked or wrong link says so', (tester) async {
      await pump(tester, 'BBBBBBBBBBBBBBBBBBBBBB');
      expect(
          find.text(
              'این لینک اشتباه است یا صاحبش اشتراک‌گذاری را لغو کرده است.'),
          findsOneWidget);
    });
  });

  testWidgets('the owner creates a link, then turns sharing off',
      (tester) async {
    final api = FakePlaylistsApi();
    final controller = PlaylistsController(api: api, token: () => 'tok');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showShareSheet(context,
                playlist: api.playlist, controller: controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ساخت لینک اشتراک'));
    await tester.pumpAndSettle();
    // Without an API origin in tests the sheet shows the code itself.
    expect(find.text(token), findsOneWidget);
    expect(find.text('کپی لینک'), findsOneWidget);

    await tester.tap(find.text('لغو اشتراک (لینک فعلی باطل می‌شود)'));
    await tester.pumpAndSettle();
    expect(api.shareToken, isNull);
    expect(find.text('ساخت لینک اشتراک'), findsOneWidget);
  });

  testWidgets('shared playlist and share sheet fit a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longName =
        'یک Playlist با اسمی بسیار طولانی که نباید از صفحه بیرون بزند ' * 2;
    final playlists = FakePlaylistsApi()
      ..shared[token] = SharedPlaylist.fromJson(token, {
        'name': longName,
        'owner': 'a-very-long-owner-name***@some-very-long-domain.example.com',
        'isOwner': false,
        'tracks': [
          for (var i = 0; i < 30; i++)
            {
              'id': 's$i',
              'title': 'A very long track title number $i that must truncate',
              'artist': 'An artist with an equally long name',
              'contentType': 'audio/mpeg',
              'sizeBytes': 1,
            },
        ],
      });
    final controller = PlaylistsController(api: playlists, token: () => 'tok');
    final player = PlayerController(
        api: FakeTracksApi(), engine: FakeAudioEngine(), token: () => 'tok');
    await tester.pumpWidget(MaterialApp(
      home: SharedPlaylistScreen(
          shareToken: token, controller: controller, player: player),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('افزودن به حساب من'), findsOneWidget);
    await tester.tap(find.textContaining('number 0 '));
    await tester.pumpAndSettle();
    // The mini player is there to pause what was just started.
    expect(find.byTooltip('توقف'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showShareSheet(context,
                playlist: Playlist(
                  id: 'p1',
                  name: longName,
                  trackCount: 0,
                  tracks: const [],
                  createdAt: DateTime.utc(2026),
                  updatedAt: DateTime.utc(2026),
                  shareToken: token,
                ),
                controller: controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('کپی لینک'), findsOneWidget);
  });
}
